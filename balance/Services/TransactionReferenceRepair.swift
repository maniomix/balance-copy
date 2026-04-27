import Foundation

// ============================================================
// MARK: - Transaction Reference Repair (Phase 6a — iOS port)
// ============================================================
//
// Walks every Store-side collection that holds a `sourceTransactionId`
// or `transactionId` back-link and deletes rows whose referenced
// transaction no longer exists. Runs at app launch alongside
// `CategoryReferenceRepair`.
//
// Ported from macOS Centmond. iOS uses Codable structs + UUID refs
// rather than SwiftData relationships, so there are no tombstone
// crash hazards — but orphaned rows still accumulate if a delete
// path forgets to cascade. This service is the safety net.
//
// Collections checked:
//   - `aiSubscriptionCharges.transactionId`
//   - `aiGoalContributions.sourceTransactionId`
//
// Goal contribution removal does NOT attempt to patch the goal's
// `currentAmount` — this is a launch-time backstop, not a user-driven
// delete. If drift is detected, `GoalContributionService.rebuildCache`
// is the right next step.
// ============================================================

enum TransactionReferenceRepair {

    /// Returns the number of orphan rows removed. Safe to call at launch.
    @discardableResult
    static func run(store: inout Store) -> Int {
        let liveIds = Set(store.transactions.map(\.id))
        var removed = 0

        // AISubscription charges — orphan if their linked transaction is gone.
        let chargesBefore = store.aiSubscriptionCharges.count
        store.aiSubscriptionCharges.removeAll { charge in
            guard let txId = charge.transactionId else { return false }
            return !liveIds.contains(txId)
        }
        removed += chargesBefore - store.aiSubscriptionCharges.count

        // Goal contributions — orphan if their source transaction is gone.
        let contribsBefore = store.aiGoalContributions.count
        store.aiGoalContributions.removeAll { contribution in
            guard let txId = contribution.sourceTransactionId else { return false }
            return !liveIds.contains(txId)
        }
        removed += contribsBefore - store.aiGoalContributions.count

        return removed
    }
}
