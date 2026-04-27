import ActivityKit
import Foundation

/// Live Activity attributes for the monthly-budget Dynamic Island.
///
/// IMPORTANT: this file MUST be a member of BOTH the main `balance` target
/// AND the widget extension target. Select the file in Xcode → File Inspector
/// → Target Membership → check both boxes.
struct BudgetActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // MARK: - Page navigation

        /// Which information page is shown in the expanded view (0...3).
        /// Cycled by `CycleBudgetPageIntent`.
        var pageIndex: Int

        // MARK: - Page 0: Budget

        /// Total budget for the month, in cents.
        var totalCents: Int
        /// Spent so far this month, in cents (expenses only).
        var spentCents: Int
        /// Days remaining in the current month (inclusive of today).
        var daysLeft: Int

        // MARK: - Page 1: Today

        /// Total spent today (cents).
        var todaySpentCents: Int
        /// Number of transactions logged today.
        var todayTxCount: Int

        // MARK: - Page 2: This week

        /// Total spent in the last 7 days (cents).
        var weekSpentCents: Int

        // MARK: - Page 3: Top category

        /// Highest-spend category this month.
        var topCategoryTitle: String?
        var topCategoryIcon: String?
        var topCategoryCents: Int

        // MARK: - Shared chrome

        /// Currency symbol shown in all amounts ("€", "$", ...).
        var currencySymbol: String
        /// Most recent transaction summary, e.g. "Lidl · €15".
        var lastTransactionTitle: String?
        /// SF Symbol for the most recent transaction's category.
        var lastTransactionIcon: String?

        /// Label for the "Today" page hero. Defaults to "today" when
        /// selectedMonth is the current real month; otherwise the actual day
        /// inside that month, e.g. "Feb 28". Optional so older Codable
        /// payloads from in-flight activities still decode.
        var todayLabel: String?

        /// True when the activity is showing data from a past or future month
        /// (i.e. `selectedMonth != currentMonth`). Lets the UI reframe labels
        /// honestly — e.g. "7 DAYS" → "last 7 of Feb".
        var isHistorical: Bool?

        // MARK: - Page 4: Goal (only shown when user has an incomplete goal)

        /// Name of the most-relevant incomplete goal (highest progress %).
        /// nil when the user has no incomplete goals — page 4 hides itself.
        var goalName: String?
        var goalIcon: String?
        var goalCurrentCents: Int?
        var goalTargetCents: Int?

        /// Effective number of pages: 4 normally, 5 when a goal is present.
        var pageCount: Int { (goalTargetCents ?? 0) > 0 ? 5 : 4 }

        // MARK: - Alert state

        /// Set on first activity start in a month where the user has crossed
        /// 100% of their budget. Persists for the lifetime of that activity
        /// (so the badge stays visible until the user reopens the app), but
        /// won't re-fire until the next month. Optional for back-compat.
        var isOverBudgetAlert: Bool?

        var goalPercent: Double {
            guard let target = goalTargetCents, target > 0,
                  let current = goalCurrentCents else { return 0 }
            return min(1.0, Double(current) / Double(target))
        }

        // MARK: - Derived

        var remainingCents: Int { max(0, totalCents - spentCents) }

        var percentSpent: Double {
            guard totalCents > 0 else { return 0 }
            return min(1.0, Double(spentCents) / Double(totalCents))
        }

        var isOverBudget: Bool { totalCents > 0 && spentCents > totalCents }

        var dailyAverageThisWeekCents: Int { weekSpentCents / 7 }
    }

    /// Month label, e.g. "April 2026". Static for the activity's lifetime.
    var monthLabel: String

    /// Maximum possible page count — used by intents that need a hard cap.
    /// The *effective* count for any given activity comes from
    /// `ContentState.pageCount`.
    static let maxPageCount: Int = 5
}
