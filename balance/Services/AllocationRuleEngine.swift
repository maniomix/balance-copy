import Foundation

// ============================================================
// MARK: - Allocation Rule Engine (Phase 4b — iOS port)
// ============================================================
//
// Evaluates active `GoalAllocationRule`s against an income Transaction
// and returns capped `AllocationProposal`s. Pure — does not mutate
// Store. Callers (typically the new-transaction sheet or AI action
// executor) show a preview UI and then write confirmed proposals via
// `GoalContributionService.addContribution` with `kind: .autoRule`.
//
// Ported from macOS Centmond. iOS adaptations:
//   - Reads rules + goals from the Store / goals snapshot (value types)
//   - Amounts are Int cents
//   - `tx.isIncome` → `tx.type == .income`
//   - `tx.payee` → `tx.note` (iOS has no dedicated payee field)
//   - `tx.category.id.uuidString` → `tx.category.storageKey` for category
//     matching, since iOS Category uses a string-based storage key
// ============================================================

/// One proposed contribution from the rule engine. Not persisted —
/// materialized into a `AIGoalContribution` only when the user confirms.
/// `amount` is mutable so the preview UI can tweak before applying.
struct AllocationProposal: Identifiable {
    let id: UUID
    let rule: GoalAllocationRule
    let goal: Goal
    var amount: Int      // cents
    var enabled: Bool

    init(id: UUID = UUID(), rule: GoalAllocationRule, goal: Goal, amount: Int, enabled: Bool = true) {
        self.id = id
        self.rule = rule
        self.goal = goal
        self.amount = amount
        self.enabled = enabled
    }
}

enum AllocationRuleEngine {

    /// Build proposals for an income transaction. Subtract any
    /// contributions already earmarked (e.g. manual allocations made in
    /// the sheet) from the cap so rules never push total above 100% of
    /// the income.
    static func proposals(
        for transaction: Transaction,
        alreadyAllocated: Int = 0,
        goals: [Goal],
        in store: Store
    ) -> [AllocationProposal] {
        guard transaction.type == .income, transaction.amount > 0 else { return [] }

        // Active rules sorted by priority desc, createdAt asc.
        let rules = store.goalAllocationRules
            .filter { $0.isActive }
            .sorted { a, b in
                if a.priority != b.priority { return a.priority > b.priority }
                return a.createdAt < b.createdAt
            }
        guard !rules.isEmpty else { return [] }

        let goalsById = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })

        var remaining = transaction.amount - alreadyAllocated
        guard remaining > 0 else { return [] }

        var out: [AllocationProposal] = []
        for rule in rules {
            guard let goal = goalsById[rule.goalId], !goal.isCompleted else { continue }
            guard rule.type.isIncomeDriven else { continue }
            guard matches(rule: rule, tx: transaction) else { continue }

            let raw = rawAmount(for: rule, tx: transaction)
            guard raw > 0 else { continue }

            // Cap to remaining unallocated income AND to the goal's own gap.
            let goalGap = max(goal.targetAmount - goal.currentAmount, 0)
            let capped = min(raw, remaining, goalGap)
            guard capped > 0 else { continue }

            out.append(AllocationProposal(rule: rule, goal: goal, amount: capped))
            remaining -= capped
            if remaining <= 0 { break }
        }
        return out
    }

    // MARK: - Internal

    private static func matches(rule: GoalAllocationRule, tx: Transaction) -> Bool {
        switch rule.source {
        case .allIncome:
            return true
        case .category:
            guard let match = rule.sourceMatch else { return false }
            return tx.category.storageKey == match
        case .payee:
            guard let match = rule.sourceMatch else { return false }
            return tx.note.localizedCaseInsensitiveCompare(match) == .orderedSame
        }
    }

    /// Raw cents the rule would contribute (uncapped, pre-gap).
    private static func rawAmount(for rule: GoalAllocationRule, tx: Transaction) -> Int {
        switch rule.type {
        case .percentOfIncome:
            // `rule.amount` is a whole percent; e.g. 10 → 10% of the income.
            return Int((Double(tx.amount) * Double(rule.amount) / 100.0).rounded())
        case .fixedPerIncome:
            return rule.amount
        case .fixedMonthly, .roundUpExpense:
            return 0 // reserved for later phases
        }
    }
}
