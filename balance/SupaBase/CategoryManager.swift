import Foundation
import Supabase

// ============================================================
// MARK: - CategoryManager (Phase 5.2)
// ============================================================
// Owns the Supabase round-trip for *custom* categories. Built-in
// categories (groceries, rent, …) live in the `Category` enum and
// never touch the DB.
//
// Storage: `public.categories` filtered by `is_custom = true`.
// `owner_id` is filled by the `fill_owner_id` trigger so Swift
// doesn't have to send it.
// ============================================================

@MainActor
final class CategoryManager {
    static let shared = CategoryManager()
    private init() {}

    private var client: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - Fetch

    /// Fetch the user's custom categories ordered by sort_order.
    func fetchCustom() async throws -> [CustomCategoryModel] {
        let response: [CustomCategoryModel] = try await client
            .from("categories")
            .select("id, name, icon, color_hex, sort_order")
            .eq("is_custom", value: true)
            .order("sort_order", ascending: true)
            .execute()
            .value
        return response
    }

    // MARK: - Persist a full snapshot
    //
    // Reconcile the server-side `categories(is_custom=true)` rows with the
    // local `models` array: insert new ones, update changed, delete missing.
    // Called by the Store save path so the existing call site
    // `saveCustomCategories(...)` keeps working.
    func sync(_ models: [CustomCategoryModel]) async throws {
        // 1. Load current server state (id only)
        struct IdRow: Codable { let id: String }
        let serverIds: [IdRow] = try await client
            .from("categories")
            .select("id")
            .eq("is_custom", value: true)
            .execute()
            .value
        let serverIdSet = Set(serverIds.map(\.id))
        let localIdSet  = Set(models.map(\.id))

        // 2. Delete rows the user removed locally
        let removed = serverIdSet.subtracting(localIdSet)
        for id in removed {
            try await client
                .from("categories")
                .delete()
                .eq("id", value: id)
                .execute()
        }

        // 3. Upsert local rows. is_custom=true is added on the client side
        //    because it's not part of CustomCategoryModel.
        struct UpsertRow: Encodable {
            let id: String
            let name: String
            let icon: String
            let color_hex: String
            let sort_order: Int
            let is_custom: Bool
            let kind: String
        }
        let payload = models.map {
            UpsertRow(
                id: $0.id, name: $0.name, icon: $0.icon,
                color_hex: $0.colorHex, sort_order: $0.sortOrder,
                is_custom: true, kind: "expense"
            )
        }
        guard !payload.isEmpty else { return }
        try await client
            .from("categories")
            .upsert(payload, onConflict: "id")
            .execute()
    }

    // MARK: - Single-row helpers (used by AI actions and settings UI)

    func upsert(_ model: CustomCategoryModel) async throws {
        struct UpsertRow: Encodable {
            let id: String
            let name: String
            let icon: String
            let color_hex: String
            let sort_order: Int
            let is_custom: Bool
            let kind: String
        }
        let row = UpsertRow(
            id: model.id, name: model.name, icon: model.icon,
            color_hex: model.colorHex, sort_order: model.sortOrder,
            is_custom: true, kind: "expense"
        )
        try await client
            .from("categories")
            .upsert(row, onConflict: "id")
            .execute()
    }

    func delete(id: String) async throws {
        try await client
            .from("categories")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
