import Foundation

// ============================================================
// MARK: - Household Share Expansion (v1 → v2)
// ============================================================
// Pure functions that convert legacy `SplitExpense` aggregates into the new
// per-share `ExpenseShare` rows. Used by:
//   - HouseholdSyncManager when pulling a v1 snapshot from Supabase.
//   - HouseholdManager during local-store migration on first launch of the
//     P3 build.
//
// Mapping per docs/HOUSEHOLD_REBUILD_P1_SPEC.md §7.1:
//   .equal           → one row per member; equal split + remainder to payer
//   .custom          → one row per non-zero MemberSplit (method = .exact)
//   .paidByMe        → payer owes full, others 0 (method = .exact)
//   .paidByPartner   → symmetric
//   .percentage(p)   → payer p%, one other (100-p)% (method = .percent)
//
// Important: the FIRST listed member in `.equal` receives the rounding
// remainder. This matches `HouseholdManager`'s pre-existing behaviour and the
// memory note `feedback_subscription_engine_rederivation` style — keep
// derivation deterministic so re-runs produce stable IDs.
// ============================================================

enum HouseholdShareExpansion {

    /// Expand a single legacy `SplitExpense` into per-member share rows.
    /// Returns rows in member order. Members not active (archived) are still
    /// included so the ledger history stays intact.
    static func expand(
        _ expense: SplitExpense,
        members: [HouseholdMember]
    ) -> [ExpenseShare] {
        guard !members.isEmpty else { return [] }

        // Resolve payer member.id from the userId string stored on the expense.
        let payerMemberId = members.first(where: { $0.userId == expense.paidBy })?.id
            ?? members.first?.id
            ?? UUID()

        // Translate to MemberSplit list using the original engine logic on the
        // expense itself. This re-uses `SplitExpense.splits(members:)` so the
        // arithmetic stays in one place.
        let splits = expense.splits(members: members)

        // Status follows the aggregate `isSettled` flag for v1.
        let baseStatus: ShareStatus = expense.isSettled ? .settled : .owed
        let baseSettledAt: Date? = expense.isSettled ? expense.settledAt : nil

        // Method + percent metadata depends on the original splitRule.
        let method: ExpenseSplitMethod
        let payerPercent: Double?
        let nonPayerPercent: Double?
        switch expense.splitRule {
        case .equal:
            method = .equal
            payerPercent = nil
            nonPayerPercent = nil
        case .custom:
            method = .exact
            payerPercent = nil
            nonPayerPercent = nil
        case .paidByMe, .paidByPartner:
            method = .exact
            payerPercent = nil
            nonPayerPercent = nil
        case .percentage(let p):
            method = .percent
            payerPercent = p
            nonPayerPercent = 100 - p
        }

        return splits.compactMap { ms in
            guard let member = members.first(where: { $0.userId == ms.userId }) else {
                return nil
            }
            // Skip zero-amount rows for `.custom` expansion (per spec §7.1).
            if expense.splitRule == .custom && ms.amount == 0 {
                return nil
            }
            let percent: Double? = {
                guard method == .percent else { return nil }
                return member.id == payerMemberId ? payerPercent : nonPayerPercent
            }()
            return ExpenseShare(
                householdId: expense.householdId,
                transactionId: expense.transactionId,
                memberId: member.id,
                paidByMemberId: payerMemberId,
                amount: ms.amount,
                percent: percent,
                method: method,
                status: baseStatus,
                createdAt: expense.createdAt,
                settledAt: baseSettledAt,
                settlementId: nil
            )
        }
    }

    /// Expand a list of legacy expenses into a flat list of share rows.
    static func expand(
        _ expenses: [SplitExpense],
        members: [HouseholdMember]
    ) -> [ExpenseShare] {
        expenses.flatMap { expand($0, members: members) }
    }
}
