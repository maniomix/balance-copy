import Foundation
import SwiftUI

// MARK: - Dashboard Trend Model

/// Derivations used by the dashboard Daily Trend card. Sourced from
/// `ChartsAnalytics.shared.snapshot(store:, range: .month)` so the dashboard
/// chart shares the same data pipeline as the Analytics rebuild — and adds
/// a handful of month-specific derivatives (cumulative spent, ideal pace,
/// previous-month alignment, projection).
struct DashboardTrendModel {

    let store: Store
    let selectedMonth: Date

    // MARK: Inputs

    private var snapshot: ChartsAnalytics.Snapshot {
        ChartsAnalytics.shared.snapshot(store: store, range: .month, now: selectedMonth)
    }

    private var calendar: Calendar { Calendar.current }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
    }

    private var daysInMonth: Int {
        (calendar.range(of: .day, in: .month, for: selectedMonth) ?? 1..<31).count
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(Date(), equalTo: selectedMonth, toGranularity: .month)
    }

    private var dayOfMonthToday: Int {
        calendar.component(.day, from: Date())
    }

    /// The daily buckets for the selected month (1 bucket per day).
    var dailyBuckets: [ChartBucket] { snapshot.buckets }

    var dailyBucketsPrev: [ChartBucket] { snapshot.previousBuckets }

    // MARK: Daily series

    struct DayPoint: Identifiable, Hashable {
        let id: Int              // day of month (1-based)
        let day: Int
        let spent: Int           // cents
        let cumulative: Int      // cents
        let isAnomaly: Bool
    }

    var dailyPoints: [DayPoint] {
        var running = 0
        let amounts = dailyBuckets.map { Double($0.spent) }
        let mean = amounts.isEmpty ? 0 : amounts.reduce(0, +) / Double(amounts.count)
        let variance = amounts.isEmpty ? 0 : amounts.map { pow($0 - mean, 2) }.reduce(0, +) / Double(amounts.count)
        let threshold = mean + sqrt(variance) * 2

        return dailyBuckets.enumerated().map { idx, b in
            running += b.spent
            let dayNum = idx + 1
            return DayPoint(
                id: dayNum,
                day: dayNum,
                spent: b.spent,
                cumulative: running,
                isAnomaly: Double(b.spent) > threshold && b.spent > 0
            )
        }
    }

    /// Previous month's cumulative series, aligned to current month day index.
    var prevMonthCumulative: [DayPoint] {
        guard !dailyBucketsPrev.isEmpty else { return [] }
        var running = 0
        return dailyBucketsPrev.enumerated().prefix(daysInMonth).map { idx, b in
            running += b.spent
            let dayNum = idx + 1
            return DayPoint(id: dayNum, day: dayNum, spent: b.spent, cumulative: running, isAnomaly: false)
        }
    }

    // MARK: Budget pace

    /// Ideal straight-line burn from day 1 (0) → last day (budget) if budget set.
    struct PacePoint: Identifiable, Hashable {
        let id: Int
        let day: Int
        let target: Int
    }

    var idealPace: [PacePoint] {
        let budget = store.budget(for: monthStart)
        guard budget > 0 else { return [] }
        return (1...daysInMonth).map { day in
            let target = Int((Double(budget) * Double(day) / Double(daysInMonth)).rounded())
            return PacePoint(id: day, day: day, target: target)
        }
    }

    // MARK: Headline KPIs

    struct Headline {
        let spent: Int
        let projected: Int
        let budget: Int
        let paceDelta: Int        // cumulative spent − ideal at today
        let paceRatio: Double     // paceDelta / budgetToDate
        let daysRemaining: Int
    }

    var headline: Headline {
        let budget = store.budget(for: monthStart)
        let spent = dailyPoints.last?.cumulative ?? 0

        let today = isCurrentMonth ? min(dayOfMonthToday, daysInMonth) : daysInMonth
        let cumulativeToday = dailyPoints.first(where: { $0.day == today })?.cumulative ?? spent

        let targetToday = budget > 0
            ? Int((Double(budget) * Double(today) / Double(daysInMonth)).rounded())
            : 0
        let paceDelta = cumulativeToday - targetToday
        let paceRatio = targetToday > 0 ? Double(paceDelta) / Double(targetToday) : 0

        let proj = Analytics.projectedEndOfMonth(store: store).projectedTotal
        let remaining = max(0, daysInMonth - today)

        return Headline(
            spent: spent,
            projected: proj,
            budget: budget,
            paceDelta: paceDelta,
            paceRatio: paceRatio,
            daysRemaining: remaining
        )
    }

    // MARK: Anomaly lookup

    func point(forDay day: Int) -> DayPoint? {
        dailyPoints.first { $0.day == day }
    }
}
