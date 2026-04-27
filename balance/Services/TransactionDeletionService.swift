import Foundation

// ============================================================
// MARK: - Transaction Deletion Service (Phase 6a — iOS port)
// ============================================================
//
// Centralised delete path for Transactions. Every caller routes
// through here so related accounting artefacts are removed in the
// right order and balances don't drift.
//
// Ported from macOS Centmond. iOS lives in a different data-layer
// world:
//   - No SwiftData tombstone hazards → no "snapshot IDs first" dance
//   - Related rows are Codable structs in Store, linked by UUID
//   - ExpenseShare / HouseholdSettlement don't exist on iOS → skipped
//   - Goal contribution delta routes back through `GoalManager` via
//     the same callback pattern introduced in 4b
//
// Deletion order:
//   1. AISubscription charges linked to the transaction
//   2. Goal contributions linked to the transaction (returns per-goal
//      deltas via `applyToGoal`)
//   3. The transaction itself
// ============================================================

enum TransactionDeletionService {

    /// Delete one transaction with cascade cleanup.
    static func delete(
        _ transaction: Transaction,
        in store: inout Store,
        applyGoalDelta: (UUID, Int) -> Void = { _, _ in }
    ) {
        delete([transaction.id], in: &store, applyGoalDelta: applyGoalDelta)
    }

    /// Delete multiple transactions with cascade cleanup.
    static func delete(
        _ transactions: [Transaction],
        in store: inout Store,
        applyGoalDelta: (UUID, Int) -> Void = { _, _ in }
    ) {
        delete(transactions.map(\.id), in: &store, applyGoalDelta: applyGoalDelta)
    }

    /// Delete by ID set. Accepts an `applyGoalDelta` callback so `GoalManager`
    /// can sync the goal's new `currentAmount` back to Supabase — Store-side
    /// contribution rows are removed synchronously here.
    static func delete(
        _ transactionIds: [UUID],
        in store: inout Store,
        applyGoalDelta: (UUID, Int) -> Void = { _, _ in }
    ) {
        guard !transactionIds.isEmpty else { return }
        let idSet = Set(transactionIds)

        // 1. AISubscription charges linked to these transactions — they only
        //    made sense while the transaction existed.
        store.aiSubscriptionCharges.removeAll { charge in
            guard let txId = charge.transactionId else { return false }
            return idSet.contains(txId)
        }

        // 2. Goal contributions — roll up net delta per goal so the caller
        //    hits GoalManager once per goal instead of per contribution.
        let orphanedContributions = store.aiGoalContributions.filter {
            guard let src = $0.sourceTransactionId else { return false }
            return idSet.contains(src)
        }
        var deltaByGoal: [UUID: Int] = [:]
        for c in orphanedContributions {
            deltaByGoal[c.goalId, default: 0] += c.amount
        }
        store.aiGoalContributions.removeAll { orphanedContributions.contains($0) }
        for (goalId, removed) in deltaByGoal {
            applyGoalDelta(goalId, -removed)
        }

        // 3. The transactions themselves. Track the IDs for sync.
        let removed = store.transactions.filter { idSet.contains($0.id) }
        store.transactions.removeAll { idSet.contains($0.id) }
        for tx in removed {
            store.trackDeletion(of: tx.id)
        }
    }
}
