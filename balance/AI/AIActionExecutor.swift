import Foundation

// ============================================================
// MARK: - AI Action Executor
// ============================================================
//
// Takes confirmed AIActions and applies them to the real data
// layer (Store, GoalManager, AccountManager, etc.).
// Returns a user-facing summary of what was done.
//
// ============================================================

enum AIActionExecutor {

    struct ExecutionResult {
        let action: AIAction
        let success: Bool
        let summary: String
        var undoData: _LegacyUndoData = .nonUndoable
    }

    /// Execute a single confirmed action. Returns a result with a human summary.
    @MainActor
    static func execute(_ action: AIAction, store: inout Store) async -> ExecutionResult {
        switch action.type {

        // ── Transactions ──

        case .addTransaction:
            return addTransaction(action, store: &store)

        case .editTransaction:
            return editTransaction(action, store: &store)

        case .deleteTransaction:
            return deleteTransaction(action, store: &store)

        case .splitTransaction:
            return splitTransaction(action, store: &store)

        // ── Transfers ──

        case .transfer:
            return await transfer(action)

        // ── Recurring ──

        case .addRecurring:
            return addRecurring(action, store: &store)

        case .editRecurring:
            return editRecurring(action, store: &store)

        case .cancelRecurring:
            return cancelRecurring(action, store: &store)

        // ── Budget ──

        case .setBudget, .adjustBudget:
            return setBudget(action, store: &store)

        case .setCategoryBudget:
            return setCategoryBudget(action, store: &store)

        // ── Goals ──

        case .createGoal:
            return await createGoal(action)

        case .addContribution:
            return await addContribution(action)

        case .updateGoal:
            return await updateGoal(action)

        // ── Subscriptions ──

        case .addSubscription:
            return addSubscription(action, store: &store)

        case .cancelSubscription:
            return cancelSubscription(action)

        // ── Accounts ──

        case .updateBalance:
            return await updateBalance(action)

        // ── Analysis (no mutation) ──

        case .analyze, .compare, .forecast, .advice:
            return ExecutionResult(action: action, success: true, summary: "")
        }
    }

    /// Execute all confirmed actions in order.
    @MainActor
    static func executeAll(_ actions: [AIAction], store: inout Store) async -> [ExecutionResult] {
        var results: [ExecutionResult] = []
        for action in actions where action.status == .confirmed {
            let result = await execute(action, store: &store)
            results.append(result)
        }
        return results
    }

    // MARK: - Transaction Handlers

    @MainActor
    private static func addTransaction(_ action: AIAction, store: inout Store) -> ExecutionResult {
        let p = action.params
        guard let amount = p.amount else {
            return ExecutionResult(action: action, success: false, summary: "Missing amount")
        }

        // Use AI-provided category, or auto-suggest from note if missing
        let category: Category
        if let catKey = p.category, Category(storageKey: catKey) != nil {
            category = resolveCategory(catKey, store: store)
        } else if let note = p.note, let suggested = AICategorySuggester.shared.suggest(note: note) {
            category = suggested
        } else {
            category = resolveCategory(p.category, store: store)
        }

        let date = resolveDate(p.date)
        let txnType: TransactionType = p.transactionType == "income" ? .income : .expense

        let txn = Transaction(
            amount: amount,
            date: date,
            category: category,
            note: p.note ?? "",
            paymentMethod: .card,
            type: txnType
        )
        store.add(txn)

        // Teach auto-categorizer from this transaction
        if let note = p.note, !note.isEmpty {
            AICategorySuggester.shared.learn(note: note, category: category)
        }

        // Trigger event-driven insight
        AIInsightEngine.shared.onTransactionAdded(txn, store: store)

        let label = txnType == .income ? "income" : "expense"
        return ExecutionResult(
            action: action, success: true,
            summary: "Added \(label): \(formatCents(amount)) [\(category.title)]",
            undoData: .addedTransaction(transactionId: txn.id)
        )
    }

    @MainActor
    private static func editTransaction(_ action: AIAction, store: inout Store) -> ExecutionResult {
        let p = action.params
        guard let idStr = p.transactionId, let uuid = UUID(uuidString: idStr),
              let idx = store.transactions.firstIndex(where: { $0.id == uuid }) else {
            return ExecutionResult(action: action, success: false, summary: "Transaction not found")
        }

        // Capture old values for undo
        let old = store.transactions[idx]
        let undoData: _LegacyUndoData = .editedTransaction(
            transactionId: uuid,
            oldAmount: old.amount,
            oldCategory: old.category.storageKey,
            oldNote: old.note,
            oldDate: old.date,
            oldType: old.type == .income ? "income" : "expense"
        )

        if let amount = p.amount { store.transactions[idx].amount = amount }
        if let cat = p.category {
            let newCategory = resolveCategory(cat, store: store)
            let oldCatKey = old.category.storageKey
            let newCatKey = newCategory.storageKey
            store.transactions[idx].category = newCategory

            // Phase 7: Record category correction for memory learning
            if oldCatKey != newCatKey && !old.note.isEmpty {
                AIMerchantMemory.shared.learnCorrection(merchantNote: old.note, correctCategory: newCatKey)
                AIMemoryStore.shared.recordCorrection(merchant: old.note, fromCategory: oldCatKey, toCategory: newCatKey)
            }
        }
        if let note = p.note { store.transactions[idx].note = note }
        if let date = p.date { store.transactions[idx].date = resolveDate(date) }
        if let t = p.transactionType { store.transactions[idx].type = t == "income" ? .income : .expense }
        store.transactions[idx].lastModified = Date()

        return ExecutionResult(action: action, success: true, summary: "Updated transaction", undoData: undoData)
    }

    @MainActor
    private static func deleteTransaction(_ action: AIAction, store: inout Store) -> ExecutionResult {
        let p = action.params
        guard let idStr = p.transactionId, let uuid = UUID(uuidString: idStr),
              let idx = store.transactions.firstIndex(where: { $0.id == uuid }) else {
            return ExecutionResult(action: action, success: false, summary: "Transaction not found")
        }

        let deleted = store.transactions[idx]
        store.transactions.remove(at: idx)
        store.trackDeletion(of: uuid)
        return ExecutionResult(action: action, success: true, summary: "Deleted transaction",
                               undoData: .deletedTransaction(deleted))
    }

    @MainActor
    private static func splitTransaction(_ action: AIAction, store: inout Store) -> ExecutionResult {
        let p = action.params
        guard let amount = p.amount, let memberName = p.splitWith else {
            return ExecutionResult(action: action, success: false, summary: "Missing amount or split partner")
        }

        let category = resolveCategory(p.category, store: store)
        let date = resolveDate(p.date)
        let ratio = p.splitRatio ?? 0.5
        let myShare = Int(Double(amount) * ratio)

        // Add the transaction for my share
        let txn = Transaction(
            amount: myShare,
            date: date,
            category: category,
            note: p.note ?? "Split with \(memberName)",
            paymentMethod: .card,
            type: .expense
        )
        store.add(txn)

        // Record split in household if available
        let manager = HouseholdManager.shared
        if manager.household != nil,
           let userId = SupabaseManager.shared.currentUserId {
            manager.addSplitExpense(
                amount: amount,
                paidBy: userId,
                splitRule: .percentage(ratio * 100),
                category: category.storageKey,
                note: p.note ?? "Split with \(memberName)",
                date: date,
                transactionId: txn.id
            )
        }

        return ExecutionResult(
            action: action, success: true,
            summary: "Split \(formatCents(amount)) with \(memberName) — your share: \(formatCents(myShare))",
            undoData: .addedTransaction(transactionId: txn.id)
        )
    }

    // MARK: - Budget Handlers

    private static func setBudget(_ action: AIAction, store: inout Store) -> ExecutionResult {
        let p = action.params
        guard let amount = p.budgetAmount else {
            return ExecutionResult(action: action, success: false, summary: "Missing budget amount")
        }

        let monthKey = resolveMonthKey(p.budgetMonth, store: store)
        let oldAmount = store.budgetsByMonth[monthKey]
        store.budgetsByMonth[monthKey] = max(0, amount)

        return ExecutionResult(
            action: action, success: true,
            summary: "Set budget to \(formatCents(amount)) for \(monthKey)",
            undoData: .budgetChanged(monthKey: monthKey, oldAmount: oldAmount)
        )
    }

    private static func setCategoryBudget(_ action: AIAction, store: inout Store) -> ExecutionResult {
        let p = action.params
        guard let cat = p.budgetCategory, let amount = p.budgetAmount else {
            return ExecutionResult(action: action, success: false, summary: "Missing category or amount")
        }

        let monthKey = resolveMonthKey(p.budgetMonth, store: store)
        let oldAmount = store.categoryBudgetsByMonth[monthKey]?[cat]
        var catBudgets = store.categoryBudgetsByMonth[monthKey] ?? [:]
        catBudgets[cat] = max(0, amount)
        store.categoryBudgetsByMonth[monthKey] = catBudgets

        return ExecutionResult(
            action: action, success: true,
            summary: "Set \(cat) budget to \(formatCents(amount)) for \(monthKey)",
            undoData: .categoryBudgetChanged(monthKey: monthKey, categoryKey: cat, oldAmount: oldAmount)
        )
    }

    // MARK: - Goal Handlers

    @MainActor
    private static func createGoal(_ action: AIAction) async -> ExecutionResult {
        let p = action.params
        guard let name = p.goalName, let target = p.goalTarget else {
            return ExecutionResult(action: action, success: false, summary: "Missing goal name or target")
        }

        let userId = SupabaseManager.shared.currentUserId ?? "local"
        let currency = UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"
        let goal = Goal(
            name: name,
            type: .custom,
            targetAmount: target,
            currentAmount: 0,
            currency: currency,
            targetDate: p.goalDeadline.flatMap { parseISO($0) },
            icon: "star.fill",
            colorToken: "blue",
            userId: userId
        )

        let ok = await GoalManager.shared.createGoal(goal)
        return ExecutionResult(
            action: action, success: ok,
            summary: ok ? "Created goal \"\(name)\" — target \(formatCents(target))" : "Failed to create goal",
            undoData: ok ? .createdGoal(goalId: goal.id) : .nonUndoable
        )
    }

    @MainActor
    private static func addContribution(_ action: AIAction) async -> ExecutionResult {
        let p = action.params
        guard let name = p.goalName, let amount = p.contributionAmount else {
            return ExecutionResult(action: action, success: false, summary: "Missing goal name or amount")
        }

        guard let goal = GoalManager.shared.goals.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            return ExecutionResult(action: action, success: false, summary: "Goal \"\(name)\" not found")
        }

        let ok = await GoalManager.shared.addContribution(to: goal, amount: amount, note: "Via AI assistant")
        return ExecutionResult(
            action: action, success: ok,
            summary: ok ? "Added \(formatCents(amount)) to \"\(name)\"" : "Failed to add contribution",
            undoData: ok ? .addedContribution(goalName: name, amount: amount) : .nonUndoable
        )
    }

    @MainActor
    private static func updateGoal(_ action: AIAction) async -> ExecutionResult {
        let p = action.params
        guard let name = p.goalName else {
            return ExecutionResult(action: action, success: false, summary: "Missing goal name")
        }

        guard var goal = GoalManager.shared.goals.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            return ExecutionResult(action: action, success: false, summary: "Goal \"\(name)\" not found")
        }

        if let target = p.goalTarget { goal.targetAmount = target }
        if let deadline = p.goalDeadline { goal.targetDate = parseISO(deadline) }
        goal.updatedAt = Date()

        let ok = await GoalManager.shared.updateGoal(goal)
        return ExecutionResult(
            action: action, success: ok,
            summary: ok ? "Updated goal \"\(name)\"" : "Failed to update goal"
        )
    }

    // MARK: - Subscription Handlers

    @MainActor
    private static func addSubscription(_ action: AIAction, store: inout Store) -> ExecutionResult {
        let p = action.params
        guard let name = p.subscriptionName, let amount = p.subscriptionAmount else {
            return ExecutionResult(action: action, success: false, summary: "Missing subscription info")
        }

        let freq: RecurringFrequency = p.subscriptionFrequency == "yearly" ? .yearly : .monthly
        let recurring = RecurringTransaction(
            name: name,
            amount: amount,
            category: .bills,
            frequency: freq,
            startDate: Date(),
            isActive: true,
            paymentMethod: .card,
            note: "Added via AI"
        )
        store.recurringTransactions.append(recurring)

        return ExecutionResult(
            action: action, success: true,
            summary: "Added subscription: \(name) \(formatCents(amount))/\(freq.rawValue)",
            undoData: .addedSubscription(name: name)
        )
    }

    @MainActor
    private static func cancelSubscription(_ action: AIAction) -> ExecutionResult {
        let p = action.params
        guard let name = p.subscriptionName else {
            return ExecutionResult(action: action, success: false, summary: "Missing subscription name")
        }

        let engine = SubscriptionEngine.shared
        if let sub = engine.subscriptions.first(where: {
            $0.merchantName.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            engine.markAsCancelled(sub)
            return ExecutionResult(action: action, success: true, summary: "Cancelled \(name)")
        }
        return ExecutionResult(action: action, success: false, summary: "Subscription \"\(name)\" not found")
    }

    // MARK: - Account Handlers

    @MainActor
    private static func updateBalance(_ action: AIAction) async -> ExecutionResult {
        let p = action.params
        guard let name = p.accountName, let balance = p.accountBalance else {
            return ExecutionResult(action: action, success: false, summary: "Missing account info")
        }

        guard var account = AccountManager.shared.accounts.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            return ExecutionResult(action: action, success: false, summary: "Account \"\(name)\" not found")
        }

        account.currentBalance = Double(balance) / 100.0
        account.updatedAt = Date()
        let ok = await AccountManager.shared.updateAccount(account)
        return ExecutionResult(
            action: action, success: ok,
            summary: ok ? "Updated \(name) balance to \(formatCents(balance))" : "Failed to update balance"
        )
    }

    // MARK: - Transfer Handler

    @MainActor
    private static func transfer(_ action: AIAction) async -> ExecutionResult {
        let p = action.params
        guard let from = p.fromAccount, let to = p.toAccount, let amount = p.amount else {
            return ExecutionResult(action: action, success: false,
                                   summary: "Missing transfer details (from, to, or amount)")
        }

        let accounts = AccountManager.shared.accounts
        guard var source = accounts.first(where: { $0.name.localizedCaseInsensitiveCompare(from) == .orderedSame }),
              var dest = accounts.first(where: { $0.name.localizedCaseInsensitiveCompare(to) == .orderedSame }) else {
            return ExecutionResult(action: action, success: false,
                                   summary: "One or both accounts not found")
        }

        let dollars = Double(amount) / 100.0
        source.currentBalance -= dollars
        dest.currentBalance += dollars
        source.updatedAt = Date()
        dest.updatedAt = Date()

        let ok1 = await AccountManager.shared.updateAccount(source)
        let ok2 = await AccountManager.shared.updateAccount(dest)

        return ExecutionResult(
            action: action, success: ok1 && ok2,
            summary: "Transferred \(formatCents(amount)) from \(from) to \(to)"
        )
    }

    // MARK: - Recurring Handlers

    @MainActor
    private static func addRecurring(_ action: AIAction, store: inout Store) -> ExecutionResult {
        let p = action.params
        let name = p.recurringName ?? p.note ?? "Recurring"
        guard let amount = p.amount else {
            return ExecutionResult(action: action, success: false, summary: "Missing amount for recurring")
        }

        let category = resolveCategory(p.category, store: store)
        let freq: RecurringFrequency
        switch p.recurringFrequency?.lowercased() {
        case "daily":   freq = .daily
        case "weekly":  freq = .weekly
        case "yearly":  freq = .yearly
        default:        freq = .monthly
        }

        let recurring = RecurringTransaction(
            name: name,
            amount: amount,
            category: category,
            frequency: freq,
            startDate: resolveDate(p.date),
            isActive: true,
            paymentMethod: .card,
            note: "Added via AI"
        )
        store.recurringTransactions.append(recurring)

        return ExecutionResult(
            action: action, success: true,
            summary: "Added recurring: \(name) \(formatCents(amount))/\(freq.rawValue)",
            undoData: .addedSubscription(name: name)
        )
    }

    @MainActor
    private static func editRecurring(_ action: AIAction, store: inout Store) -> ExecutionResult {
        let p = action.params
        guard let name = p.recurringName ?? p.subscriptionName else {
            return ExecutionResult(action: action, success: false, summary: "Missing recurring name")
        }

        guard let idx = store.recurringTransactions.firstIndex(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            return ExecutionResult(action: action, success: false,
                                   summary: "Recurring \"\(name)\" not found")
        }

        if let amount = p.amount { store.recurringTransactions[idx].amount = amount }
        if let cat = p.category { store.recurringTransactions[idx].category = resolveCategory(cat, store: store) }
        if let note = p.note { store.recurringTransactions[idx].note = note }

        return ExecutionResult(
            action: action, success: true,
            summary: "Updated recurring: \(name)"
        )
    }

    @MainActor
    private static func cancelRecurring(_ action: AIAction, store: inout Store) -> ExecutionResult {
        let p = action.params
        guard let name = p.recurringName ?? p.subscriptionName else {
            return ExecutionResult(action: action, success: false, summary: "Missing recurring name")
        }

        guard let idx = store.recurringTransactions.firstIndex(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            return ExecutionResult(action: action, success: false,
                                   summary: "Recurring \"\(name)\" not found")
        }

        store.recurringTransactions[idx].isActive = false
        return ExecutionResult(
            action: action, success: true,
            summary: "Cancelled recurring: \(name)"
        )
    }

    // MARK: - Helpers

    private static func resolveCategory(_ key: String?, store: Store) -> Category {
        guard let key else { return .other }
        if let cat = Category(storageKey: key) { return cat }
        return .other
    }

    private static func resolveDate(_ raw: String?) -> Date {
        guard let raw else { return Date() }
        let lower = raw.lowercased()
        if lower == "today" { return Date() }
        if lower == "yesterday" { return Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date() }

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        if let d = f.date(from: raw) { return d }

        // Try yyyy-MM-dd
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: raw) ?? Date()
    }

    private static func resolveMonthKey(_ raw: String?, store: Store) -> String {
        guard let raw else { return Store.monthKey(store.selectedMonth) }
        if raw == "this_month" { return Store.monthKey(Date()) }
        // Assume YYYY-MM format
        if raw.count == 7 { return raw }
        return Store.monthKey(store.selectedMonth)
    }

    private static func parseISO(_ str: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        if let d = f.date(from: str) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: str)
    }

    private static func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}
