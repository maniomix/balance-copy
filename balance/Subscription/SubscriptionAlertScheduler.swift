import Foundation
@preconcurrency import UserNotifications

// ============================================================
// MARK: - Subscription Alert Scheduler (Phase 6a)
// ============================================================
//
// Local-notification scheduler keyed off the canonical
// `DetectedSubscription` model. Sits alongside the legacy
// `SubscriptionNotificationScheduler` (AISubscription-typed) until
// Phase 9 deletes the old one — different identifier prefix
// (`subv2-`) so the two never collide.
//
// Three alert classes:
//   • renewal — fires `leadDays` mornings before each upcoming
//     `nextRenewalDate` for active records.
//   • trial-ending — fires `trialLeadDays` mornings before
//     `trialEndsAt` when `isTrial` is set.
//   • price-changed — near-immediate fire when a record's
//     `priceChangePercent` magnitude crosses the threshold AND
//     the record was last updated within the last 36 hours.
//
// Persistence: prefs live in UserDefaults so the scheduler is
// addressable from anywhere without owning a settings store.
//
// Call from: `SubscriptionEngine.republish()` (every mutation +
// every analyze) and from the Preferences view's toggles.
//
// ============================================================

enum SubscriptionAlertScheduler {

    // MARK: - UserDefaults keys

    static let masterEnabledKey      = "subscriptions.alerts.masterEnabled"
    static let renewalEnabledKey     = "subscriptions.alerts.renewalEnabled"
    static let renewalLeadDaysKey    = "subscriptions.alerts.renewalLeadDays"
    static let trialEnabledKey       = "subscriptions.alerts.trialEnabled"
    static let trialLeadDaysKey      = "subscriptions.alerts.trialLeadDays"
    static let priceChangeEnabledKey = "subscriptions.alerts.priceChangeEnabled"

    // MARK: - Defaults

    static let defaultRenewalLeadDays  = 2
    static let defaultTrialLeadDays    = 2
    static let priceChangeThresholdPct = 2.0  // |%| ≥ 2.0 fires
    private static let priceChangeWindowHours = 36
    private static let alertHour = 9
    private static let identifierPrefix = "subv2-"

    // MARK: - Authorization

    /// Ask iOS for notification authorization. Call when the user toggles
    /// any alert class on, never silently at app launch.
    static func requestAuthorization(_ completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                DispatchQueue.main.async { completion?(granted) }
            }
    }

    // MARK: - Reschedule

    /// Wipe & rebuild every `subv2-` notification. Cheap; call on every
    /// engine mutation. When the master toggle is off this still clears
    /// so previously-scheduled alerts don't keep firing.
    @MainActor
    static func rescheduleAll(records: [DetectedSubscription]) {
        let d = UserDefaults.standard
        let masterEnabled = d.object(forKey: masterEnabledKey) as? Bool ?? false

        clearAll {
            guard masterEnabled else { return }

            let renewalEnabled = d.object(forKey: renewalEnabledKey) as? Bool ?? true
            let trialEnabled = d.object(forKey: trialEnabledKey) as? Bool ?? true
            let priceEnabled = d.object(forKey: priceChangeEnabledKey) as? Bool ?? true
            let renewalLead = d.object(forKey: renewalLeadDaysKey) as? Int ?? defaultRenewalLeadDays
            let trialLead = d.object(forKey: trialLeadDaysKey) as? Int ?? defaultTrialLeadDays

            let active = records.filter { $0.status == .active || $0.status == .suspectedUnused }

            if renewalEnabled { scheduleRenewalAlerts(records: active, leadDays: renewalLead) }
            if trialEnabled { scheduleTrialAlerts(records: active, leadDays: trialLead) }
            if priceEnabled { schedulePriceChangeAlerts(records: active) }
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

    private static func scheduleRenewalAlerts(records: [DetectedSubscription], leadDays: Int) {
        let cal = Calendar.current
        for r in records {
            guard let renewal = r.nextRenewalDate else { continue }
            guard let alertDate = cal.date(byAdding: .day, value: -max(leadDays, 0), to: renewal) else { continue }
            let fire = morningOf(alertDate)
            guard fire > Date() else { continue }

            let body: String = {
                if leadDays == 0 {
                    return "Renews today — \(fmt(cents: r.expectedAmount)) will charge."
                }
                return "Renews in \(leadDays) day\(leadDays == 1 ? "" : "s") — \(fmt(cents: r.expectedAmount))."
            }()

            schedule(
                id: "\(identifierPrefix)renewal-\(r.id.uuidString)",
                title: r.merchantName.capitalized,
                body: body,
                category: "SUB_RENEWAL",
                fireAt: fire
            )
        }
    }

    private static func scheduleTrialAlerts(records: [DetectedSubscription], leadDays: Int) {
        let cal = Calendar.current
        for r in records where r.isTrial {
            guard let end = r.trialEndsAt else { continue }
            guard let alertDate = cal.date(byAdding: .day, value: -max(leadDays, 0), to: end) else { continue }
            let fire = morningOf(alertDate)
            guard fire > Date() else { continue }

            let body: String = {
                if leadDays == 0 {
                    return "Trial ends today — will start charging \(fmt(cents: r.expectedAmount))."
                }
                return "Trial ends in \(leadDays) day\(leadDays == 1 ? "" : "s") — will start charging \(fmt(cents: r.expectedAmount))."
            }()

            schedule(
                id: "\(identifierPrefix)trial-\(r.id.uuidString)",
                title: r.merchantName.capitalized,
                body: body,
                category: "SUB_TRIAL",
                fireAt: fire
            )
        }
    }

    private static func schedulePriceChangeAlerts(records: [DetectedSubscription]) {
        let cutoff = Calendar.current.date(byAdding: .hour, value: -priceChangeWindowHours, to: Date()) ?? Date()
        for r in records {
            guard let pct = r.priceChangePercent, abs(pct) >= priceChangeThresholdPct else { continue }
            // Only fire for records freshly touched (charge history just
            // updated). Without this guard a re-analyze would re-fire stale
            // alerts every launch.
            guard r.updatedAt >= cutoff else { continue }

            let dir = pct > 0 ? "raised" : "dropped"
            let body = "Price \(dir) by \(String(format: "%.1f", abs(pct)))% — now \(fmt(cents: r.lastAmount))."
            // Near-immediate fire (5s out so we don't race the system).
            let fire = Date().addingTimeInterval(5)

            schedule(
                id: "\(identifierPrefix)pricechange-\(r.id.uuidString)",
                title: r.merchantName.capitalized,
                body: body,
                category: "SUB_PRICE_CHANGE",
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

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireAt)
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
        let symbol = DS.Format.currencySymbol()
        return "\(symbol)\(DS.Format.currency(cents))"
    }
}
