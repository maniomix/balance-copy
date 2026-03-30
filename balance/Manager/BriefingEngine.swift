import Foundation

// ============================================================
// MARK: - Briefing Engine
// ============================================================
//
// Synthesizes all 4 engine outputs (Forecast, Review,
// Subscription, Household) plus Analytics and Goals into
// a single MonthlyBriefing.
//
// Template-driven text — no AI/LLM. Conditional sections
// based on data availability and relevance.
//
// Usage:
//   let briefing = BriefingEngine.generate(
//       store: store,
//       forecast: ForecastEngine.shared.forecast,
//       review: ReviewEngine.shared.dashboardSnapshot,
//       subscription: SubscriptionEngine.shared.dashboardSnapshot,
//       household: HouseholdManager.shared.dashboardSnapshot(...),
//       goals: GoalManager.shared
//   )
//
// ============================================================

@MainActor
enum BriefingEngine {

    static func generate(
        store: Store,
        forecast: ForecastResult?,
        reviewSnapshot: ReviewSnapshot?,
        subscriptionSnapshot: SubscriptionSnapshot?,
        householdSnapshot: HouseholdSnapshot?,
        goalManager: GoalManager?
    ) -> MonthlyBriefing {
        let cal = Calendar.current
        let month = store.selectedMonth
        let monthKey = monthKeyString(from: month)

        // MARK: - Overview

        let summary = Analytics.monthSummary(store: store)
        let income = store.income(for: month)
        let vsAverage = computeVsAverage(store: store, currentSpent: summary.totalSpent)

        let spentFormatted = DS.Format.money(summary.totalSpent)
        let monthName = monthDisplayName(from: month)

        var headline = "You spent \(spentFormatted) in \(monthName)"
        var subheadline: String
        if let vs = vsAverage {
            let pctStr = DS.Format.percent(abs(vs.percentChange))
            switch vs.direction {
            case .below:
                subheadline = "That's \(pctStr) below your 3-month average"
            case .above:
                subheadline = "That's \(pctStr) above your 3-month average"
            case .equal:
                subheadline = "Right in line with your 3-month average"
            }
        } else {
            subheadline = "Keep tracking to build your spending baseline"
        }

        if summary.spentRatio >= 1.0 {
            headline = "You went over budget in \(monthName)"
        }

        let overview = OverviewSection(
            headline: headline,
            subheadline: subheadline,
            budgetTotal: summary.budgetCents,
            totalSpent: summary.totalSpent,
            totalIncome: income,
            remaining: summary.remaining,
            spentRatio: summary.spentRatio,
            vsAverage: vsAverage
        )

        // MARK: - Spending

        let categories = Analytics.categoryBreakdown(store: store)
        let spendingSection: SpendingSection?
        if !categories.isEmpty {
            let totalSpent = max(1, summary.totalSpent)
            let top5 = categories.prefix(5).map { row in
                (category: row.category.title,
                 amount: row.total,
                 percent: Double(row.total) / Double(totalSpent))
            }

            let concentrationWarning: String?
            if let top = top5.first, top.percent > 0.35 {
                concentrationWarning = "\(DS.Format.percent(top.percent)) of spending in \(top.category)"
            } else {
                concentrationWarning = nil
            }

            // Small expense detection
            let monthTx = Analytics.monthTransactions(store: store)
            let smallThreshold = max(500, summary.dailyAvg / 3)  // ~1/3 of daily avg
            let smallTx = monthTx.filter { $0.amount < smallThreshold && $0.amount > 0 }
            let smallAlert: String?
            if smallTx.count >= 8 {
                let total = smallTx.reduce(0) { $0 + $1.amount }
                smallAlert = "\(smallTx.count) small purchases added up to \(DS.Format.money(total))"
            } else {
                smallAlert = nil
            }

            spendingSection = SpendingSection(
                topCategories: top5,
                concentrationWarning: concentrationWarning,
                smallExpenseAlert: smallAlert,
                dailyAverage: summary.dailyAvg
            )
        } else {
            spendingSection = nil
        }

        // MARK: - Forecast

        let forecastSection: ForecastSection?
        if let f = forecast {
            forecastSection = ForecastSection(
                safeToSpendTotal: f.safeToSpend.totalAmount,
                safeToSpendPerDay: f.safeToSpend.perDay,
                riskLevel: f.riskLevel.label.lowercased(),
                riskSummary: f.urgentRiskSummary,
                projected30Day: f.projected30Day,
                projectedMonthEnd: f.projectedMonthEnd,
                upcomingBillCount: f.upcomingBills.count,
                overdueBillCount: f.overdueBillCount,
                dataConfidence: f.dataConfidence.label.lowercased()
            )
        } else {
            forecastSection = nil
        }

        // MARK: - Subscriptions

        let subscriptionSection: SubscriptionSection?
        if let ss = subscriptionSnapshot, ss.activeCount > 0 {
            let headline: String
            if ss.unusedCount > 0 {
                headline = "\(ss.unusedCount) subscription\(ss.unusedCount == 1 ? "" : "s") may be unused — save \(DS.Format.money(ss.potentialSavings))/mo"
            } else if ss.priceIncreaseCount > 0 {
                headline = "\(ss.priceIncreaseCount) subscription\(ss.priceIncreaseCount == 1 ? "" : "s") increased in price"
            } else {
                headline = "\(ss.activeCount) active subscriptions totaling \(DS.Format.money(ss.monthlyTotal))/mo"
            }

            subscriptionSection = SubscriptionSection(
                activeCount: ss.activeCount,
                monthlyTotal: ss.monthlyTotal,
                unusedCount: ss.unusedCount,
                potentialSavings: ss.potentialSavings,
                priceIncreaseCount: ss.priceIncreaseCount,
                renewingSoonCount: ss.renewingSoon,
                headline: headline
            )
        } else {
            subscriptionSection = nil
        }

        // MARK: - Review

        let reviewSection: ReviewSection?
        if let rs = reviewSnapshot, rs.pendingCount > 0 {
            var parts: [String] = []
            if rs.duplicateCount > 0 { parts.append("\(rs.duplicateCount) potential duplicate\(rs.duplicateCount == 1 ? "" : "s")") }
            if rs.uncategorizedCount > 0 { parts.append("\(rs.uncategorizedCount) uncategorized") }
            if rs.spikeCount > 0 { parts.append("\(rs.spikeCount) spending spike\(rs.spikeCount == 1 ? "" : "s")") }

            let headline: String
            if parts.isEmpty {
                headline = "\(rs.pendingCount) transaction\(rs.pendingCount == 1 ? "" : "s") need\(rs.pendingCount == 1 ? "s" : "") review"
            } else {
                headline = "\(rs.pendingCount) to review: \(parts.joined(separator: ", "))"
            }

            reviewSection = ReviewSection(
                pendingCount: rs.pendingCount,
                highPriorityCount: rs.highPriorityCount,
                duplicateCount: rs.duplicateCount,
                uncategorizedCount: rs.uncategorizedCount,
                headline: headline
            )
        } else {
            reviewSection = nil
        }

        // MARK: - Goals

        let goalSection: GoalSection?
        if let gm = goalManager, !gm.activeGoals.isEmpty {
            let active = gm.activeGoals
            let behind = gm.behindGoals.count
            let onTrack = active.count - behind
            let totalProgress = active.isEmpty ? 0.0 :
                Double(active.reduce(0) { $0 + $1.currentAmount }) /
                Double(max(1, active.reduce(0) { $0 + $1.targetAmount }))

            let headline: String
            if behind > 0 {
                headline = "\(onTrack) goal\(onTrack == 1 ? "" : "s") on track, \(behind) behind"
            } else {
                headline = "All \(active.count) goal\(active.count == 1 ? "" : "s") on track"
            }

            let topGoal = active.sorted { $0.progress > $1.progress }.first

            goalSection = GoalSection(
                activeGoalCount: active.count,
                totalProgress: totalProgress,
                behindCount: behind,
                headline: headline,
                topGoalName: topGoal?.name,
                topGoalProgress: topGoal.map { $0.progress }
            )
        } else {
            goalSection = nil
        }

        // MARK: - Household

        let householdSection: HouseholdSection?
        if let hs = householdSnapshot, hs.hasPartner {
            let partnerName = HouseholdManager.shared.household?.partner?.displayName ?? "Partner"
            let netBalance = hs.owedToYou - hs.youOwe

            let headline: String
            if hs.sharedSpending > 0 {
                headline = "You and \(partnerName) spent \(DS.Format.money(hs.sharedSpending)) together"
            } else {
                headline = "No shared expenses this month"
            }

            householdSection = HouseholdSection(
                partnerName: partnerName,
                sharedSpending: hs.sharedSpending,
                sharedBudget: hs.sharedBudget,
                netBalance: netBalance,
                unsettledCount: hs.unsettledCount,
                headline: headline
            )
        } else {
            householdSection = nil
        }

        return MonthlyBriefing(
            monthKey: monthKey,
            generatedAt: Date(),
            overview: overview,
            spending: spendingSection,
            forecast: forecastSection,
            subscriptions: subscriptionSection,
            review: reviewSection,
            goals: goalSection,
            household: householdSection,
            healthScore: nil  // P3-F7 will populate this
        )
    }

    // MARK: - Helpers

    private static func monthKeyString(from date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        return String(format: "%04d-%02d", y, m)
    }

    private static func monthDisplayName(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }

    /// Compare current month's spending to 3-month average.
    private static func computeVsAverage(store: Store, currentSpent: Int) -> ComparisonResult? {
        let cal = Calendar.current
        let now = store.selectedMonth
        var monthTotals: [Int] = []

        for offset in 1...3 {
            guard let pastMonth = cal.date(byAdding: .month, value: -offset, to: now) else { continue }
            let spent = store.spent(for: pastMonth)
            if spent > 0 {
                monthTotals.append(spent)
            }
        }

        guard !monthTotals.isEmpty else { return nil }

        let avg = monthTotals.reduce(0, +) / monthTotals.count
        guard avg > 0 else { return nil }

        let delta = currentSpent - avg
        let pctChange = Double(delta) / Double(avg)

        let direction: ComparisonResult.Direction
        if abs(pctChange) < 0.02 {
            direction = .equal
        } else if pctChange > 0 {
            direction = .above
        } else {
            direction = .below
        }

        return ComparisonResult(
            avgAmount: avg,
            delta: delta,
            percentChange: pctChange,
            direction: direction
        )
    }
}
