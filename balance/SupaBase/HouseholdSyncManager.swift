import Foundation
import Supabase

// ============================================================
// MARK: - Household Cloud Sync (Phase 5.7)
// ============================================================
//
// Per-user JSONB blob in `public.household_state` keyed on owner_id.
// Replaces the prior 7-table row-per-entity model — too much bespoke
// mapping for a domain that's loaded all-at-once and saved
// all-at-once.
//
// Cross-user invite-code lookup is deferred: `findHouseholdByInviteCode`
// always returns nil for now. Single-user households work end-to-end.
// Multi-user join is a future feature (a tiny `household_invites`
// table can be added then without touching this snapshot).
// ============================================================

extension SupabaseManager {

    // MARK: - Snapshot DTO

    private struct HouseholdSnapshotDTO: Codable {
        let household: Household?
        let splitExpenses: [SplitExpense]
        let settlements: [Settlement]
        let sharedBudgets: [SharedBudget]
        let sharedGoals: [SharedGoal]
    }

    private struct HSRow: Codable {
        let owner_id: String
        let snapshot: HouseholdSnapshotDTO
    }

    // MARK: - Push (called after every local edit)

    func pushHouseholdData(
        household: Household,
        members: [HouseholdMember],
        splitExpenses: [SplitExpense],
        settlements: [Settlement],
        sharedBudgets: [SharedBudget],
        sharedGoals: [SharedGoal]
    ) async throws {
        guard let userId = currentUser?.id.uuidString else { return }

        // Embed members onto the household so the snapshot is self-contained.
        var fullHousehold = household
        fullHousehold.members = members

        let row = HSRow(
            owner_id: userId,
            snapshot: HouseholdSnapshotDTO(
                household: fullHousehold,
                splitExpenses: splitExpenses,
                settlements: settlements,
                sharedBudgets: sharedBudgets,
                sharedGoals: sharedGoals
            )
        )
        try await client
            .from("household_state")
            .upsert(row, onConflict: "owner_id")
            .execute()
        SecureLogger.info("Household snapshot pushed")
    }

    // MARK: - Pull (called on sign-in)

    func pullHouseholdData(userId: String) async throws -> HouseholdCloudData? {
        let rows: [HSRow] = try await client
            .from("household_state")
            .select("owner_id, snapshot")
            .limit(1)
            .execute()
            .value
        guard let snap = rows.first?.snapshot, let h = snap.household else { return nil }
        return HouseholdCloudData(
            household: h,
            splitExpenses: snap.splitExpenses,
            settlements: snap.settlements,
            sharedBudgets: snap.sharedBudgets,
            sharedGoals: snap.sharedGoals
        )
    }

    // MARK: - Cross-user lookup (deferred)
    //
    // The pre-rebuild model exposed cross-user invite-code discovery: a user
    // with a friend's code could find the friend's household and join. The
    // per-user JSONB layout doesn't permit cross-user queries by design (RLS
    // blocks reads outside auth.uid()).
    //
    // For v1, single-user households work; the join flow no-ops.
    // Re-enabling this is a future "household linking" phase: add a small
    // `household_invites` table with public read-by-code semantics.

    func findHouseholdByInviteCode(_ code: String) async throws -> Household? {
        SecureLogger.debug("findHouseholdByInviteCode: cross-user lookup disabled in Phase 5.7")
        return nil
    }

    func loadHouseholdMembers(householdId: UUID) async throws -> [HouseholdMember] {
        // Members live inside the JSONB snapshot — fetch the snapshot and
        // return the embedded members for the requesting user's household.
        guard let userId = currentUser?.id.uuidString else { return [] }
        if let cloud = try await pullHouseholdData(userId: userId),
           cloud.household.id == householdId {
            return cloud.household.members
        }
        return []
    }

    func saveHouseholdMember(_ member: HouseholdMember, householdId: UUID) async throws {
        // No-op — members are persisted as part of the snapshot in
        // pushHouseholdData. Kept for API compatibility with the join flow.
    }

    /// Hard-delete the user's household row in the cloud. Called from
    /// HouseholdManager.deleteHousehold so the cloud doesn't resurrect a
    /// household onto a fresh device.
    func deleteHouseholdSnapshot() async throws {
        guard let userId = currentUser?.id.uuidString else { return }
        try await client
            .from("household_state")
            .delete()
            .eq("owner_id", value: userId)
            .execute()
        SecureLogger.info("Household snapshot deleted from cloud")
    }
}

// MARK: - Cloud Data Container

/// Container for all household data pulled from cloud.
struct HouseholdCloudData {
    let household: Household
    let splitExpenses: [SplitExpense]
    let settlements: [Settlement]
    let sharedBudgets: [SharedBudget]
    let sharedGoals: [SharedGoal]
}
