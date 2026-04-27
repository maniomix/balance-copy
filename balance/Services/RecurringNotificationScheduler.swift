import Foundation
@preconcurrency import UserNotifications

// ============================================================
// MARK: - Recurring Notification Scheduler (Phase 3c — iOS port)
// ============================================================
//
// Local notification scheduling for recurring transactions. Mirrors
// `SubscriptionNotificationScheduler` — wipes and rebuilds the full
// plan on every call. Cheap, and a clean rebuild guarantees we don't
// accumulate stale alerts when a template is paused or edited.
//
// Identifier scheme: `rec-<kind>-<templateID>-<extra>` so we target
// removals without clearing unrelated notifications.
//
// Ported from macOS Centmond, adapted to iOS:
//   - macOS pulls `RecurringTransaction` from SwiftData; iOS reads
//     `store.recurringTransactions`
//   - iOS `RecurringTransaction.nextOccurrence(from:)` already walks
//     forward — no separate frequency helper needed
//   - All iOS recurring templates are expense-only (no `isIncome` flag)
//   - Amounts are Int cents; threshold stored and compared in cents
// ============================================================

enum RecurringNotificationScheduler {

    // MARK: - UserDefaults keys

    static let masterEnabledKey        = "recurringNotificationsEnabled"
    static let chargeAlertThresholdKey = "recurringNotificationsThreshold"

    // MARK: - Constants

    private static let identifierPrefix      = "rec-"
    private static let scheduleHorizonDays   = 60
    private static let alertHour             = 9
    /// Default threshold in cents ($100). Off-by-default for small bills.
    private static let defaultThresholdCents = 10_000

    // MARK: - Public API

    /// Request notification authorization. Call only when the user enables
    /// notifications, never silently at app launch.
    static func requestAuthorization(_ completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    /// Wipe & rebuild every recurring-prefixed notification. When the master
    /// toggle is off we still clear so previously-scheduled alerts stop.
    @MainActor
    static func rescheduleAll(store: Store) {
        let defaults = UserDefaults.standard
        let masterEnabled = defaults.object(forKey: masterEnabledKey) as? Bool ?? false
        let templates = store.recurringTransactions.filter { $0.isActive }
        clearAll {
            guard masterEnabled else { return }
            let thresholdCents = defaults.object(forKey: chargeAlertThresholdKey) as? Int ?? defaultThresholdCents
            Self.scheduleUpcoming(templates: templates, thresholdCents: thresholdCents)
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

    private static func scheduleUpcoming(templates: [RecurringTransaction], thresholdCents: Int) {
        let cal = Calendar.current
        guard let horizon = cal.date(byAdding: .day, value: scheduleHorizonDays, to: Date()) else { return }
        let cap = scheduleHorizonDays * 2

        for template in templates {
            guard template.amount >= thresholdCents else { continue }

            // Walk forward through projected occurrences and schedule one
            // alert per occurrence within the horizon.
            var cursor: Date? = template.nextOccurrence(from: Date())
            var iter = 0
            while let next = cursor, next <= horizon, iter < cap {
                let dayBefore = cal.date(byAdding: .day, value: -1, to: next) ?? next
                let fireAt = morningOf(dayBefore)
                if fireAt > Date() {
                    let stamp = String(Int(next.timeIntervalSince1970))
                    schedule(
                        id: "\(identifierPrefix)charge-\(template.id.uuidString)-\(stamp)",
                        title: template.name,
                        body: "\(fmt(cents: template.amount)) is due tomorrow.",
                        category: "REC_CHARGE",
                        fireAt: fireAt
                    )
                }
                // Simulate advance by constructing a template clone whose
                // `lastProcessedDate` is the current occurrence — that's
                // exactly what `nextOccurrence(from:)` uses internally.
                var stepped = template
                stepped.lastProcessedDate = next
                cursor = stepped.nextOccurrence(from: next)
                iter += 1
            }
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
