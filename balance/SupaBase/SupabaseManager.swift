import Foundation
import Supabase
import SwiftUI
import Combine

// MARK: - Supabase Manager
// ============================================================
//
// Data access layer for Supabase. Handles CRUD operations
// for transactions, budgets, categories, and recurring items.
//
// Auth state is managed exclusively by AuthManager.
// Sync orchestration is managed by SyncCoordinator.
// This class only provides the raw read/write operations.
//
// ============================================================
@MainActor
class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    /// Implicitly-unwrapped because `setupClient()` guarantees assignment at
    /// init time — if configuration is missing it crashes loudly via
    /// `preconditionFailure` rather than leaving `client` nil for a later
    /// call site to discover with a mystery IUO crash.
    var client: SupabaseClient!

    /// Tracks whether a sync operation is in progress (used internally).
    @Published var isSyncing = false

    /// Auth state — delegates to AuthManager as single source of truth.
    var currentUser: User? { AuthManager.shared.currentUser }

    init() {
        setupClient()
    }

    private func setupClient() {
        let config = AppConfig.shared
        config.validate()

        guard !config.supabaseURL.isEmpty, !config.supabaseAnonKey.isEmpty,
              let supabaseURL = URL(string: config.supabaseURL) else {
            // Crash immediately with a clear diagnostic instead of limping
            // forward with a nil `client` that will crash later via IUO
            // unwrap at some random auth/sync call site. The app is
            // unusable without backend config, so failing at launch is
            // strictly better than failing mid-session.
            SecureLogger.error("Missing Supabase configuration. Check Config.plist.")
            preconditionFailure("Supabase configuration missing or invalid — cannot start app. See Security/SECURITY.md.")
        }

        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: config.supabaseAnonKey
        )

        SecureLogger.info("Supabase client initialized [\(config.environment.rawValue)]")
    }
    
    // MARK: - Auth Methods
    
    func signUp(email: String, password: String, displayName: String? = nil) async throws {
        SecureLogger.info("Starting sign up")

        do {
            let response = try await client.auth.signUp(email: email, password: password)
            SecureLogger.info("Auth sign up successful")

            // Create user profile
            let userId = response.user.id.uuidString

            let userData: [String: String] = [
                "id": userId,
                "email": email,
                "display_name": displayName ?? "User"
            ]

            try await client.database
                .from("users")
                .insert(userData)
                .execute()

            SecureLogger.info("User profile created")

        } catch {
            SecureLogger.error("Sign up failed", error)
            throw error
        }
    }
    
    func signIn(email: String, password: String) async throws {
        SecureLogger.info("Signing in")
        try await client.auth.signIn(email: email, password: password)
        SecureLogger.info("Sign in successful")
    }

    func signOut() throws {
        SecureLogger.info("Signing out")
        Task {
            try await client.auth.signOut()
        }
    }

    func resetPassword(email: String) async throws {
        SecureLogger.info("Password reset requested")
        try await client.auth.resetPasswordForEmail(email)
        SecureLogger.info("Password reset email sent")
    }

    func changePassword(newPassword: String) async throws {
        SecureLogger.info("Changing password")
        try await client.auth.update(user: UserAttributes(password: newPassword))
        SecureLogger.info("Password changed")
    }
    
    // MARK: - Store Sync (Complete Store)
    
    func syncStore(_ localStore: Store) async throws -> Store {
        guard let userId = currentUser?.id.uuidString else {
            throw NSError(domain: "Supabase", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        SecureLogger.info("Syncing store")
        
        // Load all data
        let transactions = try await loadTransactions(userId: userId)
        let budgets = try await loadBudgets(userId: userId)
        let categoryBudgets = try await loadCategoryBudgets(userId: userId)
        let customCategories = try await loadCustomCategories(userId: userId)
        let recurringTransactions = try await loadRecurringTransactions(userId: userId)
        
        // Merge strategy for budgets:
        //   Cloud is authoritative. Local values are only preserved as a
        //   safety net when the cloud has NO entry at all for a given month
        //   (key missing from dictionary). This prevents data loss during
        //   offline edits while still allowing intentional zero-value budgets.
        //
        //   If cloud returns a key (even with value 0), cloud wins.
        //   If cloud is missing a key entirely, local value is kept.
        var mergedBudgets = budgets
        for (key, value) in localStore.budgetsByMonth {
            if mergedBudgets[key] == nil {
                // Cloud doesn't have this month at all — preserve local
                mergedBudgets[key] = value
            }
            // If cloud has the key (even == 0), cloud wins — no override
        }
        var mergedCategoryBudgets = categoryBudgets
        for (monthKey, localCats) in localStore.categoryBudgetsByMonth {
            if mergedCategoryBudgets[monthKey] == nil {
                // Cloud has no data for this month — preserve all local categories
                mergedCategoryBudgets[monthKey] = localCats
            } else {
                // Cloud has this month — only fill in categories cloud is missing entirely
                for (catKey, value) in localCats {
                    if mergedCategoryBudgets[monthKey]?[catKey] == nil {
                        mergedCategoryBudgets[monthKey]?[catKey] = value
                    }
                }
            }
        }

        var syncedStore = localStore
        syncedStore.transactions = transactions
        syncedStore.budgetsByMonth = mergedBudgets
        syncedStore.categoryBudgetsByMonth = mergedCategoryBudgets
        syncedStore.customCategoriesWithIcons = customCategories
        syncedStore.recurringTransactions = recurringTransactions
        
        // ✅ Sync customCategoryNames from server (not merge with local)
        syncedStore.customCategoryNames = customCategories.map { $0.name }.sorted { $0.lowercased() < $1.lowercased() }
        
        SecureLogger.info("Store synced: \(transactions.count) transactions, \(recurringTransactions.count) recurring, \(customCategories.count) custom categories")
        return syncedStore
    }
    
    func saveStore(_ store: Store) async throws {
        guard let userId = currentUser?.id.uuidString else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        SecureLogger.debug("Saving store")
        
        // 1. Hard delete removed transactions from Supabase
        for deletedId in store.deletedTransactionIds {
            if let uuid = UUID(uuidString: deletedId) {
                do {
                    try await deleteTransaction(uuid)
                    SecureLogger.debug("Deleted transaction")
                } catch {
                    SecureLogger.error("Failed to delete transaction")
                }
            }
        }
        
        // 2. Save all active transactions
        for transaction in store.transactions {
            try await saveTransaction(transaction, userId: userId)
        }
        
        // 3. Save budgets + delete removed months from server
        let localBudgetMonths = Set(store.budgetsByMonth.keys)
        
        // Load server budget months
        struct BudgetMonthDTO: Codable { let month: String }
        let serverBudgets: [BudgetMonthDTO] = try await client.database
            .from("budgets")
            .select("month")
            .eq("user_id", value: userId.lowercased())
            .execute()
            .value
        
        // Delete budgets that exist on server but not locally
        for sb in serverBudgets {
            if !localBudgetMonths.contains(sb.month) {
                SecureLogger.debug("Deleting budget and category budgets for month")
                try await client.database
                    .from("budgets")
                    .delete()
                    .eq("user_id", value: userId.lowercased())
                    .eq("month", value: sb.month)
                    .execute()

                // Also delete all category budgets for that month
                try await client.database
                    .from("category_budgets")
                    .delete()
                    .eq("user_id", value: userId.lowercased())
                    .eq("month", value: sb.month)
                    .execute()
            }
        }
        
        for (monthKey, amount) in store.budgetsByMonth {
            if let month = monthKeyToDate(monthKey) {
                try await saveBudget(userId: userId, month: month, amount: amount)
            }
        }
        
        // 4. Save category budgets + clean removed ones
        let localCatBudgetMonths = Set(store.categoryBudgetsByMonth.keys)
        
        for (monthKey, categoriesDict) in store.categoryBudgetsByMonth {
            if let month = monthKeyToDate(monthKey) {
                for (categoryKey, amount) in categoriesDict {
                    try await saveCategoryBudget(userId: userId, month: month, category: categoryKey, amount: amount)
                }
            }
        }
        
        // Delete category budgets for months not in local
        struct CatBudgetMonthDTO: Codable { let month: String }
        let serverCatBudgets: [CatBudgetMonthDTO] = try await client.database
            .from("category_budgets")
            .select("month")
            .eq("user_id", value: userId.lowercased())
            .execute()
            .value
        
        let serverCatMonths = Set(serverCatBudgets.map { $0.month })
        for month in serverCatMonths {
            if !localCatBudgetMonths.contains(month) {
                try await client.database
                    .from("category_budgets")
                    .delete()
                    .eq("user_id", value: userId.lowercased())
                    .eq("month", value: month)
                    .execute()
            }
        }
        
        // 5. Save custom categories
        try await saveCustomCategories(store.customCategoriesWithIcons, userId: userId)
        
        // 6. Save recurring transactions
        try await saveRecurringTransactions(store.recurringTransactions, userId: userId)
        
        SecureLogger.info("Store saved")
    }
    
    // MARK: - Transactions
    
    func saveTransaction(_ transaction: Transaction, userId: String) async throws {
        let dateFormatter = ISO8601DateFormatter()
        
        let data: [String: String] = [
            "id": transaction.id.uuidString,
            "user_id": userId.lowercased(),
            "amount": String(transaction.amount),
            "category": transaction.category.storageKey,
            "type": transaction.type == .income ? "income" : "expense",
            "note": transaction.note,
            "date": dateFormatter.string(from: transaction.date)
        ]
        
        try await client.database
            .from("transactions")
            .upsert(data)
            .execute()
    }
    
    func loadTransactions(userId: String) async throws -> [Transaction] {
        // ⚠️ Important: Supabase stores UUIDs in lowercase, but Swift returns uppercase
        let userIdLowercase = userId.lowercased()
        
        struct TransactionDTO: Codable {
            let id: String
            let amount: Int
            let category: String
            let type: String
            let note: String?
            let date: String
        }
        
        SecureLogger.debug("Loading transactions")

        let response: [TransactionDTO] = try await client.database
            .from("transactions")
            .select()
            .eq("user_id", value: userIdLowercase)
            .order("date", ascending: false)
            .execute()
            .value
        
        SecureLogger.debug("Received \(response.count) transactions")
        
        var parsedCount = 0
        var failedCount = 0
        
        let transactions = response.compactMap { dto -> Transaction? in
            guard let uuid = UUID(uuidString: dto.id) else {
                failedCount += 1
                SecureLogger.error("Failed to parse UUID")
                return nil
            }
            
            // Parse date - handle both "YYYY-MM-DD" and ISO8601 formats
            let date: Date
            if let isoDate = ISO8601DateFormatter().date(from: dto.date) {
                date = isoDate
            } else {
                // Try simple date format "YYYY-MM-DD"
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                
                if let simpleDate = formatter.date(from: dto.date) {
                    date = simpleDate
                } else {
                    failedCount += 1
                    SecureLogger.error("Failed to parse date")
                    return nil
                }
            }
            
            // Parse category from storage key
            let category: Category
            if dto.category.hasPrefix("custom:") {
                let customName = String(dto.category.dropFirst(7))
                category = .custom(customName)
            } else {
                switch dto.category {
                case "groceries": category = .groceries
                case "rent": category = .rent
                case "bills": category = .bills
                case "transport": category = .transport
                case "health": category = .health
                case "education": category = .education
                case "dining": category = .dining
                case "shopping": category = .shopping
                default: category = .other
                }
            }
            
            parsedCount += 1
            
            return Transaction(
                id: uuid,
                amount: dto.amount,
                date: date,
                category: category,
                note: dto.note ?? "",
                type: dto.type == "income" ? .income : .expense
            )
        }
        
        SecureLogger.info("Successfully parsed \(parsedCount) transactions")
        if failedCount > 0 {
            SecureLogger.warning("Failed to parse \(failedCount) transactions")
        }
        
        return transactions
    }
    
    func deleteTransaction(_ transactionId: UUID) async throws {
        guard let userId = currentUser?.id.uuidString.lowercased() else {
            SecureLogger.warning("deleteTransaction: No authenticated user")
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        try await client.database
            .from("transactions")
            .delete()
            .eq("id", value: transactionId.uuidString.lowercased())
            .eq("user_id", value: userId)
            .execute()
    }
    
    // MARK: - Budgets
    
    func saveBudget(userId: String, month: Date, amount: Int) async throws {
        let monthStr = dateToMonthKey(month)
        
        let data: [String: String] = [
            "user_id": userId.lowercased(),
            "month": monthStr,
            "total_amount": String(amount)
        ]
        
        try await client.database
            .from("budgets")
            .upsert(data, onConflict: "user_id,month")
            .execute()
    }
    
    func loadBudgets(userId: String) async throws -> [String: Int] {
        struct BudgetDTO: Codable {
            let month: String
            let total_amount: Int
        }
        
        let response: [BudgetDTO] = try await client.database
            .from("budgets")
            .select()
            .eq("user_id", value: userId.lowercased())
            .execute()
            .value
        
        var budgets: [String: Int] = [:]
        for budget in response {
            budgets[budget.month] = budget.total_amount
        }
        return budgets
    }
    
    // MARK: - Category Budgets
    
    func saveCategoryBudget(userId: String, month: Date, category: String, amount: Int) async throws {
        let monthStr = dateToMonthKey(month)
        
        let data: [String: String] = [
            "user_id": userId.lowercased(),
            "month": monthStr,
            "category": category,
            "amount": String(amount)
        ]
        
        try await client.database
            .from("category_budgets")
            .upsert(data, onConflict: "user_id,month,category")
            .execute()
    }
    
    func loadCategoryBudgets(userId: String) async throws -> [String: [String: Int]] {
        struct CategoryBudgetDTO: Codable {
            let month: String
            let category: String
            let amount: Int
        }
        
        let response: [CategoryBudgetDTO] = try await client.database
            .from("category_budgets")
            .select()
            .eq("user_id", value: userId.lowercased())
            .execute()
            .value
        
        var budgets: [String: [String: Int]] = [:]
        for budget in response {
            if budgets[budget.month] == nil {
                budgets[budget.month] = [:]
            }
            budgets[budget.month]?[budget.category] = budget.amount
        }
        return budgets
    }
    
    // MARK: - Real-time Sync
    
    private var realtimeChannel: RealtimeChannelV2?
    
    func startRealtimeSync(userId: String, onUpdate: @escaping () -> Void) {
        SecureLogger.debug("Real-time sync disabled for now")
        // TODO: Implement real-time sync properly
    }
    
    func stopRealtimeSync() {
        SecureLogger.debug("Stopping real-time sync")
        realtimeChannel = nil
    }
    
    // MARK: - Analytics
    
    func trackEvent(name: String, properties: [String: Any]? = nil) async {
        guard let userId = currentUser?.id.uuidString else { return }
        
        do {
            // Convert properties to JSON string
            var propsJson = "{}"
            if let properties = properties {
                let stringProps = properties.mapValues { "\($0)" }
                if let jsonData = try? JSONSerialization.data(withJSONObject: stringProps),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    propsJson = jsonString
                }
            }
            
            let data: [String: String] = [
                "user_id": userId.lowercased(),
                "event_name": name,
                "event_properties": propsJson
            ]
            
            try await client.database
                .from("events")
                .insert(data)
                .execute()
        } catch {
            SecureLogger.warning("Failed to track event")
        }
    }
    
    func updateLastActive() async throws {
        guard let userId = currentUser?.id.uuidString else { return }
        
        try await client.database
            .from("users")
            .update(["last_active_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: userId)
            .execute()
    }
    
    // MARK: - Delete Month Data
    
    /// حذف کامل داده‌های یک ماه از Supabase
    /// شامل: transactions, budgets, category_budgets
    func deleteMonthData(userId: String, monthKey: String) async throws {
        // Validate the caller's userId matches the authenticated user
        guard let currentId = currentUser?.id.uuidString.lowercased(),
              userId.lowercased() == currentId else {
            SecureLogger.security("deleteMonthData: userId mismatch with authenticated user")
            throw NSError(domain: "SupabaseManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        }

        let userIdLower = userId.lowercased()

        SecureLogger.debug("Deleting month data from Supabase")
        
        // 1. حذف تراکنش‌های این ماه
        // date ها به فرمت ISO8601 هستن: "2026-03-15T..." پس با like فیلتر میکنیم
        // هم فرمت ISO8601 و هم YYYY-MM-DD رو ساپورت میکنه
        try await client.database
            .from("transactions")
            .delete()
            .eq("user_id", value: userIdLower)
            .like("date", pattern: "\(monthKey)%")
            .execute()

        SecureLogger.info("Deleted transactions")
        
        // 2. حذف بودجه کل این ماه
        try await client.database
            .from("budgets")
            .delete()
            .eq("user_id", value: userIdLower)
            .eq("month", value: monthKey)
            .execute()

        SecureLogger.info("Deleted budget")
        
        // 3. حذف category budgets این ماه
        try await client.database
            .from("category_budgets")
            .delete()
            .eq("user_id", value: userIdLower)
            .eq("month", value: monthKey)
            .execute()

        SecureLogger.info("Deleted category budgets")
        SecureLogger.info("Month data fully deleted")
    }
    
    // MARK: - Helpers
    
    private func dateToMonthKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
    
    private func monthKeyToDate(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.date(from: key)
    }
}

// MARK: - Recurring Transactions
extension SupabaseManager {
    
    func saveRecurringTransactions(_ recurring: [RecurringTransaction], userId: String) async throws {
        let userIdLower = userId.lowercased()
        let dateFormatter = ISO8601DateFormatter()
        
        SecureLogger.debug("Saving \(recurring.count) recurring transactions")
        
        // Get existing IDs from server
        struct IdDTO: Codable { let id: String }
        let existing: [IdDTO] = try await client.database
            .from("recurring_transactions")
            .select("id")
            .eq("user_id", value: userIdLower)
            .execute()
            .value
        
        let existingIds = Set(existing.map { $0.id.lowercased() })
        let localIds = Set(recurring.map { $0.id.uuidString.lowercased() })
        
        // Hard delete ones that exist on server but not locally
        let deletedIds = existingIds.subtracting(localIds)
        for deletedId in deletedIds {
            try await client.database
                .from("recurring_transactions")
                .delete()
                .eq("id", value: deletedId)
                .execute()
        }
        
        // Upsert all local recurring
        for item in recurring {
            var data: [String: String] = [
                "id": item.id.uuidString.lowercased(),
                "user_id": userIdLower,
                "name": item.name,
                "amount": String(item.amount),
                "category": item.category.storageKey,
                "frequency": item.frequency.rawValue,
                "start_date": dateFormatter.string(from: item.startDate),
                "is_active": item.isActive ? "true" : "false",
                "payment_method": item.paymentMethod.rawValue,
                "note": item.note
            ]
            
            if let endDate = item.endDate {
                data["end_date"] = dateFormatter.string(from: endDate)
            }
            
            if let lastProcessed = item.lastProcessedDate {
                data["last_processed_date"] = dateFormatter.string(from: lastProcessed)
            }
            
            try await client.database
                .from("recurring_transactions")
                .upsert(data)
                .execute()
        }
        
        SecureLogger.info("Recurring transactions saved (\(recurring.count) upserted, \(deletedIds.count) deleted)")
    }
    
    func loadRecurringTransactions(userId: String) async throws -> [RecurringTransaction] {
        let userIdLower = userId.lowercased()
        
        struct RecurringDTO: Codable {
            let id: String
            let name: String
            let amount: Int
            let category: String
            let frequency: String
            let start_date: String
            let end_date: String?
            let is_active: Bool
            let last_processed_date: String?
            let payment_method: String?
            let note: String?
        }
        
        SecureLogger.debug("Loading recurring transactions")
        
        let response: [RecurringDTO] = try await client.database
            .from("recurring_transactions")
            .select()
            .eq("user_id", value: userIdLower)
            .execute()
            .value
        
        let isoFormatter = ISO8601DateFormatter()
        let simpleFormatter = DateFormatter()
        simpleFormatter.dateFormat = "yyyy-MM-dd"
        simpleFormatter.locale = Locale(identifier: "en_US_POSIX")
        simpleFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        func parseDate(_ str: String) -> Date? {
            isoFormatter.date(from: str) ?? simpleFormatter.date(from: str)
        }
        
        func parseCategory(_ key: String) -> Category {
            if key.hasPrefix("custom:") {
                return .custom(String(key.dropFirst(7)))
            }
            switch key {
            case "groceries": return .groceries
            case "rent": return .rent
            case "bills": return .bills
            case "transport": return .transport
            case "health": return .health
            case "education": return .education
            case "dining": return .dining
            case "shopping": return .shopping
            default: return .other
            }
        }
        
        func parseFrequency(_ raw: String) -> RecurringFrequency {
            switch raw {
            case "daily": return .daily
            case "weekly": return .weekly
            case "monthly": return .monthly
            case "yearly": return .yearly
            default: return .monthly
            }
        }
        
        func parsePaymentMethod(_ raw: String?) -> PaymentMethod {
            guard let raw = raw else { return .card }
            return PaymentMethod(rawValue: raw) ?? .card
        }
        
        let results = response.compactMap { dto -> RecurringTransaction? in
            guard let uuid = UUID(uuidString: dto.id),
                  let startDate = parseDate(dto.start_date) else {
                SecureLogger.error("Failed to parse recurring transaction")
                return nil
            }
            
            return RecurringTransaction(
                id: uuid,
                name: dto.name,
                amount: dto.amount,
                category: parseCategory(dto.category),
                frequency: parseFrequency(dto.frequency),
                startDate: startDate,
                endDate: dto.end_date.flatMap { parseDate($0) },
                isActive: dto.is_active,
                lastProcessedDate: dto.last_processed_date.flatMap { parseDate($0) },
                paymentMethod: parsePaymentMethod(dto.payment_method),
                note: dto.note ?? ""
            )
        }
        
        SecureLogger.info("Loaded \(results.count) recurring transactions")
        return results
    }
}

// MARK: - Custom Categories
extension SupabaseManager {
    
    /// Save custom categories to Supabase
    func saveCustomCategories(_ categories: [CustomCategoryModel], userId: String) async throws {
        SecureLogger.debug("Saving \(categories.count) custom categories")

        let jsonData = try JSONEncoder().encode(categories)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        
        try await client
            .from("users")
            .update(["custom_categories": jsonString])
            .eq("id", value: userId)
            .execute()

        SecureLogger.info("Custom categories saved")

        // Verify it was saved
        let categories = try await loadCustomCategories(userId: userId)
        SecureLogger.debug("Verified: \(categories.count) categories in database")
    }
    
    /// Load custom categories from Supabase
    func loadCustomCategories(userId: String) async throws -> [CustomCategoryModel] {
        SecureLogger.debug("Loading custom categories")
        
        // Try decoding as array first (if JSONB native)
        struct UserDataArray: Decodable {
            let custom_categories: [CustomCategoryModel]?
        }
        
        // Fallback: decode as string (if stored as JSON string)
        struct UserDataString: Decodable {
            let custom_categories: String?
        }
        
        do {
            // Try array format first
            let response: [UserDataArray] = try await client
                .from("users")
                .select("custom_categories")
                .eq("id", value: userId)
                .execute()
                .value

            if let user = response.first,
               let categories = user.custom_categories {
                SecureLogger.info("Loaded \(categories.count) custom categories (array format)")
                return categories
            }
        } catch {
            SecureLogger.debug("Not array format, trying string format")
            
            // Try string format
            do {
                let response: [UserDataString] = try await client
                    .from("users")
                    .select("custom_categories")
                    .eq("id", value: userId)
                    .execute()
                    .value

                if let user = response.first {
                    if let jsonString = user.custom_categories,
                       !jsonString.isEmpty,
                       let jsonData = jsonString.data(using: .utf8) {
                        let categories = try JSONDecoder().decode([CustomCategoryModel].self, from: jsonData)
                        SecureLogger.info("Loaded \(categories.count) custom categories (string format)")
                        return categories
                    }
                }
            } catch let stringError {
                SecureLogger.error("String format failed")

                // Auto-reset to fix corrupted format
                SecureLogger.warning("Auto-resetting custom_categories")
                do {
                    try await client
                        .from("users")
                        .update(["custom_categories": "[]"])
                        .eq("id", value: userId)
                        .execute()
                    SecureLogger.info("Reset complete")
                } catch {
                    SecureLogger.error("Reset failed")
                }
            }
        }

        SecureLogger.debug("Returning empty array")
        return []
    }
}

// MARK: - User Extension
extension User {
    var uid: String {
        id.uuidString
    }
    
    // Note: User already has 'email' property from Supabase
    // No need to override it
    
    var isEmailVerified: Bool {
        // Check if email is confirmed in Supabase
        return emailConfirmedAt != nil
    }
}
