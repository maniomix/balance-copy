import ActivityKit
import Foundation
import SwiftUI

/// Starts, updates, and ends the Budget Live Activity / Dynamic Island.
///
/// Lifecycle:
/// - App goes to background → `start(store:)` (creates the activity)
/// - App comes to foreground → `endAll()` (removes it; the running app shows
///   richer info anyway)
/// - Transaction added (including via Back Tap) → `refresh(store:)` updates
///   the existing activity if one is alive.
@MainActor
final class BudgetLiveActivityManager {
    static let shared = BudgetLiveActivityManager()
    private init() {}

    private var currentActivityID: String?

    // MARK: - Lifecycle

    func start(store: Store) {
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Don't double-start
        if currentActivityID != nil { return }

        // Anchor to the user's currently-focused month in the app. This
        // matches what they were just looking at, and avoids "0/0" when the
        // real-current-month happens to have no budget set yet.
        let month = activeMonth(for: store)
        let attrs = BudgetActivityAttributes(monthLabel: monthLabel(for: month))

        // Check whether to fire the one-shot over-budget alert for this
        // month. If so, force the initial page to Budget so the user sees it
        // first; otherwise honor the time-aware default.
        let alertActive = shouldFireOverBudgetAlert(for: store, month: month)
        if alertActive { markOverBudgetAlertFired(for: month) }

        let initialPage = alertActive ? 0 : defaultPageForCurrentTime()
        var state = makeState(from: store, preservingPage: initialPage)
        state.isOverBudgetAlert = alertActive

        do {
            let activity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: Date().addingTimeInterval(60 * 60 * 8)),
                pushType: nil
            )
            currentActivityID = activity.id
        } catch {
            // Surface in console; don't crash the app over a Live Activity failure.
            print("[BudgetLiveActivity] start failed: \(error)")
        }
    }

    func refresh(store: Store) {
        guard #available(iOS 16.2, *) else { return }
        Task {
            for activity in Activity<BudgetActivityAttributes>.activities {
                // Preserve whichever page the user is currently viewing AND
                // the alert state — alert is one-shot per activity lifetime,
                // recomputing it on every refresh would either re-fire it
                // every Back Tap save (bad) or wipe it (also bad).
                let oldState = activity.content.state
                var state = makeState(from: store, preservingPage: oldState.pageIndex)
                state.isOverBudgetAlert = oldState.isOverBudgetAlert
                await activity.update(
                    .init(state: state, staleDate: Date().addingTimeInterval(60 * 60 * 8))
                )
            }
        }
    }

    func endAll() {
        guard #available(iOS 16.2, *) else { return }
        Task {
            for activity in Activity<BudgetActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            currentActivityID = nil
        }
    }

    /// Synchronous-ish end for use during `applicationWillTerminate`. iOS
    /// gives apps ~5 seconds to clean up on graceful termination — we block
    /// the calling thread for up to 2s waiting for `Activity.end()` to
    /// complete. On a hard force-quit (where iOS gives 0 time), this won't
    /// help — the launch-time `endAll()` in `balanceApp.init()` is the only
    /// guaranteed cleanup path.
    func endAllBlocking(timeout: TimeInterval = 2.0) {
        guard #available(iOS 16.2, *) else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            for activity in Activity<BudgetActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        print("🔴 [BudgetLiveActivity] endAllBlocking finished (timeout=\(timeout)s)")
    }

    // MARK: - State builder

    private func makeState(from store: Store, preservingPage: Int? = nil) -> BudgetActivityAttributes.ContentState {
        // Show what the user is actually focused on in the app.
        let month = activeMonth(for: store)
        let now = Date()
        let total = store.budget(for: month)
        let spent = store.spent(for: month)
        let symbol = CurrencyOption.lookup(
            UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"
        ).symbol

        let cal = Calendar.current
        let monthExpenses = store.transactions.filter {
            $0.type == .expense && !$0.isTransfer &&
            cal.isDate($0.date, equalTo: month, toGranularity: .month)
        }

        // Last transaction (this month, most recent)
        let lastTxn = monthExpenses.sorted { $0.date > $1.date }.first
        var lastTitle: String? = nil
        var lastIcon: String? = nil
        if let t = lastTxn {
            let amt = String(format: "%.2f", Double(t.amount) / 100)
            let rawMerchant = t.note.isEmpty ? t.category.title : t.note
            let merchant = rawMerchant.count > 18
                ? String(rawMerchant.prefix(17)) + "…"
                : rawMerchant
            lastTitle = "\(merchant) · \(symbol)\(amt)"
            lastIcon = t.category.icon
        }

        // Anchor "today" and "week" to a reference date INSIDE the selected
        // month so browsing past months still shows real numbers (instead of
        // zeros from the real-current week).
        // - Selected month is the real current month → use today
        // - Selected month is past → use the most recent transaction in that
        //   month (or the last day of the month if none)
        // - Selected month is future → use the first day of the month
        let referenceDate: Date
        if cal.isDate(month, equalTo: now, toGranularity: .month) {
            referenceDate = now
        } else if month < now {
            referenceDate = monthExpenses.map(\.date).max()
                ?? endOfMonth(month, calendar: cal)
        } else {
            referenceDate = startOfMonth(month, calendar: cal)
        }

        // Page 1: "today" = the reference day
        let todayExpenses = store.transactions.filter {
            $0.type == .expense && !$0.isTransfer && cal.isDate($0.date, inSameDayAs: referenceDate)
        }
        let todaySpent = todayExpenses.reduce(0) { $0 + $1.amount }

        // Page 2: 7-day window ending at the reference date
        let weekEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: referenceDate)) ?? referenceDate
        let weekStart = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: referenceDate)) ?? referenceDate
        let weekSpent = store.transactions
            .filter { $0.type == .expense && !$0.isTransfer && $0.date >= weekStart && $0.date < weekEnd }
            .reduce(0) { $0 + $1.amount }

        // Page 3: top category this month
        let byCategory = Dictionary(grouping: monthExpenses, by: { $0.category })
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        let top = byCategory.max(by: { $0.value < $1.value })

        // Past-month label honesty: show the actual reference date, not "today".
        let isHistorical = !cal.isDate(month, equalTo: now, toGranularity: .month)
        let todayLabel: String
        if isHistorical {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            todayLabel = f.string(from: referenceDate)
        } else {
            todayLabel = "today"
        }

        // Page 4: most-relevant incomplete goal (highest progress %).
        let goal = featuredGoal()

        return .init(
            pageIndex: preservingPage ?? 0,
            totalCents: total,
            spentCents: spent,
            daysLeft: daysLeftInSelectedMonth(month: month, now: now),
            todaySpentCents: todaySpent,
            todayTxCount: todayExpenses.count,
            weekSpentCents: weekSpent,
            topCategoryTitle: top?.key.title,
            topCategoryIcon: top?.key.icon,
            topCategoryCents: top?.value ?? 0,
            currencySymbol: symbol,
            lastTransactionTitle: lastTitle,
            lastTransactionIcon: lastIcon,
            todayLabel: todayLabel,
            isHistorical: isHistorical,
            goalName: goal?.name,
            goalIcon: goal?.icon,
            goalCurrentCents: goal?.currentAmount,
            goalTargetCents: goal?.targetAmount
        )
    }

    /// Pick the goal we surface on page 4. We prefer the incomplete goal
    /// closest to completion (highest %), since that's the most actionable
    /// glance — "almost there" beats "just started" for motivation.
    private func featuredGoal() -> Goal? {
        let incomplete = GoalManager.shared.goals
            .filter { !$0.isCompleted && $0.targetAmount > 0 }
        return incomplete.max(by: {
            (Double($0.currentAmount) / Double($0.targetAmount)) <
            (Double($1.currentAmount) / Double($1.targetAmount))
        })
    }

    // MARK: - Over-budget alert (one-shot per month)

    private static let alertMonthKey = "dynamicIsland.lastOverBudgetAlertMonth"

    /// Returns true if we should fire the over-budget alert for this month
    /// — i.e. user is over budget AND we haven't already alerted this month.
    private func shouldFireOverBudgetAlert(for store: Store, month: Date) -> Bool {
        let total = store.budget(for: month)
        let spent = store.spent(for: month)
        guard total > 0, spent > total else { return false }

        let key = monthKey(month)
        let lastFiredKey = UserDefaults.standard.string(forKey: Self.alertMonthKey)
        return lastFiredKey != key
    }

    private func markOverBudgetAlertFired(for month: Date) {
        UserDefaults.standard.set(monthKey(month), forKey: Self.alertMonthKey)
    }

    private func monthKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }

    /// Default page selection based on the time of day:
    /// - 6-11 morning → Today (start-of-day spending review)
    /// - 18-23 evening → Week (end-of-day weekly recap)
    /// - everything else → Budget (always-useful default)
    private func defaultPageForCurrentTime() -> Int {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<11:  return 1   // Today
        case 18..<24: return 2   // Week
        default:      return 0   // Budget
        }
    }

    // MARK: - Helpers

    private func monthLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date)
    }

    /// Pick the month the activity should describe.
    /// - Prefer `store.selectedMonth` (what the user is browsing in-app).
    /// - That mirrors the rest of the app's mental model (totals, charts,
    ///   header all key off `selectedMonth`), so the Live Activity stays
    ///   consistent with what the user just saw before backgrounding.
    private func activeMonth(for store: Store) -> Date {
        store.selectedMonth
    }

    private func daysLeftInMonth(from date: Date) -> Int {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: date),
              let day = cal.dateComponents([.day], from: date).day else { return 0 }
        return max(0, range.count - day + 1)
    }

    private func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    private func endOfMonth(_ date: Date, calendar: Calendar) -> Date {
        let start = startOfMonth(date, calendar: calendar)
        return calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? date
    }

    /// Days left in `month`. If `month` is the real current month, count from
    /// today; if it's a past month, return 0; if it's a future month, return
    /// the full month length.
    private func daysLeftInSelectedMonth(month: Date, now: Date) -> Int {
        let cal = Calendar.current
        if cal.isDate(month, equalTo: now, toGranularity: .month) {
            return daysLeftInMonth(from: now)
        }
        if month < now {
            return 0
        }
        return cal.range(of: .day, in: .month, for: month)?.count ?? 0
    }
}
