import Foundation

// MARK: - Notifications for cascading cleanup

extension Notification.Name {
    /// Posted when an account is deleted. `userInfo["accountId"]` contains the deleted UUID.
    static let accountDidDelete = Notification.Name("TransactionService.accountDidDelete")
    /// Posted when a goal is deleted. `userInfo["goalId"]` contains the deleted UUID.
    static let goalDidDelete = Notification.Name("TransactionService.goalDidDelete")
}

/// Outcome of a transaction write's **local persistence** step.
///
/// This enum covers ONLY store mutation + UserDefaults write.
/// It intentionally does NOT represent:
/// - Account balance side-effects (async, may still be in flight)
/// - Goal contribution side-effects (async, may still be in flight)
/// - Remote cloud sync (async, handled by ContentView's `onChange(of: store)`)
///
/// Callers receiving `.savedLocally` may show success feedback (haptic, dismiss)
/// because the transaction record itself is durably saved. But they must NOT
/// assume that account balances or goal contributions have finished updating.
enum PersistenceResult {
    /// No mutation was needed (target not found, empty input, already applied).
    /// Store unchanged. No save attempted. No side-effects fired.
    case noChange
    /// Transaction record saved to UserDefaults. Side-effects (balance, goal) dispatched
    /// but NOT yet settled — they run in a background Task and may still be in flight.
    case savedLocally
    /// Store mutated in memory but UserDefaults write failed. Side-effects were still
    /// dispatched (cannot be recalled). Data exists only in memory until next successful save.
    case localSaveFailed
}

/// Single source of truth for all transaction mutations.
///
/// Views gather user input, then call ONE method here.
/// All account-balance, goal-contribution, and household side-effects
/// are owned exclusively by this enum — nowhere else.
///
/// Each `perform*` method:
/// 1. Guards preconditions (returns `.noChange` if target missing, input empty, or already applied)
/// 2. Derives the effective mutation set (filters out absent/duplicate items)
/// 3. Mutates the store in memory
/// 4. Fires side-effects (balance then goal, sequenced per transaction) as background Tasks
/// 5. Saves to UserDefaults synchronously
/// 6. Returns `.savedLocally` or `.localSaveFailed` so callers can react
///
/// **Settlement semantics at return time (applies to ALL perform* methods):**
/// - ✅ SETTLED: Store mutation (synchronous, complete before return)
/// - ✅ SETTLED: Local persistence (UserDefaults written, result returned as PersistenceResult)
/// - ⏳ DEFERRED: Account balance side-effects (async Task, may still be in flight at return)
/// - ⏳ DEFERRED: Goal contribution side-effects (async Task, may still be in flight at return)
/// - ⏳ DEFERRED: Remote cloud sync (handled by ContentView's `onChange(of: store)`)
///
/// Balance/goal side-effects are intentionally deferred because AccountManager and
/// GoalManager are async (they hit Supabase), and perform* methods must remain
/// synchronous (they take `inout Store`). Within each deferred Task, balance is
/// attempted before goal, and all operations are strictly sequential.
@MainActor
enum TransactionService {

    // ================================================================
    // MARK: - Public Write API (the only entry points views should use)
    // ================================================================

    /// Add a new transaction: appends to store, persists to UserDefaults.
    /// Always returns `.savedLocally` or `.localSaveFailed` (never `.noChange` — add always mutates).
    ///
    /// **At return:**
    /// - ✅ SETTLED: transaction appended to store + written to UserDefaults
    /// - ⏳ DEFERRED: account balance adjustment (async Task, may still be in flight)
    /// - ⏳ DEFERRED: goal contribution (async Task, may still be in flight)
    @discardableResult
    static func performAdd(_ transaction: Transaction, store: inout Store) -> PersistenceResult {
        store.transactions.append(transaction)
        fireSideEffectsForAdd(transaction)
        return persist(store: store)
    }

    /// Edit an existing transaction: replaces in store, persists to UserDefaults.
    /// Returns `.noChange` if the transaction is no longer in store.
    ///
    /// **At return:**
    /// - ✅ SETTLED: transaction replaced in store + written to UserDefaults
    /// - ⏳ DEFERRED: old balance reversed → new balance applied (async Task, sequential)
    /// - ⏳ DEFERRED: old goal withdrawn → new goal contributed (async Task, sequential)
    @discardableResult
    static func performEdit(old: Transaction, new: Transaction, store: inout Store) -> PersistenceResult {
        guard let idx = store.transactions.firstIndex(where: { $0.id == old.id }) else {
            return .noChange
        }
        store.transactions[idx] = new
        fireSideEffectsForEdit(old: old, new: new)
        return persist(store: store)
    }

    /// Delete a single transaction: guards existence, removes from store, persists to UserDefaults.
    /// Returns `.noChange` if the transaction is not present in store (no side-effects fired).
    ///
    /// **At return:**
    /// - ✅ SETTLED: transaction removed from store + written to UserDefaults + deletion tracked
    /// - ✅ SETTLED: household split expenses cleaned up (synchronous)
    /// - ⏳ DEFERRED: account balance reversal (async Task, may still be in flight)
    /// - ⏳ DEFERRED: goal contribution withdrawal (async Task, may still be in flight)
    @discardableResult
    static func performDelete(_ transaction: Transaction, store: inout Store) -> PersistenceResult {
        guard store.transactions.contains(where: { $0.id == transaction.id }) else {
            return .noChange
        }
        fireSideEffectsForDelete(transaction)
        HouseholdManager.shared.removeSplitExpenses(forTransaction: transaction.id)
        store.trackDeletion(of: transaction.id)
        store.transactions.removeAll { $0.id == transaction.id }
        return persist(store: store)
    }

    /// Delete multiple transactions in one shot.
    /// Only transactions actually present in store have side-effects fired and are removed.
    /// Absent or duplicate items in the input array are silently skipped.
    @discardableResult
    static func performDeleteBulk(_ transactions: [Transaction], store: inout Store) -> PersistenceResult {
        guard !transactions.isEmpty else { return .noChange }
        // Derive effective set: only transactions present in store, deduplicated by ID.
        let storeIds = Set(store.transactions.map { $0.id })
        var seenIds = Set<UUID>()
        let effective = transactions.filter { tx in
            guard storeIds.contains(tx.id), !seenIds.contains(tx.id) else { return false }
            seenIds.insert(tx.id)
            return true
        }
        guard !effective.isEmpty else { return .noChange }
        fireSideEffectsForBulkDelete(effective)
        applyBulkDeletionToStore(effective, store: &store)
        return persist(store: store)
    }

    /// Clear an entire month: deletes all transactions for the month (with side-effects),
    /// clears month budgets, then persists once. Returns one `PersistenceResult` covering
    /// the entire compound operation.
    @discardableResult
    static func performClearMonth(_ month: Date, store: inout Store) -> PersistenceResult {
        let cal = Calendar.current
        let monthTxs = store.transactions.filter {
            cal.isDate($0.date, equalTo: month, toGranularity: .month)
        }

        // Nothing to clear — no transactions, no budgets
        guard !monthTxs.isEmpty || store.hasMonthData(for: month) else {
            return .noChange
        }

        // 1. Delete transactions with all side-effects (balance, goal, household)
        if !monthTxs.isEmpty {
            fireSideEffectsForBulkDelete(monthTxs)
            applyBulkDeletionToStore(monthTxs, store: &store)
        }

        // 2. Clear budgets for the month
        store.clearMonthBudgets(for: month)

        // 3. One save covering both mutations
        return persist(store: store)
    }

    /// Undo a previous delete: restores transactions, re-applies balance and goal contributions.
    /// Skips any transaction already present in store (prevents duplicate restore and double side-effects).
    ///
    /// Phases:
    /// 1. Derive effective restore set (filter out already-present and within-batch duplicates)
    /// 2. Mutate store (untrack deletions, append transactions)
    /// 3. Fire side-effects ONCE for the effective set (1 async Task)
    /// 4. Persist
    @discardableResult
    static func performUndo(_ transactions: [Transaction], store: inout Store) -> PersistenceResult {
        guard !transactions.isEmpty else { return .noChange }

        // Phase 1: Derive effective restore set
        let existingIds = Set(store.transactions.map { $0.id })
        var seenIds = Set<UUID>()
        let effective = transactions.filter { tx in
            guard !existingIds.contains(tx.id), !seenIds.contains(tx.id) else { return false }
            seenIds.insert(tx.id)
            return true
        }
        guard !effective.isEmpty else { return .noChange }

        // Phase 2: Mutate store
        for tx in effective {
            store.untrackDeletion(of: tx.id)
        }
        store.transactions.append(contentsOf: effective)

        // Phase 3: Side-effects (1 Task for all, balance→goal per tx)
        fireSideEffectsForBulkRestore(effective)

        // Phase 4: Persist
        return persist(store: store)
    }

    // ================================================================
    // MARK: - Cascading Cleanup (account / goal deletion)
    // ================================================================

    /// Call after an account is deleted.
    /// Nils out accountId on all transactions that referenced it and persists immediately.
    /// Returns `.noChange` if no transactions referenced this account.
    ///
    /// **At return:**
    /// - ✅ SETTLED: stale accountId references removed + persisted to UserDefaults
    @discardableResult
    static func didDeleteAccount(_ accountId: UUID, store: inout Store) -> PersistenceResult {
        var changed = false
        for i in store.transactions.indices {
            if store.transactions[i].accountId == accountId {
                store.transactions[i].accountId = nil
                store.transactions[i].lastModified = Date()
                changed = true
            }
        }
        guard changed else { return .noChange }
        return persist(store: store)
    }

    /// Call after a goal is deleted.
    /// Nils out linkedGoalId on all transactions that referenced it and persists immediately.
    /// Returns `.noChange` if no transactions referenced this goal.
    ///
    /// **At return:**
    /// - ✅ SETTLED: stale linkedGoalId references removed + persisted to UserDefaults
    @discardableResult
    static func didDeleteGoal(_ goalId: UUID, store: inout Store) -> PersistenceResult {
        var changed = false
        for i in store.transactions.indices {
            if store.transactions[i].linkedGoalId == goalId {
                store.transactions[i].linkedGoalId = nil
                store.transactions[i].lastModified = Date()
                changed = true
            }
        }
        guard changed else { return .noChange }
        return persist(store: store)
    }

    // ================================================================
    // MARK: - Private: Local Persistence
    // ================================================================

    /// PRIMARY persistence for all transaction mutations.
    /// Saves store to UserDefaults and returns the outcome.
    /// ContentView's `onChange(of: store)` will also save as a secondary safety net —
    /// that double-save is intentional and harmless (idempotent UserDefaults overwrite).
    /// Remote sync is NOT triggered here — ContentView's onChange handles that.
    private static func persist(store: Store) -> PersistenceResult {
        let userId = AuthManager.shared.currentUser?.uid
        return store.save(userId: userId) ? .savedLocally : .localSaveFailed
    }

    // ================================================================
    // MARK: - Private: Side-Effects (balance + goal, sequenced per tx)
    // ================================================================
    //
    // Each helper spawns ONE Task that runs balance then goal sequentially.
    // This ensures: (a) balance is attempted first (higher financial priority),
    // (b) no intra-transaction race between balance and goal effects,
    // (c) bulk operations use 1 Task instead of 2N.

    /// Single Task: adjust account balance, then add goal contribution.
    /// Logs warnings via SecureLogger if either operation fails.
    private static func fireSideEffectsForAdd(_ tx: Transaction) {
        Task {
            // 1. Balance
            if let accountId = tx.accountId {
                let amount = Double(tx.amount) / 100.0
                let ok = await AccountManager.shared.adjustBalance(
                    accountId: accountId, amount: amount, isExpense: tx.type == .expense
                )
                if !ok {
                    SecureLogger.warning("Side-effect failed: balance adjustment after add")
                }
            }
            // 2. Goal contribution
            if tx.type == .income,
               let goalId = tx.linkedGoalId,
               let goal = GoalManager.shared.goals.first(where: { $0.id == goalId }) {
                let note = tx.note.isEmpty ? "From transaction" : tx.note
                let ok = await GoalManager.shared.addContribution(
                    to: goal, amount: tx.amount, note: note, source: .transaction
                )
                if !ok {
                    SecureLogger.warning("Side-effect failed: goal contribution after add")
                }
            }
        }
    }

    /// Single Task: reverse account balance, then reverse goal contribution.
    /// Logs warnings via SecureLogger if either operation fails.
    private static func fireSideEffectsForDelete(_ tx: Transaction) {
        Task {
            // 1. Reverse balance
            if let accountId = tx.accountId {
                let amount = Double(tx.amount) / 100.0
                let ok = await AccountManager.shared.reverseBalanceAdjustment(
                    accountId: accountId, amount: amount, isExpense: tx.type == .expense
                )
                if !ok {
                    SecureLogger.warning("Side-effect failed: balance reversal after delete")
                }
            }
            // 2. Reverse goal contribution
            if tx.type == .income,
               let goalId = tx.linkedGoalId,
               let goal = GoalManager.shared.goals.first(where: { $0.id == goalId }) {
                let ok = await GoalManager.shared.withdrawContribution(
                    from: goal, amount: tx.amount, note: "Reversed: transaction deleted"
                )
                if !ok {
                    SecureLogger.warning("Side-effect failed: goal withdrawal after delete")
                }
            }
        }
    }

    /// Single Task: reverse old balance → apply new balance → withdraw old goal → add new goal.
    /// All four operations sequential in one Task. Logs warnings for each failed step.
    private static func fireSideEffectsForEdit(old: Transaction, new: Transaction) {
        Task {
            // 1. Reverse old balance
            if let oldAccountId = old.accountId {
                let ok = await AccountManager.shared.reverseBalanceAdjustment(
                    accountId: oldAccountId,
                    amount: Double(old.amount) / 100.0,
                    isExpense: old.type == .expense
                )
                if !ok {
                    SecureLogger.warning("Side-effect failed: old balance reversal during edit")
                }
            }
            // 2. Apply new balance
            if let newAccountId = new.accountId {
                let ok = await AccountManager.shared.adjustBalance(
                    accountId: newAccountId,
                    amount: Double(new.amount) / 100.0,
                    isExpense: new.type == .expense
                )
                if !ok {
                    SecureLogger.warning("Side-effect failed: new balance apply during edit")
                }
            }
            // 3. Goal contribution delta (only if goal/amount/type changed)
            let goalChanged = old.linkedGoalId != new.linkedGoalId
            let amountChanged = old.amount != new.amount
            let typeChanged = old.type != new.type
            guard goalChanged || amountChanged || typeChanged else { return }

            // 3a. Withdraw from old goal
            if let oldGId = old.linkedGoalId, old.type == .income,
               let oldGoal = GoalManager.shared.goals.first(where: { $0.id == oldGId }) {
                let ok = await GoalManager.shared.withdrawContribution(
                    from: oldGoal, amount: old.amount, note: "Adjusted: transaction edited"
                )
                if !ok {
                    SecureLogger.warning("Side-effect failed: old goal withdrawal during edit")
                }
            }
            // 3b. Contribute to new goal
            if let newGId = new.linkedGoalId, new.type == .income,
               let newGoal = GoalManager.shared.goals.first(where: { $0.id == newGId }) {
                let note = new.note.isEmpty ? "From transaction (edited)" : new.note
                let ok = await GoalManager.shared.addContribution(
                    to: newGoal, amount: new.amount, note: note, source: .transaction
                )
                if !ok {
                    SecureLogger.warning("Side-effect failed: new goal contribution during edit")
                }
            }
        }
    }

    /// Single Task: process ALL deletion side-effects sequentially.
    /// Replaces 2N Tasks with 1 Task for bulk/month-clear operations.
    /// Logs a warning for each individual failure; continues processing remaining transactions.
    private static func fireSideEffectsForBulkDelete(_ transactions: [Transaction]) {
        guard !transactions.isEmpty else { return }
        Task {
            for tx in transactions {
                // Balance first, then goal — per transaction, sequential
                if let accountId = tx.accountId {
                    let amount = Double(tx.amount) / 100.0
                    let ok = await AccountManager.shared.reverseBalanceAdjustment(
                        accountId: accountId, amount: amount, isExpense: tx.type == .expense
                    )
                    if !ok {
                        SecureLogger.warning("Side-effect failed: balance reversal in bulk delete")
                    }
                }
                if tx.type == .income,
                   let goalId = tx.linkedGoalId,
                   let goal = GoalManager.shared.goals.first(where: { $0.id == goalId }) {
                    let ok = await GoalManager.shared.withdrawContribution(
                        from: goal, amount: tx.amount, note: "Reversed: transaction deleted"
                    )
                    if !ok {
                        SecureLogger.warning("Side-effect failed: goal withdrawal in bulk delete")
                    }
                }
            }
        }
    }

    /// Single Task: process ALL restore side-effects sequentially.
    /// Mirrors `fireSideEffectsForBulkDelete` — one Task for N transactions, balance→goal per tx.
    /// Logs a warning for each individual failure; continues processing remaining transactions.
    private static func fireSideEffectsForBulkRestore(_ transactions: [Transaction]) {
        guard !transactions.isEmpty else { return }
        Task {
            for tx in transactions {
                // Balance first, then goal — per transaction, sequential
                if let accountId = tx.accountId {
                    let amount = Double(tx.amount) / 100.0
                    let ok = await AccountManager.shared.adjustBalance(
                        accountId: accountId, amount: amount, isExpense: tx.type == .expense
                    )
                    if !ok {
                        SecureLogger.warning("Side-effect failed: balance adjustment in bulk restore")
                    }
                }
                if tx.type == .income,
                   let goalId = tx.linkedGoalId,
                   let goal = GoalManager.shared.goals.first(where: { $0.id == goalId }) {
                    let note = tx.note.isEmpty ? "From transaction" : tx.note
                    let ok = await GoalManager.shared.addContribution(
                        to: goal, amount: tx.amount, note: note, source: .transaction
                    )
                    if !ok {
                        SecureLogger.warning("Side-effect failed: goal contribution in bulk restore")
                    }
                }
            }
        }
    }

    // ================================================================
    // MARK: - Private: Bulk Store Mutation
    // ================================================================

    /// Mutate store for bulk deletion: track deleted IDs, remove transactions, clean household splits.
    /// Does NOT fire side-effects or persist — callers handle those separately.
    private static func applyBulkDeletionToStore(_ transactions: [Transaction], store: inout Store) {
        let ids = Set(transactions.map { $0.id })
        HouseholdManager.shared.removeSplitExpenses(forTransactions: ids)
        for tx in transactions {
            store.trackDeletion(of: tx.id)
        }
        store.transactions.removeAll { ids.contains($0.id) }
    }
}
