import Foundation
import Supabase

// ============================================================
// MARK: - SavedFilterPresetSync (Phase 5.8)
// ============================================================
// Mirrors local SavedFilterPresetStore to public.saved_filter_presets.
// UserDefaults stays the synchronous fast path; this just keeps the
// cloud copy reconciled.
//
// Conflict policy: client list overwrites cloud (delete-missing +
// upsert). Last-writer wins across devices, same as the rest of the
// rebuild.
// ============================================================

@MainActor
enum SavedFilterPresetSync {

    private static var client: SupabaseClient { SupabaseManager.shared.client }

    private struct Row: Codable {
        let id: String
        let name: String
        let filter: TransactionFilter
        let sort_order: Int
    }

    // MARK: - Pull

    static func pull() async {
        do {
            let rows: [Row] = try await client
                .from("saved_filter_presets")
                .select("id, name, filter, sort_order")
                .order("sort_order", ascending: true)
                .execute()
                .value
            let presets: [SavedFilterPreset] = rows.compactMap { r in
                guard let uuid = UUID(uuidString: r.id) else { return nil }
                return SavedFilterPreset(id: uuid, name: r.name, filter: r.filter)
            }
            SavedFilterPresetStore.shared.replaceFromCloud(presets)
            SecureLogger.info("Filter presets pulled: \(presets.count)")
        } catch {
            SecureLogger.warning("Filter preset pull failed")
        }
    }

    // MARK: - Push

    /// Reconcile: delete cloud rows missing locally, then upsert all local
    /// rows. Fire-and-forget.
    static func push(_ presets: [SavedFilterPreset]) {
        Task.detached(priority: .background) {
            await pushBlocking(presets)
        }
    }

    static func pushBlocking(_ presets: [SavedFilterPreset]) async {
        do {
            // 1. Server-side ids
            struct IdRow: Codable { let id: String }
            let server: [IdRow] = try await client
                .from("saved_filter_presets")
                .select("id")
                .execute()
                .value
            let serverIds = Set(server.map(\.id))
            let localIds = Set(presets.map { $0.id.uuidString })

            // 2. Delete removed
            let removed = serverIds.subtracting(localIds)
            if !removed.isEmpty {
                try await client
                    .from("saved_filter_presets")
                    .delete()
                    .in("id", values: Array(removed))
                    .execute()
            }

            // 3. Upsert all locals (sort_order = array index so reorder syncs)
            let payload = presets.enumerated().map { (i, p) in
                Row(id: p.id.uuidString, name: p.name, filter: p.filter, sort_order: i)
            }
            guard !payload.isEmpty else { return }
            try await client
                .from("saved_filter_presets")
                .upsert(payload, onConflict: "id")
                .execute()
        } catch {
            SecureLogger.warning("Filter preset push failed")
        }
    }
}
