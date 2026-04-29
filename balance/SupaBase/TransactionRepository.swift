import Foundation
import Supabase

// ============================================================
// MARK: - TransactionRepository (Phase 5.3)
// ============================================================
// Round-trips Swift `Transaction` ↔ `public.transactions` row.
//
// `Transaction` itself stays Codable for local-snapshot use
// (UserDefaults, offline cache). The wire format is a separate
// internal `Row` DTO so the column shape is decoupled from the
// in-memory type.
//
// Storage notes:
//   • amount is stored as bigint cents (Swift Int matches PG bigint).
//   • category becomes a text key (e.g. "groceries", "custom:Coffee");
//     Swift `Category` is reconstructed from it on read.
//   • transfer_group_id replaces the old transfer_pair_id semantics.
//   • owner_id is filled by the `fill_owner_id` trigger.
// ============================================================

@MainActor
final class TransactionRepository {
    static let shared = TransactionRepository()
    private init() {}

    private var client: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - DTO

    private struct Row: Codable {
        let id: String
        let account_id: String?
        let category_key: String?
        let amount: Int
        let occurred_at: String
        let note: String?
        let type: String              // 'expense' | 'income'
        let payment_method: String    // 'cash' | 'card'
        let is_flagged: Bool
        let linked_goal_id: String?
        let transfer_group_id: String?
        let updated_at: String?

        static let isoIn:  ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        static let isoOut: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()

        // Tolerant date parser — DB may return either with or without fractional seconds.
        static func parseDate(_ s: String) -> Date? {
            if let d = isoIn.date(from: s) { return d }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return plain.date(from: s)
        }
    }

    // MARK: - Fetch

    func fetchAll() async throws -> [Transaction] {
        let rows: [Row] = try await client
            .from("transactions")
            .select()
            .order("occurred_at", ascending: false)
            .execute()
            .value
        return rows.compactMap(toTransaction(_:))
    }

    // MARK: - Upsert

    func upsert(_ tx: Transaction) async throws {
        let row = makeRow(from: tx)
        try await client
            .from("transactions")
            .upsert(row, onConflict: "id")
            .execute()
    }

    func upsertMany(_ txs: [Transaction]) async throws {
        guard !txs.isEmpty else { return }
        let rows = txs.map(makeRow(from:))
        try await client
            .from("transactions")
            .upsert(rows, onConflict: "id")
            .execute()
    }

    // MARK: - Delete

    func delete(id: UUID) async throws {
        try await client
            .from("transactions")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func deleteMany(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await client
            .from("transactions")
            .delete()
            .in("id", values: ids.map(\.uuidString))
            .execute()
    }

    // MARK: - Mapping

    private func makeRow(from tx: Transaction) -> Row {
        Row(
            id: tx.id.uuidString,
            account_id: tx.accountId?.uuidString,
            category_key: tx.category.storageKey,
            amount: tx.amount,
            occurred_at: Row.isoOut.string(from: tx.date),
            note: tx.note.isEmpty ? nil : tx.note,
            type: tx.type.rawValue,
            payment_method: tx.paymentMethod.rawValue,
            is_flagged: tx.isFlagged,
            linked_goal_id: tx.linkedGoalId?.uuidString,
            transfer_group_id: tx.transferGroupId?.uuidString,
            updated_at: nil  // never sent — moddatetime trigger sets it
        )
    }

    private func toTransaction(_ row: Row) -> Transaction? {
        guard let id = UUID(uuidString: row.id),
              let date = Row.parseDate(row.occurred_at) else { return nil }
        let type = TransactionType(rawValue: row.type) ?? .expense
        let pm   = PaymentMethod(rawValue: row.payment_method) ?? .card
        let cat  = (row.category_key.flatMap(Category.init(storageKey:))) ?? .other
        let lastModified = row.updated_at.flatMap(Row.parseDate(_:)) ?? date
        return Transaction(
            id: id,
            amount: row.amount,
            date: date,
            category: cat,
            note: row.note ?? "",
            paymentMethod: pm,
            type: type,
            attachmentData: nil,            // attachments handled separately
            attachmentType: nil,
            accountId: row.account_id.flatMap(UUID.init(uuidString:)),
            isFlagged: row.is_flagged,
            linkedGoalId: row.linked_goal_id.flatMap(UUID.init(uuidString:)),
            lastModified: lastModified,
            transferGroupId: row.transfer_group_id.flatMap(UUID.init(uuidString:))
        )
    }
}
