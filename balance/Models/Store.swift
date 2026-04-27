import SwiftUI

// MARK: - Store

struct Store: Hashable, Codable {
    var selectedMonth: Date = Date()
    var budgetsByMonth: [String: Int] = [:]
    /// Optional per-category budgets per month, stored in cents.
    /// Outer key: YYYY-MM, inner key: Category.storageKey
    var categoryBudgetsByMonth: [String: [String: Int]] = [:]
    var transactions: [Transaction] = []
    // Custom categories created by user.
    // `customCategoriesWithIcons` is the source of truth (Phase 1+).
    // `customCategoryNames` is a Phase 7 legacy field — kept in the schema
    // for one more release so old persisted JSON / old backups still decode.
    // It is migrated into `customCategoriesWithIcons` on load and then emptied;
    // no code path writes to it anymore.
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

    // MARK: - AISubscriptions (Phase 3a)
    var aiSubscriptions: [AISubscription] = []
    var aiSubscriptionCharges: [AISubscriptionCharge] = []
    var aiSubscriptionPriceChanges: [AISubscriptionPriceChange] = []
    /// Merchant keys the user dismissed as "not a subscription" — SubscriptionDetector
    /// skips these on re-runs so the review queue doesn't keep resurfacing them.
    var aiDismissedSubscriptionKeys: [String] = []

    // MARK: - Goal Contributions & Rules (Phase 4b)
    var aiGoalContributions: [AIGoalContribution] = []
    var goalAllocationRules: [GoalAllocationRule] = []

    // MARK: - Net Worth Snapshots (Phase 4c)
    var netWorthSnapshots: [NetWorthSnapshot] = []

    // MARK: - Review Queue dismissals (Phase 6b)
    /// Keys the user has dismissed ("review:<reason>:<id>"). `ReviewQueueService`
    /// filters the queue against this set so dismissed items stay hidden.
    var dismissedReviewKeys: [String] = []

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

    /// Total spent (expenses only) for a given month (cents). Transfer legs
    /// are excluded — moving money between own accounts is not spending.
    func spent(for month: Date) -> Int {
        let cal = Calendar.current
        return transactions
            .filter {
                cal.isDate($0.date, equalTo: month, toGranularity: .month) &&
                $0.type == .expense && !$0.isTransfer
            }
            .reduce(0) { $0 + $1.amount }
    }

    /// Total income for a given month (cents). Transfer legs are excluded.
    func income(for month: Date) -> Int {
        let cal = Calendar.current
        return transactions
            .filter {
                cal.isDate($0.date, equalTo: month, toGranularity: .month) &&
                $0.type == .income && !$0.isTransfer
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

    /// Source of truth for custom categories is `customCategoriesWithIcons`.
    /// `customCategoryNames` is kept for back-compat (legacy persistence + backups)
    /// and is migrated into the icon-bearing list on load — see
    /// `migrateCustomCategoriesIfNeeded()`. Phase 7 will delete the old field.
    var allCategories: [Category] {
        let sorted = customCategoriesWithIcons.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.lowercased() < $1.name.lowercased()
        }
        return Category.allCases + sorted.map { Category.custom($0.name) }
    }

    /// One-way migration: any name in the legacy `customCategoryNames` list that
    /// doesn't yet have a `CustomCategoryModel` entry gets one with default
    /// icon/color. Idempotent — safe to call repeatedly. Returns `true` if any
    /// change was made (so callers can persist). Phase 7: also drains the
    /// legacy list after promoting so subsequent saves don't carry it.
    @discardableResult
    mutating func migrateCustomCategoriesIfNeeded() -> Bool {
        var changed = false
        let existing = Set(customCategoriesWithIcons.map { $0.name.lowercased() })
        var nextOrder = (customCategoriesWithIcons.map(\.sortOrder).max() ?? -1) + 1

        for name in customCategoryNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !existing.contains(trimmed.lowercased()) else { continue }
            customCategoriesWithIcons.append(
                CustomCategoryModel(name: trimmed, sortOrder: nextOrder)
            )
            nextOrder += 1
            changed = true
        }

        // Phase 7: once promoted, never write to the legacy field again.
        if !customCategoryNames.isEmpty {
            customCategoryNames.removeAll()
            changed = true
        }

        // Backfill sortOrder for any records that all share 0
        if customCategoriesWithIcons.count > 1 {
            let allZero = customCategoriesWithIcons.allSatisfy { $0.sortOrder == 0 }
            if allZero {
                let alpha = customCategoriesWithIcons
                    .sorted { $0.name.lowercased() < $1.name.lowercased() }
                for (i, model) in alpha.enumerated() {
                    if let idx = customCategoriesWithIcons.firstIndex(where: { $0.id == model.id }) {
                        customCategoriesWithIcons[idx].sortOrder = i
                    }
                }
                changed = true
            }
        }

        return changed
    }

    /// Whether a custom category name already exists (case-insensitive check).
    /// Also checks against system category names to prevent shadowing.
    func customCategoryNameExists(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }

        // Check system category names
        let systemNames = Category.allCases.map { $0.title.lowercased() }
        if systemNames.contains(trimmed) { return true }

        // Check existing custom categories (icon list is the source of truth)
        if customCategoriesWithIcons.contains(where: { $0.name.lowercased() == trimmed }) { return true }

        return false
    }

    mutating func addCustomCategory(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !customCategoryNameExists(trimmed) else { return }

        // Single source of truth (Phase 7): write only to the icon-bearing list.
        let nextOrder = (customCategoriesWithIcons.map(\.sortOrder).max() ?? -1) + 1
        customCategoriesWithIcons.append(CustomCategoryModel(name: trimmed, sortOrder: nextOrder))
    }

    /// Add a fully-specified custom category (with icon/color).
    /// Used by the editor sheet. Idempotent on duplicates.
    mutating func addCustomCategory(_ model: CustomCategoryModel) {
        let trimmed = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !customCategoryNameExists(trimmed) else { return }

        var copy = model
        copy.name = trimmed
        if copy.sortOrder == 0 {
            copy.sortOrder = (customCategoriesWithIcons.map(\.sortOrder).max() ?? -1) + 1
        }
        customCategoriesWithIcons.append(copy)
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

        // 1. Update customCategoriesWithIcons (name is mutable on the model)
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
        // 1. Remove from customCategoriesWithIcons (single source of truth)
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

    /// Merge the `source` custom category into `target`. Reassigns all
    /// transactions, recurring rules, and category budgets that point at
    /// `source` to point at `target`, then removes `source` from the custom
    /// list. If both have a budget for the same month, the values are summed
    /// (the user's intent is "add this category's spend to that one").
    ///
    /// `target` may be a built-in category or another custom one — only
    /// `source` is required to be a custom name. No-op if names match
    /// (case-insensitive) or if `source` doesn't exist.
    mutating func mergeCustomCategory(source sourceName: String, into target: Category) {
        let trimmed = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if case .custom(let tName) = target, tName.lowercased() == trimmed.lowercased() { return }

        let sourceCat = Category.custom(trimmed)
        let sourceKey = sourceCat.storageKey
        let targetKey = target.storageKey

        // 1. Reassign transactions
        for i in transactions.indices {
            if case .custom(let n) = transactions[i].category, n == trimmed {
                transactions[i].category = target
                transactions[i].lastModified = Date()
            }
        }

        // 2. Reassign recurring
        for i in recurringTransactions.indices {
            if case .custom(let n) = recurringTransactions[i].category, n == trimmed {
                recurringTransactions[i].category = target
            }
        }

        // 3. Merge category budgets (sum on collision)
        for monthKey in categoryBudgetsByMonth.keys {
            guard let sourceValue = categoryBudgetsByMonth[monthKey]?[sourceKey] else { continue }
            let existing = categoryBudgetsByMonth[monthKey]?[targetKey] ?? 0
            categoryBudgetsByMonth[monthKey]?[targetKey] = existing + sourceValue
            categoryBudgetsByMonth[monthKey]?.removeValue(forKey: sourceKey)
        }

        // 4. Remove source from custom list
        customCategoriesWithIcons.removeAll { $0.name == trimmed }
    }

    /// How many entries in each domain reference this custom category. Used to
    /// preview the impact of delete/merge before the user confirms.
    func customCategoryUsage(name: String) -> (transactions: Int, recurring: Int, budgets: Int) {
        let txCount = transactions.reduce(0) { partial, t in
            if case .custom(let n) = t.category, n == name { return partial + 1 }
            return partial
        }
        let recCount = recurringTransactions.reduce(0) { partial, r in
            if case .custom(let n) = r.category, n == name { return partial + 1 }
            return partial
        }
        let key = Category.custom(name).storageKey
        let budgetMonths = categoryBudgetsByMonth.values.filter { ($0[key] ?? 0) > 0 }.count
        return (txCount, recCount, budgetMonths)
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
            var loaded = try decoder.decode(Store.self, from: data)
            // Phase 1: bring legacy string-only custom categories into the
            // icon-bearing list so the rest of the app can render them properly.
            if loaded.migrateCustomCategoriesIfNeeded() {
                _ = loaded.save(userId: userId)
            }
            return loaded
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
