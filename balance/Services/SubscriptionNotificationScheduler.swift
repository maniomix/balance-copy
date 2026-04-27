import Foundation
@preconcurrency import UserNotifications

// ============================================================
// MARK: - AISubscription Notification Scheduler (Phase 3c — iOS port)
// ============================================================
//
// Local notification scheduling for subscription events. Mirrors
// macOS Centmond `SubscriptionNotificationScheduler`. Rebuilds its
// full plan on every call rather than diffing in place — cheap, and
// a clean rebuild guarantees we don't accumulate stale alerts when
// a subscription is paused, cancelled, or edited.
//
// Identifier scheme: `sub-<kind>-<id>-<extra>` so we target removals
// without nuking unrelated notifications.
//
// Call from: subscription list on appear, after reconciliation applies
// a match, Settings toggle changes.
// ============================================================

enum SubscriptionNotificationScheduler {

    // MARK: - UserDefaults keys (mirror Settings)

    static let masterEnabledKey         = "subscriptionNotificationsEnabled"
    static let trialAlertDaysKey        = "subscriptionTrialAlertDays"
    static let chargeAlertEnabledKey    = "subscriptionChargeAlertEnabled"
    static let chargeAlertThresholdKey  = "subscriptionChargeAlertThreshold"
    static let priceHikeAlertEnabledKey = "subscriptionPriceHikeAlertEnabled"
    static let unusedAlertEnabledKey    = "subscriptionUnusedAlertEnabled"

    // MARK: - Constants

    private static let identifierPrefix       = "sub-"
    private static let scheduleHorizonDays    = 60
    private static let unusedThresholdDays    = 60
    private static let defaultTrialLeadDays   = 2
    /// Charge-alert threshold in cents. UI presents as dollars.
    private static let defaultChargeThresholdCents = 1_000
    private static let alertHour = 9

    // MARK: - Public API

    /// Request notification authorization. Call only when the user enables
    /// a notification class, never silently at app launch.
    static func requestAuthorization(_ completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    /// Wipe & rebuild every subscription-prefixed notification. Cheap; safe
    /// to call after any subscription mutation. When the master toggle is
    /// off this still clears so prior alerts don't keep firing.
    @MainActor
    static func rescheduleAll(store: Store) {
        let defaults = UserDefaults.standard
        let masterEnabled = defaults.object(forKey: masterEnabledKey) as? Bool ?? true

        // Snapshot state before the async clear so the completion closure
        // doesn't need to re-read the (possibly mutated) store.
        let subs = store.aiSubscriptions.filter { $0.status == .active || $0.status == .trial }
        let priceChanges = store.aiSubscriptionPriceChanges

        clearAll {
            guard masterEnabled else { return }
            let chargeEnabled  = defaults.object(forKey: chargeAlertEnabledKey)    as? Bool ?? true
            let priceEnabled   = defaults.object(forKey: priceHikeAlertEnabledKey) as? Bool ?? true
            let unusedEnabled  = defaults.object(forKey: unusedAlertEnabledKey)    as? Bool ?? true
            let trialLeadDays  = defaults.object(forKey: trialAlertDaysKey)        as? Int ?? defaultTrialLeadDays
            let thresholdCents = defaults.object(forKey: chargeAlertThresholdKey)  as? Int ?? defaultChargeThresholdCents

            Self.scheduleTrialAlerts(subs: subs, leadDays: trialLeadDays)
            if chargeEnabled { Self.scheduleChargeAlerts(subs: subs, thresholdCents: thresholdCents) }
            if priceEnabled  { Self.schedulePriceHikeAlerts(subs: subs, priceChanges: priceChanges) }
            if unusedEnabled { Self.scheduleUnusedAlerts(subs: subs) }
        }
    }

    // MARK: - Clearing

    private static func clearAll(then continuation: @escaping () -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
            DispatchQueue.main.async { continuation() }
        }
    }

    // MARK: - Schedulers

    private static func scheduleTrialAlerts(subs: [AISubscription], leadDays: Int) {
        let cal = Calendar.current
        for sub in subs where sub.isTrial {
            guard let end = sub.trialEndsAt else { continue }
            guard let alertDate = cal.date(byAdding: .day, value: -max(leadDays, 0), to: end) else { continue }
            guard alertDate > Date() else { continue }

            let body: String
            if leadDays == 0 {
                body = "Trial ends today — will start charging \(fmt(cents: sub.amount))."
            } else {
                body = "Trial ends in \(leadDays) day\(leadDays == 1 ? "" : "s") — will start charging \(fmt(cents: sub.amount))."
            }

            schedule(
                id: "\(identifierPrefix)trial-\(sub.id.uuidString)",
                title: sub.serviceName,
                body: body,
                category: "SUB_TRIAL",
                fireAt: morningOf(alertDate)
            )
        }
    }

    private static func scheduleChargeAlerts(subs: [AISubscription], thresholdCents: Int) {
        let to = Calendar.current.date(byAdding: .day, value: scheduleHorizonDays, to: Date()) ?? Date()
        let upcoming = SubscriptionForecast.upcomingCharges(
            for: subs, from: Date(), to: to, includeTrialEnds: false
        )
        let cal = Calendar.current
        for charge in upcoming {
            guard charge.amount >= thresholdCents else { continue }
            // Schedule the morning BEFORE the charge so the user has time
            // to react (move funds, cancel, etc.).
            let dayBefore = cal.date(byAdding: .day, value: -1, to: charge.date) ?? charge.date
            let fireAt = morningOf(dayBefore)
            guard fireAt > Date() else { continue }

            let stamp = String(Int(charge.date.timeIntervalSince1970))
            schedule(
                id: "\(identifierPrefix)charge-\(charge.subscriptionID.uuidString)-\(stamp)",
                title: charge.displayName,
                body: "\(fmt(cents: charge.amount)) charges tomorrow",
                category: "SUB_CHARGE",
                fireAt: fireAt
            )
        }
    }

    private static func schedulePriceHikeAlerts(
        subs: [AISubscription],
        priceChanges: [AISubscriptionPriceChange]
    ) {
        let cutoff = Calendar.current.date(byAdding: .hour, value: -36, to: Date()) ?? Date()
        let subsByID = Dictionary(uniqueKeysWithValues: subs.map { ($0.id, $0) })
        for change in priceChanges where !change.acknowledged && change.observedAt >= cutoff {
            guard let sub = subsByID[change.subscriptionId] else { continue }
            let pct = Int(abs(change.percentChange) * 100)
            let dir = change.percentChange >= 0 ? "raised" : "dropped"
            let body = "Price \(dir) by \(pct)% — now \(fmt(cents: change.newAmount))."
            let fire = Date().addingTimeInterval(5) // near-immediate
            schedule(
                id: "\(identifierPrefix)pricehike-\(change.id.uuidString)",
                title: sub.serviceName,
                body: body,
                category: "SUB_PRICE_HIKE",
                fireAt: fire
            )
        }
    }

    private static func scheduleUnusedAlerts(subs: [AISubscription]) {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -unusedThresholdDays, to: Date()) ?? Date()
        for sub in subs where sub.status == .active {
            // "Unused" heuristic: charges land fine, but the subscription hasn't
            // been touched in ≥ 60 days (indicator via `updatedAt`). Schedule a
            // single one-shot for tomorrow morning.
            guard sub.createdAt < cutoff, sub.updatedAt < cutoff else { continue }
            let fire = morningOf(cal.date(byAdding: .day, value: 1, to: Date()) ?? Date())
            guard fire > Date() else { continue }
            schedule(
                id: "\(identifierPrefix)unused-\(sub.id.uuidString)",
                title: sub.serviceName,
                body: "Still using this? No changes in \(unusedThresholdDays) days at \(fmt(cents: sub.amount))/cycle.",
                category: "SUB_UNUSED",
                fireAt: fire
            )
        }
    }

    // MARK: - Low-level

    private static func schedule(id: String, title: String, body: String, category: String, fireAt: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private static func morningOf(_ date: Date) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = alertHour
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? date
    }

    private static func fmt(cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100.0)
    }
}
