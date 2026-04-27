import Foundation

// ============================================================
// MARK: - Briefing Engine
// ============================================================
//
// Produces a MonthlyBriefing as an ordered [BriefingSection].
// Each section has its own builder; the top-level engine
// coordinates ordering, relevance gating, and confidence.
//
// Anchored to store.selectedMonth (never Date()).
// Template-driven, no LLM.
//
// Section order is dynamic:
//   1. Overview always first.
//   2. Forecast jumps above Spending if there's an urgent risk
//      or overdue bills (so danger surfaces fast).
//   3. Otherwise: Spending → Forecast → Subscriptions → Review
//      → Goals → Household.
//
// ============================================================

@MainActor
enum BriefingEngine {

    // MARK: - Cache

    private struct CacheKey: Hashable {
        let monthKey: String
        let storeRevision: Int
    }

    private static var cache: [CacheKey: MonthlyBriefing] = [:]

    /// Invalidate the cache. Call when something mutates store state and
    /// you want the next generate() to recompute. Optional — the cache
    /// also keys on a revision number, so callers can bump that instead.
    static func invalidateCache() {
        cache.removeAll()
    }

    // MARK: - Public entry point

    static func generate(
        store: Store,
        forecast: ForecastResult?,
        reviewSnapshot: ReviewSnapshot?,
        subscriptionSnapshot: SubscriptionSnapshot?,
        householdSnapshot: HouseholdSnapshot?,
        goalManager: GoalManager?,
        storeRevision: Int = 0
    ) -> MonthlyBriefing {
        let monthKey = monthKeyString(from: store.selectedMonth)
        let key = CacheKey(monthKey: monthKey, storeRevision: storeRevision)
        if storeRevision > 0, let hit = cache[key] {
            return hit
        }

        let summary = Analytics.monthSummary(store: store)
        let income = store.income(for: store.selectedMonth)
        let vsAverage = computeVsAverage(store: store, currentSpent: summary.totalSpent)
        let monthsOfData = forecast?.monthsOfData ?? 0

        var sections: [BriefingSection] = []

        // Overview — always present
        sections.append(buildOverview(
            store: store,
            summary: summary,
            income: income,
            vsAverage: vsAverage,
            monthsOfData: monthsOfData
        ))

        // Forecast (built first so we can decide priority placement)
        let forecastSection = buildForecast(forecast: forecast)

        // Spending
        let spendingSection = buildSpending(store: store, summary: summary)

        // Promote forecast above spending when there's urgent risk
        let forecastIsUrgent: Bool = {
            guard let f = forecast else { return false }
            return f.urgentRiskSummary != nil || f.overdueBillCount > 0
        }()

        if forecastIsUrgent, let fs = forecastSection {
            sections.append(fs)
            if let ss = spendingSection { sections.append(ss) }
        } else {
            if let ss = spendingSection { sections.append(ss) }
            if let fs = forecastSection { sections.append(fs) }
        }

        if let s = buildSubscriptions(snapshot: subscriptionSnapshot) { sections.append(s) }
        if let r = buildReview(snapshot: reviewSnapshot) { sections.append(r) }
        if let g = buildGoals(goalManager: goalManager) { sections.append(g) }
        if let h = buildHousehold(snapshot: householdSnapshot) { sections.append(h) }

        let briefing = MonthlyBriefing(
            monthKey: monthKey,
            generatedAt: Date(),
            sections: sections
        )

        if storeRevision > 0 {
            cache[key] = briefing
        }
        return briefing
    }

    // ============================================================
    // MARK: - Section Builders
    // ============================================================

    private static func buildOverview(
        store: Store,
        summary: Analytics.MonthSummary,
        income: Int,
        vsAverage: ComparisonResult?,
        monthsOfData: Int
    ) -> BriefingSection {
        let monthName = monthDisplayName(from: store.selectedMonth)
        let spentFormatted = DS.Format.money(summary.totalSpent)

        var headline = "You spent \(spentFormatted) in \(monthName)"
        if summary.spentRatio >= 1.0 {
            headline = "You went over budget in \(monthName)"
        }

        let subheadline: String
        if let vs = vsAverage {
            let pctStr = DS.Format.percent(abs(vs.percentChange))
            switch vs.direction {
            case .below: subheadline = "That's \(pctStr) below your 3-month average"
            case .above: subheadline = "That's \(pctStr) above your 3-month average"
            case .equal: subheadline = "Right in line with your 3-month average"
            }
        } else {
            subheadline = "Keep tracking to build your spending baseline"
        }

        let payload = OverviewPayload(
            headline: headline,
            subheadline: subheadline,
            budgetTotal: summary.budgetCents,
            totalSpent: summary.totalSpent,
            totalIncome: income,
            remaining: summary.remaining,
            spentRatio: summary.spentRatio,
            vsAverage: vsAverage
        )

        // Confidence keys off available history.
        let confidence: BriefingSection.Confidence
        if vsAverage == nil && monthsOfData < 1 { confidence = .low }
        else if monthsOfData < 3 { confidence = .medium }
        else { confidence = .high }

        return BriefingSection(kind: .overview(payload), confidence: confidence)
    }

    private static func buildSpending(
        store: Store,
        summary: Analytics.MonthSummary
    ) -> BriefingSection? {
        let categories = Analytics.categoryBreakdown(store: store)
        guard !categories.isEmpty else { return nil }

        let totalSpent = max(1, summary.totalSpent)
        let top5 = categories.prefix(5).map {
            SpendingPayload.CategoryRow(
                category: $0.category.title,
                amount: $0.total,
                percent: Double($0.total) / Double(totalSpent)
            )
        }

        let concentrationWarning: String?
        if let top = top5.first, top.percent > 0.35 {
            concentrationWarning = "\(DS.Format.percent(top.percent)) of spending in \(top.category)"
        } else {
            concentrationWarning = nil
        }

        let monthTx = Analytics.monthTransactions(store: store)
        let smallThreshold = max(500, summary.dailyAvg / 3)
        let smallTx = monthTx.filter { $0.amount < smallThreshold && $0.amount > 0 && $0.type == .expense }
        let smallAlert: String?
        if smallTx.count >= 8 {
            let total = smallTx.reduce(0) { $0 + $1.amount }
            smallAlert = "\(smallTx.count) small purchases added up to \(DS.Format.money(total))"
        } else {
            smallAlert = nil
        }

        let payload = SpendingPayload(
            topCategories: top5,
            concentrationWarning: concentrationWarning,
            smallExpenseAlert: smallAlert,
            dailyAverage: summary.dailyAvg
        )

        let confidence: BriefingSection.Confidence = monthTx.count < 5 ? .low
            : monthTx.count < 15 ? .medium
            : .high

        return BriefingSection(kind: .spending(payload), confidence: confidence)
    }

    private static func buildForecast(forecast: ForecastResult?) -> BriefingSection? {
        guard let f = forecast else { return nil }

        let risk: ForecastPayload.RiskLevel = {
            switch f.riskLevel.label.lowercased() {
            case "safe": return .safe
            case "caution": return .caution
            default: return .highRisk
            }
        }()

        let payload = ForecastPayload(
            safeToSpendTotal: f.safeToSpend.totalAmount,
            safeToSpendPerDay: f.safeToSpend.perDay,
            riskLevel: risk,
            riskSummary: f.urgentRiskSummary,
            projectedMonthEnd: f.projectedMonthEnd,
            upcomingBillCount: f.upcomingBills.count,
            overdueBillCount: f.overdueBillCount
        )

        let confidence: BriefingSection.Confidence = {
            switch f.dataConfidence.label.lowercased() {
            case "high": return .high
            case "medium": return .medium
            default: return .low
            }
        }()

        return BriefingSection(kind: .forecast(payload), confidence: confidence)
    }

    private static func buildSubscriptions(snapshot: SubscriptionSnapshot?) -> BriefingSection? {
        guard let ss = snapshot, ss.activeCount > 0 else { return nil }

        let headline: String
        if ss.unusedCount > 0 {
            headline = "\(ss.unusedCount) subscription\(ss.unusedCount == 1 ? "" : "s") may be unused — save \(DS.Format.money(ss.potentialSavings))/mo"
        } else if ss.priceIncreaseCount > 0 {
            headline = "\(ss.priceIncreaseCount) subscription\(ss.priceIncreaseCount == 1 ? "" : "s") increased in price"
        } else {
            headline = "\(ss.activeCount) active subscriptions totaling \(DS.Format.money(ss.monthlyTotal))/mo"
        }

        let payload = SubscriptionPayload(
            activeCount: ss.activeCount,
            monthlyTotal: ss.monthlyTotal,
            unusedCount: ss.unusedCount,
            potentialSavings: ss.potentialSavings,
            priceIncreaseCount: ss.priceIncreaseCount,
            renewingSoonCount: ss.renewingSoon,
            headline: headline
        )
        return BriefingSection(kind: .subscriptions(payload), confidence: .high)
    }

    private static func buildReview(snapshot: ReviewSnapshot?) -> BriefingSection? {
        guard let rs = snapshot, rs.pendingCount > 0 else { return nil }

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

        let payload = ReviewPayload(
            pendingCount: rs.pendingCount,
            highPriorityCount: rs.highPriorityCount,
            duplicateCount: rs.duplicateCount,
            uncategorizedCount: rs.uncategorizedCount,
            headline: headline
        )
        return BriefingSection(kind: .review(payload), confidence: .high)
    }

    private static func buildGoals(goalManager: GoalManager?) -> BriefingSection? {
        guard let gm = goalManager, !gm.activeGoals.isEmpty else { return nil }

        let active = gm.activeGoals
        let behind = gm.behindGoals.count
        let onTrack = active.count - behind
        let totalProgress = Double(active.reduce(0) { $0 + $1.currentAmount }) /
                            Double(max(1, active.reduce(0) { $0 + $1.targetAmount }))

        let headline: String
        if behind > 0 {
            headline = "\(onTrack) goal\(onTrack == 1 ? "" : "s") on track, \(behind) behind"
        } else {
            headline = "All \(active.count) goal\(active.count == 1 ? "" : "s") on track"
        }

        let topGoal = active.sorted { $0.progress > $1.progress }.first

        let payload = GoalPayload(
            activeGoalCount: active.count,
            totalProgress: totalProgress,
            behindCount: behind,
            headline: headline,
            topGoalName: topGoal?.name,
            topGoalProgress: topGoal.map { $0.progress }
        )
        return BriefingSection(kind: .goals(payload), confidence: .high)
    }

    private static func buildHousehold(snapshot: HouseholdSnapshot?) -> BriefingSection? {
        guard let hs = snapshot, hs.hasPartner else { return nil }

        let partnerName = HouseholdManager.shared.household?.partner?.displayName ?? "Partner"
        let netBalance = hs.owedToYou - hs.youOwe

        let headline: String
        if hs.sharedSpending > 0 {
            headline = "You and \(partnerName) spent \(DS.Format.money(hs.sharedSpending)) together"
        } else {
            headline = "No shared expenses this month"
        }

        let payload = HouseholdPayload(
            partnerName: partnerName,
            sharedSpending: hs.sharedSpending,
            sharedBudget: hs.sharedBudget,
            netBalance: netBalance,
            unsettledCount: hs.unsettledCount,
            headline: headline
        )
        return BriefingSection(kind: .household(payload), confidence: .high)
    }

    // ============================================================
    // MARK: - Helpers
    // ============================================================

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

    /// Compare current month's spending to 3-month average,
    /// anchored on store.selectedMonth (NOT Date()).
    private static func computeVsAverage(store: Store, currentSpent: Int) -> ComparisonResult? {
        let cal = Calendar.current
        let anchor = store.selectedMonth
        var monthTotals: [Int] = []

        for offset in 1...3 {
            guard let pastMonth = cal.date(byAdding: .month, value: -offset, to: anchor) else { continue }
            let spent = store.spent(for: pastMonth)
            if spent > 0 { monthTotals.append(spent) }
        }

        guard !monthTotals.isEmpty else { return nil }
        let avg = monthTotals.reduce(0, +) / monthTotals.count
        guard avg > 0 else { return nil }

        let delta = currentSpent - avg
        let pctChange = Double(delta) / Double(avg)

        let direction: ComparisonResult.Direction
        if abs(pctChange) < 0.02 { direction = .equal }
        else if pctChange > 0 { direction = .above }
        else { direction = .below }

        return ComparisonResult(avgAmount: avg, delta: delta, percentChange: pctChange, direction: direction)
    }
}
