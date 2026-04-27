import Foundation
@preconcurrency import UserNotifications

// ============================================================
// MARK: - Forecast Notification Scheduler (Phase 4a — iOS port)
// ============================================================
//
// Local notifications for forecast-derived watch points. Wipe-and-
// rebuild pattern (same as AISubscription/Recurring schedulers).
//
// Three alert classes, fired the morning before the relevant date:
//   1. Overdraft — expected balance crosses zero inside the horizon.
//   2. Tight window — P10 band dips below zero (expected stays positive).
//   3. Low-balance watch point — lowest expected balance drops below
//      `lowBalanceThresholdKey` (default $500).
//
// Identifier scheme: `forecast-<kind>-<isoDate>`.
//
// Ported from macOS. Adapted: reads inputs from `Store` (not SwiftData
// context), amounts in Int cents throughout, Account balance converted
// from Double → cents at the boundary.
// ============================================================

enum ForecastNotificationScheduler {

    // MARK: - UserDefaults keys

    static let masterEnabledKey       = "forecastAlertsEnabled"
    /// Threshold stored in cents. UI presents as dollars.
    static let lowBalanceThresholdKey = "forecastAlertsLowBalanceThreshold"

    // MARK: - Constants

    private static let identifierPrefix = "forecast-"
    private static let horizonDays = 60
    private static let alertHour = 9
    private static let defaultLowBalanceCents = 50_000  // $500

    // MARK: - Public API

    /// Request authorization. Only call when the user toggles alerts on.
    static func requestAuthorization(_ completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    /// Rebuild all forecast-prefixed notifications. Caller passes the
    /// current Store + the Accounts snapshot (iOS Accounts aren't on Store
    /// — they live in `AccountManager` / Supabase state).
    @MainActor
    static func rescheduleAll(store: Store, accounts: [Account]) {
        let defaults = UserDefaults.standard
        let masterEnabled = defaults.object(forKey: masterEnabledKey) as? Bool ?? false
        let snapshot = Snapshot(store: store, accounts: accounts)
        clearAll {
            guard masterEnabled else { return }
            let thresholdCents = defaults.object(forKey: lowBalanceThresholdKey) as? Int ?? defaultLowBalanceCents
            Task { @MainActor in
                scheduleFromHorizon(snapshot: snapshot, lowBalanceThresholdCents: thresholdCents)
            }
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

    // MARK: - Inputs snapshot

    /// Captured on the main actor before the async clear so the scheduling
    /// closure doesn't touch (possibly mutated) live state mid-hop.
    private struct Snapshot {
        let aiSubscriptions: [AISubscription]
        let recurring: [RecurringTransaction]
        let goals: [Goal]
        let history: [Transaction]
        let startingBalanceCents: Int

        init(store: Store, accounts: [Account]) {
            self.aiSubscriptions = store.aiSubscriptions
            self.recurring = store.recurringTransactions
            self.goals = []  // iOS goals live outside Store; pass [] unless wired
            let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
            self.history = store.transactions.filter { $0.date >= cutoff }
            let eligibleBalance = accounts
                .filter { !$0.isArchived }
                .reduce(0.0) { $0 + $1.currentBalance }
            self.startingBalanceCents = Int((eligibleBalance * 100).rounded())
        }
    }

    // MARK: - Scheduling

    private static func scheduleFromHorizon(snapshot: Snapshot, lowBalanceThresholdCents: Int) {
        let horizon = CashflowForecastEngine.build(
            CashflowForecastEngine.Inputs(
                startingBalance: snapshot.startingBalanceCents,
                aiSubscriptions: snapshot.aiSubscriptions,
                recurring: snapshot.recurring,
                goals: snapshot.goals,
                history: snapshot.history
            ),
            horizonDays: horizonDays
        )

        let summary = horizon.summary

        if let neg = summary.firstExpectedNegativeDate {
            schedule(
                id: idFor(kind: "overdraft", date: neg),
                title: "Balance will hit $0",
                body: "Projected to go negative on \(shortDate(neg)). Take a look at upcoming obligations.",
                category: "FORECAST_OVERDRAFT",
                fireAt: morningOf(neg, daysBefore: 1)
            )
        } else if let risk = summary.firstAtRiskDate {
            schedule(
                id: idFor(kind: "tight", date: risk),
                title: "Tight week ahead",
                body: "Budget gets snug around \(shortDate(risk)). Review your forecast.",
                category: "FORECAST_TIGHT",
                fireAt: morningOf(risk, daysBefore: 2)
            )
        }

        if summary.lowestExpectedBalance < lowBalanceThresholdCents
            && summary.lowestExpectedBalanceDate > Date() {
            schedule(
                id: idFor(kind: "lowbalance", date: summary.lowestExpectedBalanceDate),
                title: "Low-balance watch point",
                body: "Lowest projected balance \(format(cents: summary.lowestExpectedBalance)) on \(shortDate(summary.lowestExpectedBalanceDate)).",
                category: "FORECAST_LOW_BALANCE",
                fireAt: morningOf(summary.lowestExpectedBalanceDate, daysBefore: 3)
            )
        }
    }

    // MARK: - Helpers

    private static func schedule(id: String, title: String, body: String, category: String, fireAt: Date) {
        guard fireAt > Date() else { return }
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

    private static func idFor(kind: String, date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return "\(identifierPrefix)\(kind)-\(f.string(from: date))"
    }

    private static func morningOf(_ date: Date, daysBefore: Int) -> Date {
        let cal = Calendar.current
        let target = cal.date(byAdding: .day, value: -daysBefore, to: date) ?? date
        var comps = cal.dateComponents([.year, .month, .day], from: target)
        comps.hour = alertHour
        comps.minute = 0
        return cal.date(from: comps) ?? target
    }

    private static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private static func format(cents: Int) -> String {
        let dollars = Double(cents) / 100
        if abs(dollars) >= 1000 {
            return String(format: "$%.1fk", dollars / 1000)
        }
        return String(format: "$%.0f", dollars)
    }
}
