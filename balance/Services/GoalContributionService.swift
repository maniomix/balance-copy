import Foundation

// ============================================================
// MARK: - Goal Contribution Service (Phase 4b — iOS port)
// ============================================================
//
// Single write path for goal progress. Routes every mutation through
// here so the contribution history and `Goal.currentAmount` stay
// consistent.
//
// Ported from macOS Centmond. iOS adaptations:
//   - macOS: `Goal` is an `@Model` class mutated in place via SwiftData
//   - iOS:   `Goal` is a struct owned by `GoalManager` (Supabase-backed).
//     Services take the goal as `inout` and return the mutated copy;
//     the caller (typically `GoalManager`) is responsible for syncing
//     the updated Goal back to Supabase.
//   - Contributions live in `Store.aiGoalContributions` (value-type list).
//   - Amounts are Int cents.
// ============================================================

enum GoalContributionService {

    // MARK: - Writes

    /// Apply a contribution: appends a `AIGoalContribution` row to the Store,
    /// bumps `goal.currentAmount`, auto-transitions `isCompleted`. Returns
    /// the created contribution for UI / telemetry.
    ///
    /// The caller must persist the returned `Goal` mutation (via
    /// `GoalManager` → Supabase). The Store-side contribution row is
    /// independent and will be persisted by the Store's usual save path.
    @discardableResult
    static func addContribution(
        to goal: inout Goal,
        amount: Int,
        kind: GoalContributionKind = .manual,
        date: Date = Date(),
        note: String? = nil,
        sourceTransactionId: UUID? = nil,
        in store: inout Store
    ) -> AIGoalContribution {
        let contribution = AIGoalContribution(
            goalId: goal.id,
            amount: amount,
            date: date,
            kind: kind,
            note: note,
            sourceTransactionId: sourceTransactionId
        )
        store.aiGoalContributions.append(contribution)
        goal.currentAmount += amount
        goal.updatedAt = Date()
        autoTransitionStatus(&goal)
        return contribution
    }

    /// Remove a contribution by id. Reverses the `Goal.currentAmount` bump
    /// (clamped ≥ 0). Caller must persist the Goal mutation.
    static func removeContribution(
        id contributionId: UUID,
        from goal: inout Goal,
        in store: inout Store
    ) {
        guard let idx = store.aiGoalContributions.firstIndex(where: { $0.id == contributionId }) else { return }
        let c = store.aiGoalContributions[idx]
        store.aiGoalContributions.remove(at: idx)
        guard c.goalId == goal.id else { return }
        goal.currentAmount = max(0, goal.currentAmount - c.amount)
        goal.updatedAt = Date()
        autoTransitionStatus(&goal)
    }

    /// Delete every contribution that originated from a given transaction —
    /// called when a Transaction is deleted so goal balances don't drift.
    /// Mutates goals in-place via `applyToGoal` callback so GoalManager can
    /// funnel persistence through its Supabase path.
    static func removeContributions(
        forTransactionId txId: UUID,
        in store: inout Store,
        applyToGoal: (UUID, Int) -> Void
    ) {
        let matches = store.aiGoalContributions.filter { $0.sourceTransactionId == txId }
        guard !matches.isEmpty else { return }
        store.aiGoalContributions.removeAll { $0.sourceTransactionId == txId }
        // Roll up net delta per goal so we hit GoalManager once per goal
        // instead of per contribution.
        var byGoal: [UUID: Int] = [:]
        for c in matches { byGoal[c.goalId, default: 0] += c.amount }
        for (goalId, totalToRemove) in byGoal {
            applyToGoal(goalId, -totalToRemove)
        }
    }

    // MARK: - Lookups

    /// Sum (cents) of contributions linked to a single Transaction. Used by
    /// income-row surfaces that show "$X went to goals, $Y left to spend".
    static func totalAllocated(forTransactionId txId: UUID, in store: Store) -> Int {
        store.aiGoalContributions
            .filter { $0.sourceTransactionId == txId }
            .reduce(0) { $0 + $1.amount }
    }

    /// Sum of contributions whose source transaction is an income
    /// transaction dated on the given calendar day.
    static func totalAllocatedFromIncome(on day: Date, in store: Store) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let incomeIds = Set(
            store.transactions
                .filter { $0.type == .income && $0.date >= start && $0.date < end }
                .map(\.id)
        )
        guard !incomeIds.isEmpty else { return 0 }
        return store.aiGoalContributions.reduce(0) { acc, c in
            guard let src = c.sourceTransactionId, incomeIds.contains(src) else { return acc }
            return acc + c.amount
        }
    }

    // MARK: - Integrity

    /// Recompute `goal.currentAmount` from its contribution list. Safe to
    /// call anytime — useful after a bulk import or suspected drift.
    static func rebuildCache(for goal: inout Goal, from store: Store) {
        let sum = store.aiGoalContributions
            .filter { $0.goalId == goal.id }
            .reduce(0) { $0 + $1.amount }
        goal.currentAmount = sum
        goal.updatedAt = Date()
        autoTransitionStatus(&goal)
    }

    // MARK: - Migration

    /// One-shot migration: for goals that have a non-zero `currentAmount`
    /// but no contribution history, synthesize a single `.manual` seed
    /// contribution so the history view matches the legacy balance.
    static func migrateLegacyBalances(goals: [Goal], in store: inout Store) {
        let existingGoalIds = Set(store.aiGoalContributions.map(\.goalId))
        for goal in goals where !existingGoalIds.contains(goal.id) && goal.currentAmount > 0 {
            store.aiGoalContributions.append(AIGoalContribution(
                goalId: goal.id,
                amount: goal.currentAmount,
                date: goal.createdAt,
                kind: .manual,
                note: "Imported from legacy balance"
            ))
        }
    }

    // MARK: - Internal

    private static func autoTransitionStatus(_ goal: inout Goal) {
        if !goal.isCompleted, goal.currentAmount >= goal.targetAmount {
            goal.isCompleted = true
        } else if goal.isCompleted, goal.currentAmount < goal.targetAmount {
            goal.isCompleted = false
        }
    }
}
