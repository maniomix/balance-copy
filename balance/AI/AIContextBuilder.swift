import Foundation

// ============================================================
// MARK: - AI Context Builder
// ============================================================
//
// Summarises live app data into a compact text block that gets
// injected into the system prompt. This gives Gemma awareness
// of the user's finances without sending raw model objects.
//
// ============================================================

enum AIContextBuilder {

    /// Build a full financial context string from the current app state.
    @MainActor
    static func build(store: Store) -> String {
        var sections: [String] = []

        sections.append(budgetSection(store: store))
        sections.append(transactionSection(store: store))
        sections.append(categoryBreakdown(store: store))
        sections.append(goalSection())
        sections.append(accountSection())
        sections.append(subscriptionSection())
        sections.append(householdSection())

        return sections
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    // MARK: - Budget

    @MainActor
    private static func budgetSection(store: Store) -> String {
        let month = store.selectedMonth
        let monthKey = monthKey(for: month)
        let budget = store.budgetsByMonth[monthKey] ?? 0
        let spent = store.spent(for: month)
        let income = store.income(for: month)
        let remaining = store.remaining(for: month)

        guard budget > 0 || spent > 0 || income > 0 else { return "" }

        var lines = ["BUDGET (\(monthKey))"]
        if budget > 0 { lines.append("  Monthly budget: \(cents(budget))") }
        if income > 0 { lines.append("  Income: \(cents(income))") }
        lines.append("  Spent: \(cents(spent))")
        if budget > 0 { lines.append("  Remaining: \(cents(remaining))") }

        // Category budgets
        if let catBudgets = store.categoryBudgetsByMonth[monthKey], !catBudgets.isEmpty {
            lines.append("  Category budgets:")
            for (key, amount) in catBudgets.sorted(by: { $0.key < $1.key }) {
                lines.append("    \(key): \(cents(amount))")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Transactions (recent)

    private static func transactionSection(store: Store) -> String {
        let month = store.selectedMonth
        let txns = store.transactions
            .filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
            .sorted { $0.date > $1.date }

        guard !txns.isEmpty else { return "" }

        let recent = txns.prefix(15)
        var lines = ["RECENT TRANSACTIONS (showing \(recent.count) of \(txns.count) this month)"]
        for t in recent {
            let typeTag = t.type == .income ? "+" : "-"
            let dateStr = shortDate(t.date)
            let cat = t.category.storageKey
            let note = t.note.isEmpty ? "" : " — \(t.note)"
            lines.append("  \(dateStr) \(typeTag)\(cents(t.amount)) [\(cat)]\(note) id:\(t.id.uuidString)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Category Breakdown

    private static func categoryBreakdown(store: Store) -> String {
        let month = store.selectedMonth
        let expenses = store.transactions.filter {
            $0.type == .expense &&
            Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
        }

        guard !expenses.isEmpty else { return "" }

        var totals: [String: Int] = [:]
        for t in expenses {
            totals[t.category.storageKey, default: 0] += t.amount
        }

        let sorted = totals.sorted { $0.value > $1.value }
        var lines = ["SPENDING BY CATEGORY"]
        for (cat, amount) in sorted {
            lines.append("  \(cat): \(cents(amount))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Goals

    @MainActor
    private static func goalSection() -> String {
        let goals = GoalManager.shared.goals.filter { !$0.isCompleted }
        guard !goals.isEmpty else { return "" }

        var lines = ["ACTIVE GOALS"]
        for g in goals {
            var detail = "  \(g.name): \(cents(g.currentAmount)) / \(cents(g.targetAmount)) (\(g.progressPercent)%)"
            if let deadline = g.targetDate {
                detail += " due \(shortDate(deadline))"
            }
            if let monthly = g.requiredMonthlySaving {
                detail += " — need \(cents(monthly))/mo"
            }
            lines.append(detail)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Accounts

    @MainActor
    private static func accountSection() -> String {
        let accounts = AccountManager.shared.accounts.filter { !$0.isArchived }
        guard !accounts.isEmpty else { return "" }

        var lines = ["ACCOUNTS"]
        for a in accounts {
            lines.append("  \(a.name) (\(a.type.rawValue)): \(String(format: "%.2f", a.currentBalance)) \(a.currency)")
        }

        let netWorth = AccountManager.shared.netWorth
        lines.append("  Net worth: \(String(format: "$%.2f", netWorth))")

        return lines.joined(separator: "\n")
    }

    // MARK: - Subscriptions

    @MainActor
    private static func subscriptionSection() -> String {
        let subs = SubscriptionEngine.shared.subscriptions.filter { $0.status == .active }
        guard !subs.isEmpty else { return "" }

        let monthlyTotal = subs.reduce(0) { $0 + $1.monthlyCost }
        var lines = ["ACTIVE SUBSCRIPTIONS (total \(cents(monthlyTotal))/mo)"]
        for s in subs {
            var detail = "  \(s.merchantName): \(cents(s.expectedAmount))/\(s.billingCycle.rawValue)"
            if let days = s.daysUntilRenewal {
                detail += " (renews in \(days)d)"
            }
            lines.append(detail)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Household

    @MainActor
    private static func householdSection() -> String {
        let manager = HouseholdManager.shared
        guard let household = manager.household else { return "" }

        let members = household.members.map { $0.displayName }.joined(separator: ", ")
        var lines = ["HOUSEHOLD: \(household.name)", "  Members: \(members)"]

        let monthKey = monthKey(for: Date())
        let uid = SupabaseManager.shared.currentUserId ?? ""
        let snapshot = manager.dashboardSnapshot(monthKey: monthKey, currentUserId: uid)
        if snapshot.unsettledCount > 0 {
            lines.append("  Unsettled splits: \(snapshot.unsettledCount) (\(cents(snapshot.unsettledAmount)))")
            if snapshot.youOwe > 0 { lines.append("  You owe: \(cents(snapshot.youOwe))") }
            if snapshot.owedToYou > 0 { lines.append("  Owed to you: \(cents(snapshot.owedToYou))") }
        }
        if snapshot.sharedBudget > 0 {
            lines.append("  Shared budget: \(cents(snapshot.sharedBudget)) — spent \(cents(snapshot.sharedSpending))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Safe-to-Spend Context

    @MainActor
    static func safeToSpendSection(store: Store) -> String {
        let sts = AISafeToSpend.shared.calculate(store: store)
        return sts.summary()
    }

    // MARK: - Duplicate Detection Context (Phase 3)

    @MainActor
    static func duplicateSection(store: Store) -> String {
        let dupes = AIDuplicateDetector.shared.detectDuplicates(in: store.transactions, month: Date())
        guard !dupes.isEmpty else { return "" }

        var lines = ["POTENTIAL DUPLICATES (\(dupes.count) group(s)):"]
        for group in dupes.prefix(5) {
            let txnDescs = group.transactions.map { txn in
                "\(shortDate(txn.date)) \(cents(txn.amount)) [\(txn.category.storageKey)] \(txn.note) id:\(txn.id.uuidString)"
            }
            lines.append("  \(group.reason.rawValue) (conf: \(Int(group.confidence * 100))%):")
            for desc in txnDescs {
                lines.append("    \(desc)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Focused Builders (for Intent Router)

    @MainActor
    static func buildBudgetOnly(store: Store) -> String {
        [budgetSection(store: store), categoryBreakdown(store: store)]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    @MainActor
    static func buildTransactionsOnly(store: Store) -> String {
        [transactionSection(store: store), categoryBreakdown(store: store)]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    @MainActor
    static func buildGoalsOnly(store: Store) -> String {
        goalSection()
    }

    @MainActor
    static func buildSubscriptionsOnly(store: Store) -> String {
        subscriptionSection()
    }

    // MARK: - Helpers

    private static func cents(_ amount: Int) -> String {
        let dollars = Double(amount) / 100.0
        return String(format: "$%.2f", dollars)
    }

    private static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private static func monthKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }
}
