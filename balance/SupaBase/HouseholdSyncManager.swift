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
        // v1: legacy shape with `splitExpenses` aggregate.
        // v2: adds `expenseShares` (per-share rows) + `pendingInvites`
        // (P6.1). Transition writes both legacy and new fields so older
        // clients keep working; reads detect the version and expand v1
        // payloads on the fly via HouseholdShareExpansion.
        var schema_version: Int = 2
        let household: Household?
        let splitExpenses: [SplitExpense]
        let expenseShares: [ExpenseShare]
        let settlements: [Settlement]
        let sharedBudgets: [SharedBudget]
        let sharedGoals: [SharedGoal]
        let pendingInvites: [HouseholdInvite]

        enum CodingKeys: String, CodingKey {
            case schema_version, household, splitExpenses, expenseShares
            case settlements, sharedBudgets, sharedGoals, pendingInvites
        }

        init(
            schema_version: Int = 2,
            household: Household?,
            splitExpenses: [SplitExpense],
            expenseShares: [ExpenseShare] = [],
            settlements: [Settlement],
            sharedBudgets: [SharedBudget],
            sharedGoals: [SharedGoal],
            pendingInvites: [HouseholdInvite] = []
        ) {
            self.schema_version = schema_version
            self.household = household
            self.splitExpenses = splitExpenses
            self.expenseShares = expenseShares
            self.settlements = settlements
            self.sharedBudgets = sharedBudgets
            self.sharedGoals = sharedGoals
            self.pendingInvites = pendingInvites
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schema_version = (try? c.decode(Int.self, forKey: .schema_version)) ?? 1
            household = try? c.decode(Household.self, forKey: .household)
            splitExpenses = (try? c.decode([SplitExpense].self, forKey: .splitExpenses)) ?? []
            expenseShares = (try? c.decode([ExpenseShare].self, forKey: .expenseShares)) ?? []
            settlements = (try? c.decode([Settlement].self, forKey: .settlements)) ?? []
            sharedBudgets = (try? c.decode([SharedBudget].self, forKey: .sharedBudgets)) ?? []
            sharedGoals = (try? c.decode([SharedGoal].self, forKey: .sharedGoals)) ?? []
            pendingInvites = (try? c.decode([HouseholdInvite].self, forKey: .pendingInvites)) ?? []
        }
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
        sharedGoals: [SharedGoal],
        expenseShares: [ExpenseShare] = [],
        pendingInvites: [HouseholdInvite] = []
    ) async throws {
        guard let userId = currentUser?.id.uuidString else { return }

        // Embed members onto the household so the snapshot is self-contained.
        var fullHousehold = household
        fullHousehold.members = members

        // Transition behaviour: write BOTH legacy `splitExpenses` and new
        // `expenseShares` so older clients keep reading. Once P3.3 lands and
        // the manager pushes shares as source of truth, the legacy field can
        // be derived from shares before push.
        let row = HSRow(
            owner_id: userId,
            snapshot: HouseholdSnapshotDTO(
                schema_version: 2,
                household: fullHousehold,
                splitExpenses: splitExpenses,
                expenseShares: expenseShares,
                settlements: settlements,
                sharedBudgets: sharedBudgets,
                sharedGoals: sharedGoals,
                pendingInvites: pendingInvites
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

        // v1 → v2 expansion: if the snapshot was written by an older client
        // (no `expenseShares` field), expand legacy splitExpenses into shares
        // using the same rules the new engine writes with. Local store gets
        // the expanded list; legacy field stays untouched until the next push.
        let shares: [ExpenseShare]
        if snap.expenseShares.isEmpty && !snap.splitExpenses.isEmpty {
            shares = HouseholdShareExpansion.expand(snap.splitExpenses, members: h.members)
            SecureLogger.info("Household snapshot v1→v2: expanded \(snap.splitExpenses.count) expenses into \(shares.count) shares")
        } else {
            shares = snap.expenseShares
        }

        return HouseholdCloudData(
            household: h,
            splitExpenses: snap.splitExpenses,
            settlements: snap.settlements,
            sharedBudgets: snap.sharedBudgets,
            sharedGoals: snap.sharedGoals,
            expenseShares: shares,
            pendingInvites: snap.pendingInvites
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
    /// Per-share rows. Either decoded directly from a v2 snapshot or expanded
    /// from `splitExpenses` when the snapshot is v1.
    let expenseShares: [ExpenseShare]
    let pendingInvites: [HouseholdInvite]
}
