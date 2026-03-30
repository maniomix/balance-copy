import Foundation
import UserNotifications

// MARK: - Notifications

final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterDelegate()

    // Show notifications even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Banner + sound makes the test + future reminders visible while the app is open.
        return [.banner, .sound]
    }
}

enum Notifications {
    // Identifiers
    private static let dailyID = "balance.notif.daily"
    private static let weeklyID = "balance.notif.weekly"
    private static let paydayID = "balance.notif.payday"

    // Smart (one-off) identifiers are built from these prefixes
    private static let t70Prefix = "balance.notif.threshold70."
    private static let t80Prefix = "balance.notif.threshold80."
    private static let overBudgetPrefix = "balance.notif.overbudget."
    private static let overspendPrefix = "balance.notif.overspend."
    private static let categoryPrefix = "balance.notif.categorycap."
    private static let billDuePrefix = "balance.notif.billdue."

    // Persist “already notified” markers
    private static func monthKey(_ date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        return String(format: "%04d-%02d", y, m)
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    static func syncAll(store: Store) async {
        // If not authorized, do nothing.
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }

        scheduleDailyReminder()
        scheduleWeeklyCheckIn()
        schedulePaydayReminder()

        await evaluateSmartRules(store: store)
    }

    // 1) Daily reminder (simple)
    private static func scheduleDailyReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyID])

        var dc = DateComponents()
        dc.hour = 20
        dc.minute = 30

        let content = UNMutableNotificationContent()
        content.title = "Balance"
        content.body = "Quick check: did you log today’s expenses?"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        let req = UNNotificationRequest(identifier: dailyID, content: content, trigger: trigger)
        center.add(req)
    }

    // 2) Weekly check-in (simple)
    private static func scheduleWeeklyCheckIn() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyID])

        // Sunday 18:00 (can be changed later in Settings)
        var dc = DateComponents()
        dc.weekday = 1 // Sunday
        dc.hour = 18
        dc.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "Balance — Weekly check"
        content.body = "Take 60 seconds to review this week’s spending and adjust next week."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        let req = UNNotificationRequest(identifier: weeklyID, content: content, trigger: trigger)
        center.add(req)
    }

    // 7) Payday reminder (simple: 1st of month at 09:00)
    private static func schedulePaydayReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [paydayID])

        var dc = DateComponents()
        dc.day = 1
        dc.hour = 9
        dc.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "Balance — New month"
        content.body = "New month started. Set your budget and category caps for better control."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        let req = UNNotificationRequest(identifier: paydayID, content: content, trigger: trigger)
        center.add(req)
    }

    // Smart rules (evaluated while user uses the app)
    static func evaluateSmartRules(store: Store) async {
        guard store.budgetTotal > 0 else { return }

        let mKey = monthKey(store.selectedMonth)
        let summary = Analytics.monthSummary(store: store)

        // 3) Monthly budget notifications (edge-triggered)
        // If user goes over budget, notify once. If they later go back under (e.g., edit/delete), reset so crossing again notifies again.
        let overKey = overBudgetPrefix + mKey
        let isOverNow = summary.spentRatio >= 1.0

        if !isOverNow {
            // Reset once we are back under budget.
            UserDefaults.standard.removeObject(forKey: overKey)
        }

        let alreadyOverBudgetNotified = UserDefaults.standard.bool(forKey: overKey)
        if isOverNow {
            if !alreadyOverBudgetNotified {
                // Mark and send immediately
                UserDefaults.standard.set(true, forKey: overKey)
                await scheduleImmediate(
                    id: overKey,
                    title: "Over budget",
                    body: "You’re over your monthly budget. Review spending and pause non‑essentials until month end."
                )
            }
        } else {
            // Repeatable 70/80 alerts while not over-budget.
            // 70/80 alerts (edge-triggered, once per month).
            // We keep a simple state so entering Insights or re-evaluations don't spam.
            let thresholdStateKey = "balance.notif.threshold.state." + mKey
            let lastState = UserDefaults.standard.string(forKey: thresholdStateKey) ?? "none" // none | t70 | t80

            let newState: String
            if summary.spentRatio >= 0.80 {
                newState = "t80"
            } else if summary.spentRatio >= 0.70 {
                newState = "t70"
            } else {
                newState = "none"
            }

            if newState == "none" {
                // Reset once we are back under 70% so future crossings can notify again.
                if lastState != "none" {
                    UserDefaults.standard.removeObject(forKey: thresholdStateKey)
                }
            } else {
                // Only notify on upward transitions (none -> t70, t70 -> t80, none -> t80).
                let shouldNotify: Bool
                if lastState == "none" {
                    shouldNotify = true
                } else if lastState == "t70" && newState == "t80" {
                    shouldNotify = true
                } else {
                    shouldNotify = false
                }

                if shouldNotify {
                    UserDefaults.standard.set(newState, forKey: thresholdStateKey)

                    if newState == "t70" {
                        let id = t70Prefix + mKey
                        await scheduleImmediate(
                            id: id,
                            title: "Budget alert",
                            body: "You’ve used 70% of your monthly budget. Consider trimming discretionary spending this week."
                        )
                    } else {
                        let id = t80Prefix + mKey
                        await scheduleImmediate(
                            id: id,
                            title: "Budget warning",
                            body: "You’ve used 80% of your monthly budget. Tighten spending to avoid exceeding your limit."
                        )
                    }
                }
            }
        }

        // 4) Overspend today vs daily cap — notify every time rule is evaluated
        

        // 5) Category cap near/over — edge-triggered per category per month
        let monthTx = Analytics.monthTransactions(store: store)
        for c in store.allCategories {
            let cap = store.categoryBudget(for: c)
            guard cap > 0 else { continue }

            let spent = monthTx.filter { $0.category == c }.reduce(0) { $0 + $1.amount }
            let ratio = Double(spent) / Double(max(1, cap))

            // Track last state so we only notify on transitions.
            // States: none (<0.90), near (>=0.90 and <1.0), over (>=1.0)
            let stateKey = categoryPrefix + "state." + mKey + "." + c.storageKey
            let lastState = (UserDefaults.standard.string(forKey: stateKey) ?? "none")

            let newState: String
            if ratio >= 1.0 {
                newState = "over"
            } else if ratio >= 0.90 {
                newState = "near"
            } else {
                newState = "none"
            }

            // Reset when back below threshold so future crossings notify again.
            if newState == "none" {
                if lastState != "none" {
                    UserDefaults.standard.removeObject(forKey: stateKey)
                }
                continue
            }

            // Transition: none -> near, near -> over, none -> over
            if newState != lastState {
                UserDefaults.standard.set(newState, forKey: stateKey)

                if newState == "over" {
                    let over = max(0, spent - cap)
                    let overPct = cap > 0 ? Double(over) / Double(cap) : 0
                    let id = categoryPrefix + UUID().uuidString
                    await scheduleImmediate(
                        id: id,
                        title: "Category cap exceeded",
                        body: "\(c.title): \(DS.Format.percent(overPct)) over cap (\(DS.Format.money(over)) above \(DS.Format.money(cap)))"
                    )
                } else {
                    let id = categoryPrefix + UUID().uuidString
                    await scheduleImmediate(
                        id: id,
                        title: "Approaching category cap",
                        body: "\(c.title): used \(DS.Format.percent(min(1.5, ratio))) of your \(DS.Format.money(cap)) cap."
                    )
                }
            }
        }

        // 6) Bill due date reminders — notify when a recurring transaction is due within 3 days
        let now = Date()
        let calendar = Calendar.current
        let threeDaysFromNow = calendar.date(byAdding: .day, value: 3, to: now)!

        for rt in store.recurringTransactions where rt.isActive {
            guard let nextDue = rt.nextOccurrence(from: now) else { continue }
            guard nextDue <= threeDaysFromNow else { continue }

            // Edge-triggered: one notification per recurring transaction per due date
            let dueDateString = ISO8601DateFormatter().string(from: nextDue)
            let markerKey = billDuePrefix + rt.id.uuidString + "." + dueDateString
            let ud = UserDefaults.standard
            guard !ud.bool(forKey: markerKey) else { continue }
            ud.set(true, forKey: markerKey)

            let daysUntil = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: nextDue)).day ?? 0
            let timeDesc: String
            if daysUntil <= 0 {
                timeDesc = "today"
            } else if daysUntil == 1 {
                timeDesc = "tomorrow"
            } else {
                timeDesc = "in \(daysUntil) days"
            }

            await scheduleImmediate(
                id: markerKey,
                title: "Bill due \(timeDesc)",
                body: "\(rt.name): \(DS.Format.money(rt.amount)) due \(timeDesc)."
            )
        }
    }


    // Send helpers
    private static func sendOncePerMonth(id: String, title: String, body: String) async {
        // Marker is stored in UserDefaults so we don’t spam.
        let ud = UserDefaults.standard
        if ud.bool(forKey: id) { return }
        ud.set(true, forKey: id)
        await scheduleImmediate(id: id, title: title, body: body)
    }

    private static func sendOnce(id: String, title: String, body: String) async {
        let ud = UserDefaults.standard
        if ud.bool(forKey: id) { return }
        ud.set(true, forKey: id)
        await scheduleImmediate(id: id, title: title, body: body)
    }

    private static func scheduleImmediate(id: String, title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Deliver immediately (no trigger). This removes the noticeable delay.
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        do {
            try await center.add(req)
        } catch {
            // ignore
        }
    }
}
