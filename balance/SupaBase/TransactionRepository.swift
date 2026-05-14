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
        /// Cross-platform "name" column. macOS calls it `payee`; iOS calls it
        /// `name`; the cloud column is `merchant`.
        let merchant: String?
        let note: String?
        let type: String              // 'expense' | 'income'
        let payment_method: String    // 'cash' | 'card'
        let is_flagged: Bool
        let linked_goal_id: String?
        let transfer_group_id: String?
        /// Soft FK to a HouseholdMember.id. **PULL ONLY** on iOS — iOS has
        /// no UI to set this, and sending null on every iOS upsert would
        /// wipe macOS's per-transaction attributions on first sync. The
        /// custom `encode(to:)` below intentionally omits this field.
        /// See `feedback_asymmetric_cloud_columns` memory.
        let household_member_id: String?
        let updated_at: String?

        enum CodingKeys: String, CodingKey {
            case id, account_id, category_key, amount, occurred_at, merchant, note, type
            case payment_method, is_flagged, linked_goal_id, transfer_group_id
            case household_member_id, updated_at
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encodeIfPresent(account_id, forKey: .account_id)
            try c.encodeIfPresent(category_key, forKey: .category_key)
            try c.encode(amount, forKey: .amount)
            try c.encode(occurred_at, forKey: .occurred_at)
            try c.encodeIfPresent(merchant, forKey: .merchant)
            try c.encodeIfPresent(note, forKey: .note)
            try c.encode(type, forKey: .type)
            try c.encode(payment_method, forKey: .payment_method)
            try c.encode(is_flagged, forKey: .is_flagged)
            try c.encodeIfPresent(linked_goal_id, forKey: .linked_goal_id)
            try c.encodeIfPresent(transfer_group_id, forKey: .transfer_group_id)
            try c.encodeIfPresent(updated_at, forKey: .updated_at)
            // household_member_id intentionally NOT encoded — macOS owns this.
        }

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
        let idStrings = ids.map(\.uuidString)
        SecureLogger.info("DELETE transactions: requesting \(idStrings.count) ids — first: \(idStrings.first ?? "nil")")
        do {
            // `.select()` forces PostgREST to return the deleted rows in the
            // body — that lets us VERIFY the delete actually affected rows
            // and isn't being silently no-op'd by RLS or a stale auth token.
            struct DeletedRow: Codable { let id: String }
            let deleted: [DeletedRow] = try await client
                .from("transactions")
                .delete()
                .in("id", values: idStrings)
                .select("id")
                .execute()
                .value
            SecureLogger.info("DELETE transactions: \(deleted.count) row(s) actually removed from cloud")
            if deleted.count != idStrings.count {
                SecureLogger.warning("DELETE transactions: requested \(idStrings.count) but cloud only removed \(deleted.count). RLS or stale token suspected.")
            }
        } catch {
            SecureLogger.error("DELETE transactions failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Mapping

    private func makeRow(from tx: Transaction) -> Row {
        Row(
            id: tx.id.uuidString,
            account_id: tx.accountId?.uuidString,
            category_key: tx.category.storageKey,
            amount: tx.amount,
            occurred_at: Row.isoOut.string(from: tx.date),
            merchant: tx.name.isEmpty ? nil : tx.name,
            note: tx.note.isEmpty ? nil : tx.note,
            type: tx.type.rawValue,
            payment_method: tx.paymentMethod.rawValue,
            is_flagged: tx.isFlagged,
            linked_goal_id: tx.linkedGoalId?.uuidString,
            transfer_group_id: tx.transferGroupId?.uuidString,
            household_member_id: tx.householdMemberId?.uuidString,  // populated locally; omitted on encode (see Row.encode)
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
            name: row.merchant ?? "",
            note: row.note ?? "",
            paymentMethod: pm,
            type: type,
            attachmentData: nil,            // attachments handled separately
            attachmentType: nil,
            accountId: row.account_id.flatMap(UUID.init(uuidString:)),
            isFlagged: row.is_flagged,
            linkedGoalId: row.linked_goal_id.flatMap(UUID.init(uuidString:)),
            lastModified: lastModified,
            transferGroupId: row.transfer_group_id.flatMap(UUID.init(uuidString:)),
            householdMemberId: row.household_member_id.flatMap(UUID.init(uuidString:))
        )
    }
}
