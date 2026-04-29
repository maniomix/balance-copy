import Foundation
import Supabase

// ============================================================
// MARK: - SubscriptionStateSync (Phase 5.6)
// ============================================================
// Cloud-syncs the local SubscriptionStoreSnapshot.
//
// UserDefaults stays the synchronous fast path inside the app
// (SubscriptionStorePersistence.save/load are sync). This layer:
//   • pull(): on sign-in, fetch the latest snapshot and overwrite
//     UserDefaults so the device matches cloud state.
//   • push(_:): on save, fire-and-forget upsert to Supabase.
//
// Conflict policy: last-write-wins on `updated_at`. Matches the
// rest of the rebuild — no manual merge UI for this domain.
// ============================================================

@MainActor
enum SubscriptionStateSync {

    private static var client: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - Pull

    /// Fetch the cloud snapshot (if any) and write it to UserDefaults so
    /// the existing sync `SubscriptionStorePersistence.load()` returns it
    /// on the next call. Idempotent — safe to call on every cold start.
    static func pull() async {
        struct Row: Codable { let snapshot: SubscriptionStoreSnapshot }
        do {
            let rows: [Row] = try await client
                .from("subscription_state")
                .select("snapshot")
                .limit(1)
                .execute()
                .value
            guard let snapshot = rows.first?.snapshot else { return }
            // Persist to UserDefaults via the existing sync path.
            SubscriptionStorePersistence.save(snapshot)
            SecureLogger.info("Subscription snapshot pulled from cloud")
        } catch {
            SecureLogger.warning("Subscription snapshot pull failed")
        }
    }

    // MARK: - Push

    /// Upsert the snapshot to Supabase. Fire-and-forget — failures don't
    /// block the user's edit.
    static func push(_ snapshot: SubscriptionStoreSnapshot) {
        Task.detached(priority: .background) {
            await pushBlocking(snapshot)
        }
    }

    /// Awaitable variant for callers (e.g. sign-out flow) that need to
    /// know the write landed before proceeding.
    static func pushBlocking(_ snapshot: SubscriptionStoreSnapshot) async {
        struct UpsertRow: Encodable {
            let owner_id: String
            let snapshot: SubscriptionStoreSnapshot
        }
        guard let userId = AuthManager.shared.currentUser?.id.uuidString else { return }
        do {
            try await client
                .from("subscription_state")
                .upsert(UpsertRow(owner_id: userId, snapshot: snapshot),
                        onConflict: "owner_id")
                .execute()
        } catch {
            SecureLogger.warning("Subscription snapshot push failed")
        }
    }
}
