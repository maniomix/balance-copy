import ActivityKit
import Foundation

/// Live Activity attributes for the monthly-budget Dynamic Island.
///
/// IMPORTANT: this file MUST be a member of BOTH the main `balance` target
/// AND the widget extension target. The explicit `BudgetActivityAttributes.swift`
/// exception entry in `project.pbxproj` carries the dual membership.
struct BudgetActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // MARK: - Page navigation

        /// Which information page is shown in the expanded view (0...3).
        /// 0 Budget, 1 Today, 2 This Week, 3 Top Category.
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
        /// 24 hourly buckets of today's expenses (cents). Index = hour-of-day.
        /// Optional so older Codable payloads still decode after the schema
        /// bump from v1 (no sparkline) to v2.
        var todaySparkline: [Int]?

        // MARK: - Page 2: This week

        /// Total spent in the last 7 days (cents).
        var weekSpentCents: Int
        /// 7 daily buckets (cents) — index 0 = 6 days ago, index 6 = today.
        var weekDailyBuckets: [Int]?

        // MARK: - Page 3: Top category

        /// Highest-spend category this month.
        var topCategoryTitle: String?
        var topCategoryIcon: String?
        var topCategoryCents: Int
        /// Pre-computed share of total month spending (0...1). Avoids divide
        /// math in the widget render path.
        var topCategoryShareOfMonth: Double?

        // MARK: - Shared chrome

        /// Currency symbol shown in all amounts ("€", "$", ...).
        var currencySymbol: String

        /// Most recent expense (this month) — used in the Today page bottom
        /// row for context. Optional so older Codable payloads decode.
        var lastTransactionTitle: String?
        var lastTransactionIcon: String?

        // MARK: - Derived

        var pageCount: Int { 4 }
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

    /// Schema version. v1 = goal page + alert. v2 = sparkline build.
    /// v3 = hero+gauge+icon-row redesign. v4 = enlarged hero + 90pt page box.
    /// v5 = compact "K/M" formatter. v6 = heavy middle padding (reverted).
    /// v7 = uniform 10pt inset on header AND body so the whole DI content
    /// reads as one padded block.
    /// cleanupOrphans ends any activity below the current version.
    var schemaVersion: Int = 7
}
