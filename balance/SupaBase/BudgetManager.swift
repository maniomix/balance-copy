import Foundation
import Supabase

// ============================================================
// MARK: - BudgetManager (Phase 5.4)
// ============================================================
// Round-trips Swift's per-month budget overrides against the new
// `monthly_budgets` and `monthly_category_budgets` tables.
//
// In-memory shape (Store):
//   var budgetsByMonth:        [String: Int]            // YYYY-MM → cents
//   var categoryBudgetsByMonth:[String: [String: Int]]  // YYYY-MM → key → cents
//
// owner_id is filled by the `fill_owner_id` trigger on insert.
// ============================================================

@MainActor
final class BudgetManager {
    static let shared = BudgetManager()
    private init() {}

    private var client: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - Monthly total budget

    private struct MBRow: Codable {
        let month: String
        let total_amount: Int
    }

    func fetchMonthlyTotals() async throws -> [String: Int] {
        let rows: [MBRow] = try await client
            .from("monthly_budgets")
            .select("month, total_amount")
            .execute()
            .value
        var dict: [String: Int] = [:]
        for r in rows { dict[r.month] = r.total_amount }
        return dict
    }

    /// Reconcile the per-month totals: upsert local entries, delete server
    /// rows for months not present locally.
    func syncMonthlyTotals(_ totals: [String: Int]) async throws {
        // 1. Server-side months
        struct MonthRow: Codable { let month: String }
        let server: [MonthRow] = try await client
            .from("monthly_budgets")
            .select("month")
            .execute()
            .value
        let serverMonths = Set(server.map(\.month))
        let localMonths  = Set(totals.keys)

        // 2. Delete months removed locally
        let removed = serverMonths.subtracting(localMonths)
        if !removed.isEmpty {
            try await client
                .from("monthly_budgets")
                .delete()
                .in("month", values: Array(removed))
                .execute()
        }

        // 3. Upsert local rows
        struct UpsertRow: Encodable {
            let month: String
            let total_amount: Int
        }
        let payload = totals.map { UpsertRow(month: $0.key, total_amount: $0.value) }
        guard !payload.isEmpty else { return }
        try await client
            .from("monthly_budgets")
            .upsert(payload, onConflict: "owner_id,month")
            .execute()
    }

    // MARK: - Per-category monthly budgets

    private struct MCBRow: Codable {
        let month: String
        let category_key: String
        let amount: Int
    }

    func fetchCategoryBudgets() async throws -> [String: [String: Int]] {
        let rows: [MCBRow] = try await client
            .from("monthly_category_budgets")
            .select("month, category_key, amount")
            .execute()
            .value
        var out: [String: [String: Int]] = [:]
        for r in rows {
            out[r.month, default: [:]][r.category_key] = r.amount
        }
        return out
    }

    /// Reconcile per-category caps: upsert all local rows, delete server rows
    /// for months not present locally.
    func syncCategoryBudgets(_ cats: [String: [String: Int]]) async throws {
        // 1. Server months
        struct MonthRow: Codable { let month: String }
        let server: [MonthRow] = try await client
            .from("monthly_category_budgets")
            .select("month")
            .execute()
            .value
        let serverMonths = Set(server.map(\.month))
        let localMonths  = Set(cats.keys)

        // 2. Delete months no longer in local
        let removed = serverMonths.subtracting(localMonths)
        if !removed.isEmpty {
            try await client
                .from("monthly_category_budgets")
                .delete()
                .in("month", values: Array(removed))
                .execute()
        }

        // 3. Upsert local rows
        struct UpsertRow: Encodable {
            let month: String
            let category_key: String
            let amount: Int
        }
        var payload: [UpsertRow] = []
        for (month, byCat) in cats {
            for (key, amount) in byCat {
                payload.append(UpsertRow(month: month, category_key: key, amount: amount))
            }
        }
        guard !payload.isEmpty else { return }
        try await client
            .from("monthly_category_budgets")
            .upsert(payload, onConflict: "owner_id,month,category_key")
            .execute()
    }

    // MARK: - Whole-month delete (used by Settings → "Delete this month")

    func deleteMonth(_ month: String) async throws {
        try await client.from("monthly_budgets").delete().eq("month", value: month).execute()
        try await client.from("monthly_category_budgets").delete().eq("month", value: month).execute()
    }
}
