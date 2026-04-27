import Foundation

// ============================================================
// MARK: - Subscription Store (Phase 2 — Persistence Refactor)
// ============================================================
//
// Single durable container for all subscription state. Replaces the
// three pre-rebuild UserDefaults keys (`subscriptions.manual_v1`,
// `subscriptions.status_overrides`, `subscriptions.hidden_merchants`)
// with one Codable snapshot.
//
// `analyze()` no longer rebuilds the in-memory list from scratch —
// it merges detected candidates into `records`, keyed by `merchantKey`.
// User edits persist on the record itself (status + `userEditedStatus`,
// notes, custom renewal date, etc.) and survive re-detection.
//
// ============================================================

struct SubscriptionStoreSnapshot: Codable {
    /// Schema version. Bump on breaking changes; leave decoder defaults
    /// permissive so older snapshots still load.
    var version: Int = 1

    /// All known subscriptions, keyed by `merchantKey` for merge.
    /// Hidden ones stay here too — `hiddenKeys` is the filter, not a
    /// deletion. Phase 4's "Hidden" section reads from this list directly.
    var records: [DetectedSubscription] = []

    /// Merchant keys the user has chosen to hide. Stored separately so a
    /// hide survives even if the underlying record is later removed and
    /// re-detected.
    var hiddenKeys: Set<String> = []

    /// One-shot bag of legacy status overrides carried over from the
    /// pre-rebuild UserDefaults key. Each entry is consumed (and removed
    /// from this dict) the first time `analyze()` produces a record with
    /// the matching `merchantKey`.
    var legacyStatusOverridesByKey: [String: String] = [:]
}

// MARK: - On-disk persistence

enum SubscriptionStorePersistence {
    /// Single UserDefaults key holding the encoded snapshot. Promotion to
    /// an Application Support file is a Phase 9 concern — UserDefaults
    /// remains good-enough for the snapshot's expected size.
    static let snapshotKey = "subscriptions.store_v2"

    /// Legacy keys, only read once for migration then cleared.
    static let legacyManualKey = "subscriptions.manual_v1"
    static let legacyStatusOverridesKey = "subscriptions.status_overrides"
    static let legacyHiddenMerchantsKey = "subscriptions.hidden_merchants"

    static func load() -> SubscriptionStoreSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(SubscriptionStoreSnapshot.self, from: data)
    }

    static func save(_ snapshot: SubscriptionStoreSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: snapshotKey)
    }

    /// One-shot migration from the three legacy UserDefaults keys. Returns
    /// the migrated snapshot if any legacy data was found, otherwise nil.
    /// Clears the legacy keys on success so subsequent launches skip this.
    static func migrateLegacyIfPresent() -> SubscriptionStoreSnapshot? {
        let defaults = UserDefaults.standard
        let manualData = defaults.data(forKey: legacyManualKey)
        let overridesDict = defaults.dictionary(forKey: legacyStatusOverridesKey) as? [String: String]
        let hiddenArr = defaults.array(forKey: legacyHiddenMerchantsKey) as? [String]

        // Nothing to migrate.
        if manualData == nil && (overridesDict?.isEmpty ?? true) && (hiddenArr?.isEmpty ?? true) {
            return nil
        }

        var snapshot = SubscriptionStoreSnapshot()

        if let manualData,
           let manual = try? JSONDecoder().decode([DetectedSubscription].self, from: manualData) {
            // Pre-rebuild manual records may lack `source` / `merchantKey`;
            // the custom decoder fills those in. Force `source = .manual`
            // for safety since these came out of the legacy manual list.
            snapshot.records = manual.map { sub in
                var s = sub
                s.source = .manual
                if s.merchantKey.isEmpty {
                    s.merchantKey = DetectedSubscription.merchantKey(for: s.merchantName)
                }
                return s
            }
        }

        if let hiddenArr {
            snapshot.hiddenKeys = Set(hiddenArr)
        }

        if let overridesDict {
            snapshot.legacyStatusOverridesByKey = overridesDict
        }

        save(snapshot)

        // Clear legacy keys so this only runs once.
        defaults.removeObject(forKey: legacyManualKey)
        defaults.removeObject(forKey: legacyStatusOverridesKey)
        defaults.removeObject(forKey: legacyHiddenMerchantsKey)

        return snapshot
    }
}
