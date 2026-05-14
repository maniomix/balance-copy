import Foundation
import Supabase

// ============================================================
// MARK: - SubscriptionsTableSync (Track B2 — read-only cloud sync)
// ============================================================
// Pulls macOS-owned subscriptions from the columnar `subscriptions`
// table and overlays them into the local SubscriptionStoreSnapshot
// so the iOS engine renders them like any other DetectedSubscription.
//
// **Read-only on iOS.** macOS is the source of truth for these rows
// today (it has the full Subscription model, charge reconciliation,
// price-change tracking, etc.). iOS won't push back here — local
// manual / auto-detected records stay in the snapshot but never get
// written to this table.
//
// Pruning rule: track every cloud-pulled id in
// `snapshot.cloudSubscriptionIds`. On each pull, IDs that were in
// the tracker but absent from the fresh pull get removed from
// `snapshot.records` — that handles macOS deletes without ever
// touching iOS-local subs.
//
// Realtime: register `subscriptions` in SupabaseManager's watched
// tables; `runRealtimeCycle` calls `pull()` on every tick.
// ============================================================

@MainActor
enum SubscriptionsTableSync {

    private static var client: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - Wire DTO

    private struct Row: Decodable {
        let id: String
        let service_name: String
        let merchant_key: String
        let category_name: String
        let amount: Int                      // bigint cents
        let currency: String
        let billing_cycle: String
        let custom_cadence_days: Int?
        let next_payment_date: String        // date "YYYY-MM-DD"
        let last_charge_date: String?
        let first_charge_date: String?
        let status: String
        let is_trial: Bool
        let trial_ends_at: String?
        let source: String?
        let auto_detected: Bool
        let notes: String?
        let created_at: String?
        let updated_at: String?
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = dateFormatter.date(from: s) { return d }
        return timestampFormatter.date(from: s)
    }

    // MARK: - Pull

    /// Fetch all `subscriptions` rows owned by the signed-in user (RLS
    /// handles owner filtering) and overlay them into the local snapshot.
    /// Idempotent — safe to call on every cold start and every realtime tick.
    static func pull() async {
        do {
            let rows: [Row] = try await client
                .from("subscriptions")
                .select()
                .is("deleted_at", value: nil)
                .order("updated_at", ascending: false)
                .execute()
                .value
            SecureLogger.info("Subscriptions columnar pull: \(rows.count) row(s)")
            applyRows(rows)
        } catch {
            SecureLogger.warning("Subscriptions columnar pull failed")
        }
    }

    // MARK: - Merge

    private static func applyRows(_ rows: [Row]) {
        var snapshot = SubscriptionStorePersistence.load() ?? SubscriptionStoreSnapshot()

        var freshIds = Set<UUID>()
        for row in rows {
            guard let id = UUID(uuidString: row.id) else { continue }
            freshIds.insert(id)

            let translated = translate(row, id: id)
            if let idx = snapshot.records.firstIndex(where: { $0.id == id }) {
                // Update in place — preserves iOS-only fields like
                // dismissedSuspectedUnused that aren't in the cloud schema.
                var existing = snapshot.records[idx]
                existing.merchantName = translated.merchantName
                existing.merchantKey = translated.merchantKey
                existing.expectedAmount = translated.expectedAmount
                existing.lastAmount = translated.lastAmount
                existing.billingCycle = translated.billingCycle
                existing.customCadenceDays = translated.customCadenceDays
                existing.nextRenewalDate = translated.nextRenewalDate
                existing.lastChargeDate = translated.lastChargeDate
                existing.status = translated.status
                existing.notes = translated.notes
                existing.isTrial = translated.isTrial
                existing.trialEndsAt = translated.trialEndsAt
                existing.updatedAt = translated.updatedAt
                // Lock iOS detection off these records — macOS owns them.
                existing.userEditedStatus = true
                existing.source = .detected
                snapshot.records[idx] = existing
            } else {
                snapshot.records.append(translated)
            }
        }

        // Prune cloud-tracked records that vanished from the pull.
        let removed = snapshot.cloudSubscriptionIds.subtracting(freshIds)
        if !removed.isEmpty {
            snapshot.records.removeAll { removed.contains($0.id) }
            SecureLogger.info("Subscriptions columnar pull: pruned \(removed.count) deleted on macOS")
        }
        snapshot.cloudSubscriptionIds = freshIds

        // Use the persistence writer directly (UserDefaults). Avoid
        // SubscriptionStorePersistence.save which also fires off
        // SubscriptionStateSync.push — that would mirror cloud data back
        // into a separate envelope table for no reason. Cloud overlay is
        // a read-only side path.
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: SubscriptionStorePersistence.snapshotKey)
        }
    }

    private static func translate(_ row: Row, id: UUID) -> DetectedSubscription {
        let cycle = BillingCycle(rawValue: row.billing_cycle) ?? .monthly
        let status: SubscriptionStatus = {
            switch row.status {
            case "trial":  return .active
            case "active", "paused", "cancelled", "suspected_unused":
                return SubscriptionStatus(rawValue: row.status) ?? .active
            default:       return .active
            }
        }()
        let nextPay = parseDate(row.next_payment_date) ?? Date()
        let createdAt = parseDate(row.created_at) ?? Date()
        let updatedAt = parseDate(row.updated_at) ?? createdAt

        return DetectedSubscription(
            id: id,
            merchantName: row.service_name,
            merchantKey: row.merchant_key.isEmpty
                ? DetectedSubscription.merchantKey(for: row.service_name)
                : row.merchant_key,
            category: .bills,
            expectedAmount: row.amount,
            lastAmount: row.amount,
            billingCycle: cycle,
            customCadenceDays: row.custom_cadence_days,
            nextRenewalDate: nextPay,
            lastChargeDate: parseDate(row.last_charge_date),
            status: status,
            source: .detected,
            linkedTransactionIds: [],
            notes: row.notes ?? "",
            createdAt: createdAt,
            updatedAt: updatedAt,
            isTrial: row.is_trial || row.status == "trial",
            trialEndsAt: parseDate(row.trial_ends_at),
            userEditedStatus: true,     // macOS owns status — block iOS detector
            dismissedSuspectedUnused: false,
            isAutoDetected: false,
            confidenceScore: 1.0,
            chargeHistory: [],
            detectedIntervalDays: cycle.approximateDays
        )
    }
}
