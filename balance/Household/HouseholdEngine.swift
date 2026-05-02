import Foundation

// ============================================================
// MARK: - HouseholdEngine (P5 — unified surface)
// ============================================================
//
// Canonical engine surface from docs/HOUSEHOLD_REBUILD_P1_SPEC.md §6.
// Both iOS `HouseholdManager` and macOS `HouseholdService` conform to this
// protocol so cross-platform consumers (AI action executor, dashboard
// snapshot card, briefing engine) call the same methods on either side.
//
// This file ships on iOS first (P5.1+P5.2). The macOS sibling is a verbatim
// copy added in P5.3 — synced manually because the projects don't share
// source roots.
//
// IMPORTANT: members are addressed by `HouseholdMember.id` (UUID) at the
// engine surface, not `userId`. Implementations translate as needed for
// internal storage that is still keyed on auth uid strings.
// ============================================================

/// Strategy for archiving a member that still has open shares.
enum ArchiveStrategy: Hashable {
    /// Reassign the archived member's open shares to another member.
    case reassignOpenSharesTo(memberId: UUID)
    /// Forgive the archived member's open shares (`status = .waived`).
    case waiveOpenShares
    /// Refuse the archive if any open shares exist.
    case failIfOpenShares
}

/// Result returned by an `archiveMember` attempt.
enum ArchiveOutcome: Hashable {
    case archived
    case blockedByOpenShares(count: Int)
    case unknownMember
    case notPermitted
}

/// One row used by `recordSplit` to describe a member's contribution.
/// `value` is interpreted by `method`:
///   .equal    → ignored
///   .percent  → percent (0–100)
///   .exact    → cents
///   .shares   → integer weight
struct SplitLine: Hashable {
    let memberId: UUID
    let value: Double
}

protocol HouseholdEngine {

    // MARK: 6.1 Lifecycle

    @discardableResult
    func createHousehold(name: String, ownerDisplayName: String) -> Household
    func deleteHousehold()
    @discardableResult
    func regenerateInviteCode() -> String

    // MARK: 6.2 Members

    @discardableResult
    func addMember(
        displayName: String,
        email: String,
        role: HouseholdRole
    ) -> HouseholdMember?

    @discardableResult
    func updateMember(
        id: UUID,
        mutator: (inout HouseholdMember) -> Void
    ) -> HouseholdMember?

    @discardableResult
    func archiveMember(id: UUID, strategy: ArchiveStrategy) -> ArchiveOutcome
    @discardableResult
    func restoreMember(id: UUID) -> Bool

    /// Transfer ownership to another active member. Owner-only; engine refuses
    /// otherwise. Required before owner self-archive.
    @discardableResult
    func transferOwnership(toMemberId: UUID) -> Bool

    // MARK: 6.3 Splits

    @discardableResult
    func recordSplit(
        transactionId: UUID,
        totalCents: Int,
        paidByMemberId: UUID,
        method: ExpenseSplitMethod,
        lines: [SplitLine]
    ) -> [ExpenseShare]

    @discardableResult
    func editSplit(
        transactionId: UUID,
        totalCents: Int,
        paidByMemberId: UUID,
        method: ExpenseSplitMethod,
        lines: [SplitLine]
    ) -> [ExpenseShare]

    func deleteSplit(transactionId: UUID)

    // MARK: 6.4 Settlement

    @discardableResult
    func settleUp(
        fromMemberId: UUID,
        toMemberId: UUID,
        amount: Int,
        materializeAsTransaction: Bool
    ) -> Settlement?

    func unsettle(settlementId: UUID)

    // MARK: 6.5 Snapshot

    func snapshot(monthKey: String, currentMemberId: UUID) -> HouseholdSnapshot
}
