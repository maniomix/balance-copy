import Foundation

// ============================================================
// MARK: - Goal Analytics (Phase 4b — iOS port)
// ============================================================
//
// Pure read-only derivations from a Goal's contribution history. Used
// by the Goals grid cards, goal inspector timeline, and the dashboard.
//
// Ported from macOS Centmond. iOS adaptations:
//   - Contributions are loaded from Store (value-type list) and filtered
//     by goalId instead of read through a SwiftData relationship
//   - Amounts are Int cents
//   - `Goal.contributions` does not exist on iOS → every API takes the
//     contribution slice as a parameter (or fetches by goalId from store)
// ============================================================

enum GoalAnalytics {

    // MARK: - Helpers

    /// Fetch the contribution slice for a specific goal — used by every
    /// other API so callers don't need to filter themselves.
    static func contributions(for goal: Goal, in store: Store) -> [AIGoalContribution] {
        store.aiGoalContributions.filter { $0.goalId == goal.id }
    }

    // MARK: - Monthly totals

    /// Sum (cents) of contributions dated in the current calendar month.
    static func thisMonthContribution(_ goal: Goal, in store: Store) -> Int {
        let cal = Calendar.current
        let now = Date()
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        return contributions(for: goal, in: store).reduce(0) { acc, c in
            guard cal.component(.year, from: c.date) == y,
                  cal.component(.month, from: c.date) == m else { return acc }
            return acc + c.amount
        }
    }

    /// Rolling average monthly contribution (cents) over the last `months`
    /// complete calendar months (excluding the current month so partial
    /// data doesn't drag the average down). Returns 0 when too young.
    static func averageMonthlyContribution(_ goal: Goal, months: Int = 3, in store: Store) -> Int {
        guard months > 0 else { return 0 }
        let cal = Calendar.current
        let now = Date()
        let monthStartNow = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        guard let windowStart = cal.date(byAdding: .month, value: -months, to: monthStartNow) else { return 0 }

        let total = contributions(for: goal, in: store)
            .filter { $0.date >= windowStart && $0.date < monthStartNow }
            .reduce(0) { $0 + $1.amount }
        return total / months
    }

    /// Per-kind sum, suitable for a funding-source breakdown badge row.
    static func breakdownByKind(_ goal: Goal, in store: Store) -> [GoalContributionKind: Int] {
        var out: [GoalContributionKind: Int] = [:]
        for c in contributions(for: goal, in: store) {
            out[c.kind, default: 0] += c.amount
        }
        return out
    }

    /// Projected completion date assuming the goal keeps receiving
    /// `averageMonthlyContribution(months: 3)` per month. Returns nil when
    /// the goal is already complete, has no target gap, or the average
    /// is zero.
    static func projectedCompletion(_ goal: Goal, in store: Store) -> Date? {
        let gap = goal.targetAmount - goal.currentAmount
        guard gap > 0 else { return nil }
        let avg = averageMonthlyContribution(goal, months: 3, in: store)
        guard avg > 0 else { return nil }
        let monthsNeeded = Int((Double(gap) / Double(avg)).rounded(.up))
        guard monthsNeeded > 0, monthsNeeded < 600 else { return nil }
        return Calendar.current.date(byAdding: .month, value: monthsNeeded, to: Date())
    }

    // MARK: - Unallocated income (for Goals view banner)

    /// Income transactions in the current calendar month that have no
    /// associated AIGoalContribution via `sourceTransactionId`. Used by
    /// the banner to nudge users to allocate idle income.
    static func unallocatedIncomeThisMonth(in store: Store) -> (totalCents: Int, count: Int) {
        let cal = Calendar.current
        let now = Date()
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else {
            return (0, 0)
        }
        let incomeTxs = store.transactions
            .filter { $0.type == .income && $0.date >= monthStart && $0.date < monthEnd }
        guard !incomeTxs.isEmpty else { return (0, 0) }

        let linkedIds = Set(store.aiGoalContributions.compactMap(\.sourceTransactionId))
        var total = 0
        var count = 0
        for tx in incomeTxs where !linkedIds.contains(tx.id) {
            total += tx.amount
            count += 1
        }
        return (total, count)
    }
}
