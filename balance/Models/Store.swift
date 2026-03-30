import SwiftUI

// MARK: - Store

struct Store: Hashable, Codable {
    var selectedMonth: Date = Date()
    var budgetsByMonth: [String: Int] = [:]
    /// Optional per-category budgets per month, stored in cents.
    /// Outer key: YYYY-MM, inner key: Category.storageKey
    var categoryBudgetsByMonth: [String: [String: Int]] = [:]
    var transactions: [Transaction] = []
    // Custom categories created by user
    var customCategoryNames: [String] = []
    var customCategoriesWithIcons: [CustomCategoryModel] = []
    // Track deleted transactions for sync (Array for better JSON compatibility)
    var deletedTransactionIds: [String] = []  // UUID as string

    /// Record a transaction ID as deleted (idempotent — skips if already present).
    mutating func trackDeletion(of id: UUID) {
        let key = id.uuidString
        guard !deletedTransactionIds.contains(key) else { return }
        deletedTransactionIds.append(key)
    }

    /// Remove a transaction ID from the deleted-tracking list (idempotent — no-op if absent).
    mutating func untrackDeletion(of id: UUID) {
        deletedTransactionIds.removeAll { $0 == id.uuidString }
    }

    // MARK: - Recurring Transactions
    var recurringTransactions: [RecurringTransaction] = []

    static func monthKey(_ date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        return String(format: "%04d-%02d", y, m)
    }

    /// Budget for the currently selected month.
    var budgetTotal: Int {
        get { budgetsByMonth[Self.monthKey(selectedMonth)] ?? 0 }
        set { budgetsByMonth[Self.monthKey(selectedMonth)] = max(0, newValue) }
    }

    func budget(for month: Date) -> Int {
        budgetsByMonth[Self.monthKey(month)] ?? 0
    }

    // MARK: - Savings

    /// Total spent (expenses only) for a given month (cents).
    func spent(for month: Date) -> Int {
        let cal = Calendar.current
        return transactions
            .filter {
                cal.isDate($0.date, equalTo: month, toGranularity: .month) &&
                $0.type == .expense
            }
            .reduce(0) { $0 + $1.amount }
    }

    /// Total income for a given month (cents).
    func income(for month: Date) -> Int {
        let cal = Calendar.current
        return transactions
            .filter {
                cal.isDate($0.date, equalTo: month, toGranularity: .month) &&
                $0.type == .income
            }
            .reduce(0) { $0 + $1.amount }
    }

    /// Remaining (budget + income - spent) for a given month (cents).
    func remaining(for month: Date) -> Int {
        budget(for: month) + income(for: month) - spent(for: month)
    }

    /// "Saved" is positive remainder only (never negative).
    /// For current/future months, saved is 0 (because month isn't complete yet).
    func saved(for month: Date) -> Int {
        let cal = Calendar.current
        let now = Date()

        // Only count saved money for months that are FULLY COMPLETE
        if cal.isDate(month, equalTo: now, toGranularity: .month) {
            return 0
        }

        if month > now {
            return 0
        }

        return max(0, remaining(for: month))
    }

    /// Total saved across all COMPLETED months that have a budget set.
    var totalSaved: Int {
        let cal = Calendar.current
        var sum = 0

        for key in budgetsByMonth.keys {
            let parts = key.split(separator: "-")
            guard parts.count == 2,
                  let y = Int(parts[0]),
                  let m = Int(parts[1]) else { continue }

            var comps = DateComponents()
            comps.year = y
            comps.month = m
            comps.day = 1

            guard let d = cal.date(from: comps) else { continue }
            sum += saved(for: d)
        }

        return sum
    }

    /// Saved delta vs previous month (positive => saved more).
    func savedDeltaVsPreviousMonth(for month: Date) -> Int {
        let cal = Calendar.current
        guard let prev = cal.date(byAdding: .month, value: -1, to: month) else { return 0 }

        let now = Date()
        if cal.isDate(month, equalTo: now, toGranularity: .month) || month > now {
            return 0
        }

        return saved(for: month) - saved(for: prev)
    }

    mutating func setBudget(_ value: Int, for month: Date) {
        budgetsByMonth[Self.monthKey(month)] = max(0, value)
    }

    func categoryBudget(for category: Category, month: Date) -> Int {
        categoryBudgetsByMonth[Self.monthKey(month)]?[category.storageKey] ?? 0
    }

    /// Category budget for the currently selected month.
    func categoryBudget(for category: Category) -> Int {
        categoryBudget(for: category, month: selectedMonth)
    }

    mutating func setCategoryBudget(_ value: Int, for category: Category, month: Date) {
        let key = Self.monthKey(month)
        var m = categoryBudgetsByMonth[key] ?? [:]
        m[category.storageKey] = max(0, value)
        categoryBudgetsByMonth[key] = m
    }

    mutating func setCategoryBudget(_ value: Int, for category: Category) {
        setCategoryBudget(value, for: category, month: selectedMonth)
    }

    func totalCategoryBudgets(for month: Date) -> Int {
        let key = Self.monthKey(month)
        return (categoryBudgetsByMonth[key] ?? [:]).values.reduce(0, +)
    }

    func totalCategoryBudgets() -> Int {
        totalCategoryBudgets(for: selectedMonth)
    }

    mutating func add(_ t: Transaction) { transactions.append(t) }

    // MARK: - Import / Restore Validation

    /// Result of a bulk import or restore validation pass.
    struct ImportValidationResult {
        var accepted: [Transaction] = []
        var skippedZeroAmount: Int = 0
        var skippedDuplicateUUID: Int = 0
        var sanitizedAccountIds: Int = 0
        var sanitizedGoalIds: Int = 0

        var totalSkipped: Int { skippedZeroAmount + skippedDuplicateUUID }
        var totalSanitized: Int { sanitizedAccountIds + sanitizedGoalIds }
    }

    /// Validates and sanitizes a batch of transactions for import/restore.
    ///
    /// Checks performed:
    /// 1. `amount > 0` — zero/negative amounts are rejected
    /// 2. No duplicate UUIDs against existing `store.transactions`
    /// 3. No duplicate UUIDs within the batch itself
    /// 4. `accountId` references are cleared if the account does not exist
    /// 5. `linkedGoalId` references are cleared if the goal does not exist
    ///
    /// Returns validated transactions ready for insertion plus skip/sanitize counts.
    func validateForImport(
        _ candidates: [Transaction],
        existingAccountIds: Set<UUID>,
        existingGoalIds: Set<UUID>
    ) -> ImportValidationResult {
        var result = ImportValidationResult()
        let existingUUIDs = Set(transactions.map(\.id))
        var batchUUIDs = Set<UUID>()
        batchUUIDs.reserveCapacity(candidates.count)

        for var tx in candidates {
            // Rule 1: amount must be positive
            guard tx.amount > 0 else {
                result.skippedZeroAmount += 1
                continue
            }

            // Rule 2+3: no UUID collision with store or within batch
            guard !existingUUIDs.contains(tx.id), !batchUUIDs.contains(tx.id) else {
                result.skippedDuplicateUUID += 1
                continue
            }

            // Rule 4: clear orphan accountId
            if let aid = tx.accountId, !existingAccountIds.contains(aid) {
                tx.accountId = nil
                result.sanitizedAccountIds += 1
            }

            // Rule 5: clear orphan linkedGoalId
            if let gid = tx.linkedGoalId, !existingGoalIds.contains(gid) {
                tx.linkedGoalId = nil
                result.sanitizedGoalIds += 1
            }

            batchUUIDs.insert(tx.id)
            result.accepted.append(tx)
        }

        return result
    }

    mutating func flagTransaction(id: UUID, flagged: Bool = true) {
        if let idx = transactions.firstIndex(where: { $0.id == id }) {
            transactions[idx].isFlagged = flagged
            transactions[idx].lastModified = Date()
        }
    }

    mutating func linkTransactionToGoal(id: UUID, goalId: UUID?) {
        if let idx = transactions.firstIndex(where: { $0.id == id }) {
            transactions[idx].linkedGoalId = goalId
            transactions[idx].lastModified = Date()
        }
    }

    /// Removes budgets and category budgets for a month.
    /// Transaction deletion should go through TransactionService.performDeleteBulk instead.
    mutating func clearMonthBudgets(for month: Date) {
        let key = Self.monthKey(month)
        budgetsByMonth.removeValue(forKey: key)
        categoryBudgetsByMonth.removeValue(forKey: key)
    }

    /// Returns true if the given month has any stored data (transactions or budgets/caps).
    func hasMonthData(for month: Date) -> Bool {
        let key = Self.monthKey(month)
        let cal = Calendar.current

        let hasTx = transactions.contains { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
        let hasBudget = (budgetsByMonth[key] ?? 0) > 0
        let hasCaps = (categoryBudgetsByMonth[key] ?? [:]).values.contains { $0 > 0 }

        return hasTx || hasBudget || hasCaps
    }

    var allCategories: [Category] {
        let namesFromIcons = customCategoriesWithIcons.map { $0.name }
        let allCustomNames = Set(customCategoryNames + namesFromIcons)
        return Category.allCases + allCustomNames.sorted().map { Category.custom($0) }
    }

    /// Whether a custom category name already exists (case-insensitive check).
    /// Also checks against system category names to prevent shadowing.
    func customCategoryNameExists(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }

        // Check system category names
        let systemNames = Category.allCases.map { $0.title.lowercased() }
        if systemNames.contains(trimmed) { return true }

        // Check existing custom categories (both name lists)
        if customCategoryNames.contains(where: { $0.lowercased() == trimmed }) { return true }
        if customCategoriesWithIcons.contains(where: { $0.name.lowercased() == trimmed }) { return true }

        return false
    }

    mutating func addCustomCategory(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !customCategoryNameExists(trimmed) else { return }

        customCategoryNames.append(trimmed)
        customCategoryNames.sort { $0.lowercased() < $1.lowercased() }
    }

    /// Rename a custom category atomically.
    /// Updates: customCategoryNames, customCategoriesWithIcons, all transactions,
    /// and all budget mappings that reference the old name.
    mutating func renameCustomCategory(oldName: String, newName: String) {
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNew.isEmpty, oldName != trimmedNew else { return }

        // Don't rename if the new name conflicts with an existing category
        // (allow case-only renames of the same category)
        if oldName.lowercased() != trimmedNew.lowercased() && customCategoryNameExists(trimmedNew) {
            return
        }

        // 1. Update customCategoryNames
        if let idx = customCategoryNames.firstIndex(of: oldName) {
            customCategoryNames[idx] = trimmedNew
        } else {
            // Old name wasn't in customCategoryNames — add the new one
            customCategoryNames.append(trimmedNew)
        }
        customCategoryNames.sort { $0.lowercased() < $1.lowercased() }

        // 2. Update customCategoriesWithIcons (name is mutable on the model)
        if let idx = customCategoriesWithIcons.firstIndex(where: { $0.name == oldName }) {
            customCategoriesWithIcons[idx].name = trimmedNew
        }

        // 3. Update all transactions referencing the old category name
        for i in transactions.indices {
            if case .custom(let catName) = transactions[i].category, catName == oldName {
                transactions[i].category = .custom(trimmedNew)
                transactions[i].lastModified = Date()
            }
        }

        // 4. Migrate budget keys from old storageKey to new storageKey
        let oldKey = Category.custom(oldName).storageKey
        let newKey = Category.custom(trimmedNew).storageKey
        for monthKey in categoryBudgetsByMonth.keys {
            if let value = categoryBudgetsByMonth[monthKey]?[oldKey] {
                categoryBudgetsByMonth[monthKey]?.removeValue(forKey: oldKey)
                categoryBudgetsByMonth[monthKey]?[newKey] = value
            }
        }

        // 5. Update recurring transactions referencing the old category
        for i in recurringTransactions.indices {
            if case .custom(let catName) = recurringTransactions[i].category, catName == oldName {
                recurringTransactions[i].category = .custom(trimmedNew)
            }
        }
    }

    mutating func deleteCustomCategory(name: String) {
        // 1. Remove from customCategoryNames
        customCategoryNames.removeAll { $0 == name }

        // 2. Remove from customCategoriesWithIcons
        customCategoriesWithIcons.removeAll { $0.name == name }

        // 3. Update all transactions using this category to "Other"
        for i in transactions.indices {
            if case .custom(let catName) = transactions[i].category, catName == name {
                transactions[i].category = .other
                transactions[i].lastModified = Date()
            }
        }

        // 4. Remove category budgets for this category (all months)
        let categoryKey = Category.custom(name).storageKey
        for monthKey in categoryBudgetsByMonth.keys {
            categoryBudgetsByMonth[monthKey]?.removeValue(forKey: categoryKey)
        }

        // 5. Update recurring transactions using this category to "Other"
        for i in recurringTransactions.indices {
            if case .custom(let catName) = recurringTransactions[i].category, catName == name {
                recurringTransactions[i].category = .other
            }
        }
    }

    /// Remove budget keys that reference categories which no longer exist.
    /// Call after import/restore to clean up stale state.
    mutating func purgeStaleCustomCategoryBudgetKeys() {
        let validKeys = Set(allCategories.map { $0.storageKey })
        for monthKey in categoryBudgetsByMonth.keys {
            guard var month = categoryBudgetsByMonth[monthKey] else { continue }
            let staleKeys = month.keys.filter { !validKeys.contains($0) }
            for key in staleKeys {
                month.removeValue(forKey: key)
            }
            categoryBudgetsByMonth[monthKey] = month
        }
    }

    // MARK: - Custom Category Helpers

    func customCategoryIcon(for name: String) -> String {
        if let custom = customCategoriesWithIcons.first(where: { $0.name == name }) {
            return custom.icon
        }
        return "tag"
    }

    func customCategoryColor(for name: String) -> Color {
        if let custom = customCategoriesWithIcons.first(where: { $0.name == name }) {
            return custom.color
        }
        return .gray
    }

    // MARK: - Persistence

    private static let storageKey = "balance.store.v1"

    /// Set to `true` if `load()` found data but could not decode it.
    /// ContentView checks this on launch to warn the user.
    static var didLoadCorruptData = false

    static func load(userId: String? = nil) -> Store {
        didLoadCorruptData = false

        let key: String
        if let userId = userId {
            key = "store_\(userId)"
        } else {
            key = storageKey
        }

        guard let data = UserDefaults.standard.data(forKey: key) else {
            return Store()
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Store.self, from: data)
        } catch {
            SecureLogger.error("Store load failed — data corrupted, backing up and returning empty store", error)
            // Preserve corrupt data under a backup key so it can be recovered
            UserDefaults.standard.set(data, forKey: "\(key)_backup_corrupt")
            didLoadCorruptData = true
            return Store()
        }
    }

    @discardableResult
    func save(userId: String? = nil) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(self)

            let key: String
            if let userId = userId {
                key = "store_\(userId)"
            } else {
                key = Self.storageKey
            }

            UserDefaults.standard.set(data, forKey: key)
            return true
        } catch {
            SecureLogger.error("Store save failed — data may not persist", error)
            return false
        }
    }
}
