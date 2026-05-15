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

    /// Idempotent: starts an activity only if none is currently alive AND the
    /// user has a budget set for their selected month. Safe to call on every
    /// scene transition.
    func ensureStarted(store: Store) {
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if !Activity<BudgetActivityAttributes>.activities.isEmpty { return }
        guard store.budget(for: store.selectedMonth) > 0 else { return }
        start(store: store)
    }

    /// End ALL in-flight activities at launch. User-requested behavior:
    /// "after fully closing the app dynamic island also should be killed".
    /// willTerminate handles graceful quits; this is the safety net for
    /// hard force-quits where willTerminate didn't fire. As a side effect
    /// this also catches schema version mismatches automatically.
    func cleanupOrphans() {
        guard #available(iOS 16.2, *) else { return }
        Task { @MainActor in
            for activity in Activity<BudgetActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            currentActivityID = nil
        }
    }

    /// Synchronous-ish end for `applicationWillTerminate`. Blocks the main
    /// thread up to `timeout` seconds waiting for `Activity.end()` to
    /// complete. iOS gives apps ~5s on graceful termination; we use 2s of
    /// that budget. Hard force-quits give 0s — `cleanupOrphans()` at launch
    /// is the fallback for that case.
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
    }

    func start(store: Store) {
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Don't double-start
        if currentActivityID != nil { return }
        if !Activity<BudgetActivityAttributes>.activities.isEmpty { return }

        // Anchor to the user's currently-focused month in the app. This
        // matches what they were just looking at, and avoids "0/0" when the
        // real-current-month happens to have no budget set yet.
        let month = activeMonth(for: store)
        let attrs = BudgetActivityAttributes(monthLabel: monthLabel(for: month))
        let initialPage = defaultPageForCurrentTime()
        let state = makeState(from: store, preservingPage: initialPage)

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

    /// Refresh stats on the in-flight activity. `resetToFirstPage` controls
    /// page-index behavior: true (called from `.active`) snaps back to
    /// Budget; false preserves whatever page the user was viewing (used by
    /// Back-Tap saves and other mid-session updates).
    func refresh(store: Store, resetToFirstPage: Bool = false) {
        guard #available(iOS 16.2, *) else { return }
        Task {
            for activity in Activity<BudgetActivityAttributes>.activities {
                let oldState = activity.content.state
                let preserve = resetToFirstPage ? 0 : oldState.pageIndex
                let state = makeState(from: store, preservingPage: preserve)
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

    // MARK: - State builder

    private func makeState(from store: Store, preservingPage: Int? = nil) -> BudgetActivityAttributes.ContentState {
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

        // Page 1: today (single-pass over all expenses, 24 hourly buckets)
        var todaySparkline = [Int](repeating: 0, count: 24)
        var todaySpent = 0
        var todayTxCount = 0
        for t in store.transactions where t.type == .expense && !t.isTransfer && cal.isDateInToday(t.date) {
            let hour = max(0, min(23, cal.component(.hour, from: t.date)))
            todaySparkline[hour] += t.amount
            todaySpent += t.amount
            todayTxCount += 1
        }

        // Page 2: last 7 days (today + 6 prior). weekDailyBuckets[6] = today.
        let todayStart = cal.startOfDay(for: now)
        var weekDailyBuckets = [Int](repeating: 0, count: 7)
        var weekSpent = 0
        let weekStart = cal.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        for t in store.transactions where t.type == .expense && !t.isTransfer && t.date >= weekStart {
            guard let dayOffset = cal.dateComponents([.day], from: weekStart, to: cal.startOfDay(for: t.date)).day,
                  (0..<7).contains(dayOffset) else { continue }
            weekDailyBuckets[dayOffset] += t.amount
            weekSpent += t.amount
        }

        // Page 3: top category this month + its share of total month spend
        let byCategory = Dictionary(grouping: monthExpenses, by: { $0.category })
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        let top = byCategory.max(by: { $0.value < $1.value })
        let topShare: Double? = (top != nil && spent > 0)
            ? Double(top!.value) / Double(spent)
            : nil

        // Today bottom-row context: most recent expense this month (truncated)
        var lastTitle: String? = nil
        var lastIcon: String? = nil
        if let t = monthExpenses.max(by: { $0.date < $1.date }) {
            let amt = String(format: "%.2f", Double(t.amount) / 100)
            let rawMerchant = t.note.isEmpty ? t.category.title : t.note
            let merchant = rawMerchant.count > 18
                ? String(rawMerchant.prefix(17)) + "…"
                : rawMerchant
            lastTitle = "\(merchant) · \(symbol)\(amt)"
            lastIcon = t.category.icon
        }

        return .init(
            pageIndex: preservingPage ?? 0,
            totalCents: total,
            spentCents: spent,
            daysLeft: daysLeftInSelectedMonth(month: month, now: now),
            todaySpentCents: todaySpent,
            todayTxCount: todayTxCount,
            todaySparkline: todaySparkline,
            weekSpentCents: weekSpent,
            weekDailyBuckets: weekDailyBuckets,
            topCategoryTitle: top?.key.title,
            topCategoryIcon: top?.key.icon,
            topCategoryCents: top?.value ?? 0,
            topCategoryShareOfMonth: topShare,
            currencySymbol: symbol,
            lastTransactionTitle: lastTitle,
            lastTransactionIcon: lastIcon
        )
    }

    /// Initial page on every fresh activity start. User-requested: always
    /// open on Budget — "for every new app open the first default page has
    /// to be the first page user see."
    private func defaultPageForCurrentTime() -> Int { 0 }

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
