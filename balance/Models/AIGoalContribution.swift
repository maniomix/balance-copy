import Foundation

// ============================================================
// MARK: - Goal Contribution (Phase 4b — iOS port)
// ============================================================
//
// A single deposit toward a Goal. Ported from macOS Centmond as a
// Codable struct stored on Store, linked to Goal via `goalId: UUID`
// (not a SwiftData relationship).
//
// On macOS this is the AUTHORITATIVE history — `Goal.currentAmount`
// is a cache maintained from the sum of contributions. iOS keeps
// `Goal.currentAmount` as its own authoritative field (Supabase-backed)
// and uses contributions as a parallel history log that the services
// mutate alongside the Goal. `GoalContributionService.rebuildCache`
// is still available for integrity rebuilds.
// ============================================================

enum GoalContributionKind: String, Codable, CaseIterable {
    case manual
    case fromIncome
    case fromTransfer
    case autoRule
}

struct AIGoalContribution: Identifiable, Codable, Hashable {
    let id: UUID
    var goalId: UUID
    var amount: Int                // cents
    var date: Date
    var kind: GoalContributionKind
    var note: String?
    /// Originating Transaction's UUID when the contribution came from an
    /// income allocation or transfer-to-goal. Deleting the Transaction
    /// should cascade-delete contributions with a matching sourceTransactionId.
    var sourceTransactionId: UUID?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        goalId: UUID,
        amount: Int,
        date: Date = Date(),
        kind: GoalContributionKind = .manual,
        note: String? = nil,
        sourceTransactionId: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.goalId = goalId
        self.amount = amount
        self.date = date
        self.kind = kind
        self.note = note
        self.sourceTransactionId = sourceTransactionId
        self.createdAt = createdAt
    }
}
