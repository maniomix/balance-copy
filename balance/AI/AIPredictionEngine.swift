import Foundation

// ============================================================
// MARK: - AI Prediction Engine (Phase 5b — iOS port)
// ============================================================
//
// Computes spending predictions, category projections, and end-of-month
// forecasts from the iOS Store. Feeds `AIPredictionView` and the AI
// prompt builder (qualitative "key signals" analysis).
//
// Ported from macOS Centmond `AIPredictionEngine.swift`. This slot
// delivers the full data-model layer + parser + a working compute
// skeleton that the prediction UI can render against. Secondary
// builders (subscription pressure, emotional profile, full per-account
// snapshot math) are intentionally lean — they can be enriched
// incrementally without blocking the UI port.
//
// iOS conventions:
//   - Amounts stay as Double at this layer (charts consume them directly).
//     Transactions are converted from Int cents at the boundary.
//   - Store singleton instead of SwiftData `ModelContext`.
//   - `tx.payee` → `tx.note`; `tx.isIncome` → `tx.type == .income`.
// ============================================================

// MARK: - AIPredictionResult (parsed from Gemma 4 output)

struct AICategoryPrediction {
    let name: String
    let projected: Double
}

struct AITrigger: Identifiable {
    let id = UUID()
    let pattern: String         // "Late-night ordering"
    let description: String     // "3 food delivery orders after 10 PM totaling $47"
    let amount: Double
}

struct AIAnomaly: Identifiable {
    let id = UUID()
    let merchant: String
    let amount: Double
    let description: String     // "Gaming purchase 3x your usual entertainment spend"
}

struct AICombatAction: Identifiable {
    let id = UUID()
    let action: String          // "Cancel Netflix Basic"
    let savings: Double         // dollars
    let reason: String          // "No activity in 3 weeks"
}

struct AIPredictionResult {
    let projectedMonthlySpending: Double
    let savingsRate: Double
    let riskLevel: String       // low/medium/high
    let weeklyTrend: String     // accelerating/decelerating/stable
    let categoryPredictions: [AICategoryPrediction]
    let breakEvenDay: Int?
    let triggers: [AITrigger]
    let anomalies: [AIAnomaly]
    let combatPlan: [AICombatAction]

    /// Parse the `---PREDICTIONS---` JSON block from streamed model output.
    /// Returns nil when the block isn't present or the JSON fails to
    /// decode; callers fall back to `AIPredictionResult.fallback`.
    static func parse(from rawText: String, fallback data: PredictionData?) -> AIPredictionResult? {
        guard let startRange = rawText.range(of: "---PREDICTIONS---") else { return nil }
        let afterStart = rawText[startRange.upperBound...]
        guard let endRange = afterStart.range(of: "---PREDICTIONS---") else { return nil }
        let jsonStr = String(afterStart[..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        let projected = json["projectedSpending"] as? Double ?? data?.forecast.projectedSpending ?? 0
        let savings = json["savingsRate"] as? Double ?? 0
        let risk = json["riskLevel"] as? String ?? "medium"
        let trend = json["weeklyTrend"] as? String ?? "stable"
        let breakEven = json["breakEvenDay"] as? Int

        var catPredictions: [AICategoryPrediction] = []
        if let cats = json["categories"] as? [[String: Any]] {
            for cat in cats {
                if let name = cat["name"] as? String, let amount = cat["projected"] as? Double {
                    catPredictions.append(AICategoryPrediction(name: name, projected: amount))
                }
            }
        }

        var triggers: [AITrigger] = []
        if let trigs = json["triggers"] as? [[String: Any]] {
            for t in trigs {
                guard let pattern = t["pattern"] as? String,
                      let desc = t["description"] as? String,
                      let amount = t["amount"] as? Double else { continue }
                triggers.append(AITrigger(pattern: pattern, description: desc, amount: amount))
            }
        }

        var anomalies: [AIAnomaly] = []
        if let anoms = json["anomalies"] as? [[String: Any]] {
            for a in anoms {
                guard let merchant = a["merchant"] as? String,
                      let amount = a["amount"] as? Double,
                      let desc = a["description"] as? String else { continue }
                anomalies.append(AIAnomaly(merchant: merchant, amount: amount, description: desc))
            }
        }

        var combat: [AICombatAction] = []
        if let plan = json["combatPlan"] as? [[String: Any]] {
            for c in plan {
                guard let action = c["action"] as? String,
                      let savings = c["savings"] as? Double,
                      let reason = c["reason"] as? String else { continue }
                combat.append(AICombatAction(action: action, savings: savings, reason: reason))
            }
        }

        return AIPredictionResult(
            projectedMonthlySpending: projected,
            savingsRate: savings,
            riskLevel: risk,
            weeklyTrend: trend,
            categoryPredictions: catPredictions,
            breakEvenDay: breakEven,
            triggers: triggers,
            anomalies: anomalies,
            combatPlan: combat
        )
    }

    /// Heuristic fallback when the LLM hasn't produced a valid block yet.
    static func fallback(from data: PredictionData) -> AIPredictionResult {
        let f = data.forecast
        let projectedOverBudget = f.totalBudget > 0 && f.projectedSpending > f.totalBudget
        let risk: String = {
            if projectedOverBudget && f.projectedSpending > f.totalBudget * 1.15 { return "high" }
            if projectedOverBudget { return "medium" }
            return "low"
        }()

        // Week-over-week trend from weekly comparison.
        let trend: String = {
            let delta = data.weeklyComparison.percentChange
            if delta >= 0.10 { return "accelerating" }
            if delta <= -0.10 { return "decelerating" }
            return "stable"
        }()

        // Break-even day: first day-offset where cumulative trajectory crosses
        // total budget. Falls back to nil if never crosses.
        let breakEven: Int? = {
            guard f.totalBudget > 0 else { return nil }
            for point in data.spendingTrajectory where point.cumulative >= f.totalBudget {
                return point.dayIndex
            }
            return nil
        }()

        let cats = data.categoryProjections.prefix(5).map {
            AICategoryPrediction(name: $0.name, projected: $0.projected)
        }

        return AIPredictionResult(
            projectedMonthlySpending: f.projectedSpending,
            savingsRate: data.savingsRate,
            riskLevel: risk,
            weeklyTrend: trend,
            categoryPredictions: Array(cats),
            breakEvenDay: breakEven,
            triggers: [],
            anomalies: [],
            combatPlan: []
        )
    }
}

// ============================================================
// MARK: - Data Models
// ============================================================

struct SpendingDataPoint: Identifiable {
    let id = UUID()
    let dayIndex: Int       // 1-based day offset from window start
    let cumulative: Double
    let isProjected: Bool
}

struct DailySpendingBar: Identifiable {
    let id = UUID()
    let dayIndex: Int
    let date: Date
    let amount: Double
    let isProjected: Bool
}

struct ConfidenceBandPoint: Identifiable {
    let id = UUID()
    let dayIndex: Int
    let lower: Double
    let upper: Double
}

struct CategoryProjection: Identifiable {
    let id = UUID()
    let name: String
    let iconName: String
    let spent: Double
    let projected: Double
    let budget: Double
    let icon: String
    let colorHex: String?

    var isOverBudget: Bool { budget > 0 && projected > budget }
    var percentOfBudget: Double {
        guard budget > 0 else { return 0 }
        return projected / budget
    }
}

struct MonthForecast {
    let projectedSpending: Double
    let totalBudget: Double
    let incomeReceived: Double
    let expectedIncome: Double
    let spentSoFar: Double
    let daysLeft: Int
    let daysPassed: Int

    var totalIncome: Double { incomeReceived + expectedIncome }
    var surplus: Double { totalIncome - projectedSpending }
    var pacePerDay: Double {
        guard daysPassed > 0 else { return 0 }
        return spentSoFar / Double(daysPassed)
    }
}

struct TopMerchant: Identifiable {
    let id = UUID()
    let name: String
    let total: Double
    let count: Int
}

struct WeeklyComparison {
    let thisWeek: Double
    let lastWeek: Double

    var percentChange: Double {
        guard lastWeek > 0 else { return thisWeek > 0 ? 1.0 : 0 }
        return (thisWeek - lastWeek) / lastWeek
    }
}

struct AccountSnapshot: Identifiable {
    let id = UUID()
    let name: String
    let balance: Double
    let isLiability: Bool
    let iconName: String
}

struct SubscriptionPressure {
    let monthlyTotal: Double
    let count: Int
    let unusedCount: Int
}

struct RecentTransaction: Identifiable {
    let id = UUID()
    let date: Date
    let payee: String
    let amount: Double
    let categoryName: String
    let isWeekend: Bool
    let hourOfDay: Int
    let dayOfWeek: String   // "Mon", "Tue", …
}

struct EmotionalSpendingProfile {
    let lateNightCount: Int
    let lateNightTotal: Double
    let weekendCount: Int
    let weekendTotal: Double
    let topHour: Int?          // 0-23
    let topDayOfWeek: String?
    let burstDays: [Date]      // days with unusually high count / amount
}

struct MonthlySpendingData: Identifiable {
    let id = UUID()
    let monthStart: Date
    let label: String          // "Apr"
    let actual: Double
    let forecast: Double       // 0 unless current month
    let income: Double
}

struct PredictionData {
    let windowStart: Date
    let spendingTrajectory: [SpendingDataPoint]
    let dailyBars: [DailySpendingBar]
    let confidenceBand: [ConfidenceBandPoint]
    let forecast: MonthForecast
    let categoryProjections: [CategoryProjection]
    let topMerchants: [TopMerchant]
    let weeklyComparison: WeeklyComparison
    let accountSnapshots: [AccountSnapshot]
    let subscriptionPressure: SubscriptionPressure?
    let savingsRate: Double
    let lastMonthSpending: Double
    let topInsights: [String]
    let recentTransactions: [RecentTransaction]
    let currentMonthTransactions: [RecentTransaction]
    let emotionalProfile: EmotionalSpendingProfile
    let monthlyOverview: [MonthlySpendingData]
}

// MARK: - Analysis Window

/// User-selectable historical window that widens the dataset the engine
/// feeds to the AI. The current month is ALWAYS included on top of
/// `monthsBack`, so `.last3Months` renders exactly 3 calendar months.
enum PredictionTimeRange: String, CaseIterable, Identifiable {
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case last3Months = "Last 3 Months"
    case last6Months = "Last 6 Months"
    case lastYear = "Last Year"

    var id: String { rawValue }

    /// Months BEFORE the current month. The rendered window is
    /// `monthsBack + 1` calendar months.
    var monthsBack: Int {
        switch self {
        case .thisMonth:    return 0
        case .lastMonth:    return 1
        case .last3Months:  return 2
        case .last6Months:  return 5
        case .lastYear:     return 11
        }
    }

    var shortLabel: String {
        switch self {
        case .thisMonth:    return "1M"
        case .lastMonth:    return "2M"
        case .last3Months:  return "3M"
        case .last6Months:  return "6M"
        case .lastYear:     return "1Y"
        }
    }
}

// ============================================================
// MARK: - Engine
// ============================================================

enum AIPredictionEngine {

    /// Build a `PredictionData` snapshot from the Store. Accounts are passed
    /// separately since iOS Accounts live in `AccountManager`.
    ///
    /// This is a working skeleton: trajectory, daily bars, confidence band,
    /// forecast, top merchants, weekly comparison, category projections,
    /// and savings rate are fully populated. Account snapshots /
    /// subscription pressure / emotional profile are lean — they can be
    /// enriched incrementally.
    static func compute(
        store: Store,
        accounts: [Account] = [],
        range: PredictionTimeRange = .thisMonth
    ) -> PredictionData {
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: now)
        let startOfMonth = cal.date(from: comps) ?? now
        let windowStart = cal.date(byAdding: .month, value: -range.monthsBack, to: startOfMonth) ?? startOfMonth
        let nextMonthStart = cal.date(byAdding: .month, value: 1, to: startOfMonth) ?? startOfMonth
        let windowEnd = cal.date(byAdding: .day, value: -1, to: nextMonthStart) ?? nextMonthStart

        let totalDays = (cal.dateComponents([.day], from: windowStart, to: windowEnd).day ?? 0) + 1
        let daysPassed = max(1, (cal.dateComponents([.day], from: windowStart, to: now).day ?? 0) + 1)

        let (year, month) = (comps.year ?? 0, comps.month ?? 0)

        // ── Fetch window transactions ─────────────────────────────────
        let windowTxns = store.transactions.filter { $0.date >= windowStart && $0.date < nextMonthStart }
        let expenses = windowTxns.filter { $0.type == .expense }
        let incomeTotal = windowTxns
            .filter { $0.type == .income }
            .reduce(0.0) { $0 + Double($1.amount) / 100.0 }

        // Expected income from active recurring income templates (iOS has
        // none today — all templates are expenses — but this keeps the
        // surface stable for when income templates land).
        let expectedIncome: Double = 0

        // ── Total budget (sum per-month inside the window) ────────────
        var totalBudget: Double = 0
        var cursor = windowStart
        while cursor < nextMonthStart {
            let key = Store.monthKey(cursor)
            totalBudget += Double(store.budgetsByMonth[key] ?? 0) / 100.0
            cursor = cal.date(byAdding: .month, value: 1, to: cursor) ?? nextMonthStart
        }

        // ── Daily totals (day-offset → spent $) ───────────────────────
        var dailyTotals: [Int: Double] = [:]
        for tx in expenses {
            let dayIdx = cal.dateComponents([.day], from: windowStart, to: tx.date).day ?? 0
            dailyTotals[dayIdx, default: 0] += Double(tx.amount) / 100.0
        }

        // ── Actual / projected split (data-driven) ────────────────────
        let lastDataDayIdx: Int? = {
            let candidates = dailyTotals.keys.filter { $0 >= 0 && $0 < totalDays && (dailyTotals[$0] ?? 0) > 0 }
            return candidates.max()
        }()
        let firstProjectedDay: Int = {
            let byCalendar = daysPassed
            if let last = lastDataDayIdx, last + 1 > byCalendar {
                return min(last + 1, totalDays)
            }
            return min(byCalendar, totalDays)
        }()
        let projectedDaysLeft = max(0, totalDays - firstProjectedDay)

        let spentSoFar = expenses.reduce(0.0) { $0 + Double($1.amount) / 100.0 }
        let actualDaysCount = max(1, firstProjectedDay)
        let dailyAvg = spentSoFar / Double(actualDaysCount)

        let dailyAmounts = (0..<actualDaysCount).map { dailyTotals[$0] ?? 0 }
        let stdDev = standardDeviation(dailyAmounts)

        // ── Trajectory / bars / confidence band ──────────────────────
        let trajectory = buildTrajectory(
            dailyTotals: dailyTotals,
            windowStart: windowStart,
            firstProjectedDay: firstProjectedDay,
            totalDays: totalDays,
            dailyAvg: dailyAvg,
            cal: cal
        )
        let bars = buildDailyBars(
            dailyTotals: dailyTotals,
            windowStart: windowStart,
            firstProjectedDay: firstProjectedDay,
            totalDays: totalDays,
            dailyAvg: dailyAvg,
            cal: cal
        )
        let band = buildConfidenceBand(
            firstProjectedDay: firstProjectedDay,
            totalDays: totalDays,
            cumulativeAtToday: spentSoFar,
            dailyAvg: dailyAvg,
            stdDev: stdDev
        )

        let projectedSpending = spentSoFar + (dailyAvg * Double(projectedDaysLeft))

        let forecast = MonthForecast(
            projectedSpending: projectedSpending,
            totalBudget: totalBudget,
            incomeReceived: incomeTotal,
            expectedIncome: expectedIncome,
            spentSoFar: spentSoFar,
            daysLeft: projectedDaysLeft,
            daysPassed: firstProjectedDay
        )

        // ── Category projections ──────────────────────────────────────
        let monthsInWindow = max(1, range.monthsBack + 1)
        let catProjections = buildCategoryProjections(
            store: store,
            expenses: expenses,
            year: year, month: month,
            daysPassed: max(1, firstProjectedDay),
            totalDays: totalDays,
            budgetMultiplier: monthsInWindow
        )

        // ── Supporting aggregates ─────────────────────────────────────
        let topMerchants = buildTopMerchants(expenses: expenses)
        let weeklyComparison = buildWeeklyComparison(store: store, now: now, cal: cal)
        let accountSnapshots = buildAccountSnapshots(accounts: accounts)
        let subscriptionPressure = buildSubscriptionPressure(store: store, now: now)
        let totalIncome = incomeTotal + expectedIncome
        let savingsRate = totalIncome > 0 ? (totalIncome - projectedSpending) / totalIncome : 0

        // Last month spending for comparison
        let lastMonthStart = cal.date(byAdding: .month, value: -1, to: startOfMonth) ?? startOfMonth
        let lastMonthSpending = store.transactions
            .filter { $0.type == .expense && $0.date >= lastMonthStart && $0.date < startOfMonth }
            .reduce(0.0) { $0 + Double($1.amount) / 100.0 }

        let insights = generateInsights(forecast: forecast, categories: catProjections)

        // ── Recent + current-month transaction samples ───────────────
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let sampleCap: Int = {
            switch range {
            case .thisMonth:    return 50
            case .lastMonth:    return 80
            case .last3Months:  return 120
            case .last6Months:  return 160
            case .lastYear:     return 200
            }
        }()
        let recentTxns: [RecentTransaction] = expenses
            .sorted(by: { $0.date > $1.date })
            .prefix(sampleCap)
            .map { tx in
                let hour = cal.component(.hour, from: tx.date)
                let weekday = cal.component(.weekday, from: tx.date)
                return RecentTransaction(
                    date: tx.date,
                    payee: tx.note.isEmpty ? "Unknown" : tx.note,
                    amount: Double(tx.amount) / 100.0,
                    categoryName: tx.category.title,
                    isWeekend: weekday == 1 || weekday == 7,
                    hourOfDay: hour,
                    dayOfWeek: dayNames[weekday - 1]
                )
            }

        let currentMonthExpenses = expenses.filter {
            cal.component(.month, from: $0.date) == month && cal.component(.year, from: $0.date) == year
        }
        let currentMonthTxns: [RecentTransaction] = currentMonthExpenses.map { tx in
            let hour = cal.component(.hour, from: tx.date)
            let weekday = cal.component(.weekday, from: tx.date)
            return RecentTransaction(
                date: tx.date,
                payee: tx.note.isEmpty ? "Unknown" : tx.note,
                amount: Double(tx.amount) / 100.0,
                categoryName: tx.category.title,
                isWeekend: weekday == 1 || weekday == 7,
                hourOfDay: hour,
                dayOfWeek: dayNames[weekday - 1]
            )
        }

        let emotionalProfile = buildEmotionalProfile(transactions: recentTxns)

        let monthlyOverview = buildMonthlyOverview(
            store: store,
            rangeStart: windowStart,
            currentMonthStart: startOfMonth,
            currentMonthSpent: spentSoFar,
            currentMonthProjected: projectedSpending,
            currentMonthIncome: incomeTotal,
            expectedMonthIncome: expectedIncome,
            cal: cal
        )

        return PredictionData(
            windowStart: windowStart,
            spendingTrajectory: trajectory,
            dailyBars: bars,
            confidenceBand: band,
            forecast: forecast,
            categoryProjections: catProjections,
            topMerchants: topMerchants,
            weeklyComparison: weeklyComparison,
            accountSnapshots: accountSnapshots,
            subscriptionPressure: subscriptionPressure,
            savingsRate: savingsRate,
            lastMonthSpending: lastMonthSpending,
            topInsights: insights,
            recentTransactions: recentTxns,
            currentMonthTransactions: currentMonthTxns,
            emotionalProfile: emotionalProfile,
            monthlyOverview: monthlyOverview
        )
    }

    // MARK: - Trajectory

    private static func buildTrajectory(
        dailyTotals: [Int: Double],
        windowStart: Date,
        firstProjectedDay: Int,
        totalDays: Int,
        dailyAvg: Double,
        cal: Calendar
    ) -> [SpendingDataPoint] {
        var points: [SpendingDataPoint] = []
        var cumulative: Double = 0
        for day in 0..<totalDays {
            let isProjected = day >= firstProjectedDay
            if isProjected {
                cumulative += dailyAvg
            } else {
                cumulative += dailyTotals[day] ?? 0
            }
            points.append(SpendingDataPoint(
                dayIndex: day + 1,
                cumulative: cumulative,
                isProjected: isProjected
            ))
        }
        return points
    }

    // MARK: - Daily bars

    private static func buildDailyBars(
        dailyTotals: [Int: Double],
        windowStart: Date,
        firstProjectedDay: Int,
        totalDays: Int,
        dailyAvg: Double,
        cal: Calendar
    ) -> [DailySpendingBar] {
        var bars: [DailySpendingBar] = []
        bars.reserveCapacity(totalDays)
        for day in 0..<totalDays {
            let date = cal.date(byAdding: .day, value: day, to: windowStart) ?? windowStart
            let isProjected = day >= firstProjectedDay
            let amount = isProjected ? dailyAvg : (dailyTotals[day] ?? 0)
            bars.append(DailySpendingBar(
                dayIndex: day + 1,
                date: date,
                amount: amount,
                isProjected: isProjected
            ))
        }
        return bars
    }

    // MARK: - Confidence band

    private static func buildConfidenceBand(
        firstProjectedDay: Int,
        totalDays: Int,
        cumulativeAtToday: Double,
        dailyAvg: Double,
        stdDev: Double
    ) -> [ConfidenceBandPoint] {
        guard firstProjectedDay < totalDays else { return [] }
        var band: [ConfidenceBandPoint] = []
        var lower = cumulativeAtToday
        var upper = cumulativeAtToday
        for day in firstProjectedDay..<totalDays {
            // σ widens linearly with day count (simple display band;
            // a true distribution would scale as √n).
            let widenedStdDev = stdDev * Double(day - firstProjectedDay + 1)
            lower += max(0, dailyAvg - widenedStdDev)
            upper += dailyAvg + widenedStdDev
            band.append(ConfidenceBandPoint(
                dayIndex: day + 1,
                lower: lower,
                upper: upper
            ))
        }
        return band
    }

    // MARK: - Category projections

    private static func buildCategoryProjections(
        store: Store,
        expenses: [Transaction],
        year: Int, month: Int,
        daysPassed: Int,
        totalDays: Int,
        budgetMultiplier: Int
    ) -> [CategoryProjection] {
        var byCategory: [String: (spent: Double, category: Category)] = [:]
        for tx in expenses {
            let key = tx.category.storageKey
            byCategory[key, default: (0, tx.category)].spent += Double(tx.amount) / 100.0
            byCategory[key]?.category = tx.category
        }

        let monthKey = String(format: "%04d-%02d", year, month)
        let categoryBudgets = store.categoryBudgetsByMonth[monthKey] ?? [:]
        let dayRatio = Double(totalDays) / Double(max(daysPassed, 1))

        var out: [CategoryProjection] = []
        for (key, entry) in byCategory {
            let projected = entry.spent * dayRatio
            let budgetCents = categoryBudgets[key] ?? 0
            let budget = Double(budgetCents * budgetMultiplier) / 100.0
            out.append(CategoryProjection(
                name: entry.category.title,
                iconName: entry.category.icon,
                spent: entry.spent,
                projected: projected,
                budget: budget,
                icon: entry.category.icon,
                colorHex: nil
            ))
        }
        return out.sorted { $0.projected > $1.projected }
    }

    // MARK: - Top merchants

    private static func buildTopMerchants(expenses: [Transaction]) -> [TopMerchant] {
        var buckets: [String: (total: Double, count: Int)] = [:]
        for tx in expenses where !tx.note.isEmpty {
            let key = tx.note
            buckets[key, default: (0, 0)].total += Double(tx.amount) / 100.0
            buckets[key]?.count += 1
        }
        return buckets
            .sorted { $0.value.total > $1.value.total }
            .prefix(10)
            .map { TopMerchant(name: $0.key, total: $0.value.total, count: $0.value.count) }
    }

    // MARK: - Weekly comparison

    private static func buildWeeklyComparison(store: Store, now: Date, cal: Calendar) -> WeeklyComparison {
        let today = cal.startOfDay(for: now)
        let thisWeekStart = cal.date(byAdding: .day, value: -7, to: today) ?? today
        let lastWeekStart = cal.date(byAdding: .day, value: -14, to: today) ?? today

        let thisWeek = store.transactions
            .filter { $0.type == .expense && $0.date >= thisWeekStart && $0.date <= today }
            .reduce(0.0) { $0 + Double($1.amount) / 100.0 }
        let lastWeek = store.transactions
            .filter { $0.type == .expense && $0.date >= lastWeekStart && $0.date < thisWeekStart }
            .reduce(0.0) { $0 + Double($1.amount) / 100.0 }

        return WeeklyComparison(thisWeek: thisWeek, lastWeek: lastWeek)
    }

    // MARK: - Account snapshots

    private static func buildAccountSnapshots(accounts: [Account]) -> [AccountSnapshot] {
        accounts
            .filter { !$0.isArchived }
            .map {
                AccountSnapshot(
                    name: $0.name,
                    balance: $0.currentBalance,
                    isLiability: $0.type.isLiability,
                    iconName: $0.type.iconName
                )
            }
    }

    // MARK: - AISubscription pressure

    private static func buildSubscriptionPressure(store: Store, now: Date) -> SubscriptionPressure? {
        let active = store.aiSubscriptions.filter { $0.status == .active || $0.status == .trial }
        guard !active.isEmpty else { return nil }
        let monthlyTotal = active.reduce(0.0) { $0 + Double($1.monthlyCost) / 100.0 }
        // Unused heuristic: active ≥60 days with no edits — mirrors the
        // notification scheduler's "unused" rule.
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: now) ?? now
        let unusedCount = active.filter { $0.createdAt < cutoff && $0.updatedAt < cutoff }.count
        return SubscriptionPressure(monthlyTotal: monthlyTotal, count: active.count, unusedCount: unusedCount)
    }

    // MARK: - Emotional spending profile

    private static func buildEmotionalProfile(transactions: [RecentTransaction]) -> EmotionalSpendingProfile {
        let lateNight = transactions.filter { $0.hourOfDay >= 22 || $0.hourOfDay < 4 }
        let weekend = transactions.filter { $0.isWeekend }

        var hourCounts: [Int: Int] = [:]
        var dayCounts: [String: Int] = [:]
        for tx in transactions {
            hourCounts[tx.hourOfDay, default: 0] += 1
            dayCounts[tx.dayOfWeek, default: 0] += 1
        }

        return EmotionalSpendingProfile(
            lateNightCount: lateNight.count,
            lateNightTotal: lateNight.reduce(0.0) { $0 + $1.amount },
            weekendCount: weekend.count,
            weekendTotal: weekend.reduce(0.0) { $0 + $1.amount },
            topHour: hourCounts.max(by: { $0.value < $1.value })?.key,
            topDayOfWeek: dayCounts.max(by: { $0.value < $1.value })?.key,
            burstDays: []
        )
    }

    // MARK: - Monthly overview

    private static func buildMonthlyOverview(
        store: Store,
        rangeStart: Date,
        currentMonthStart: Date,
        currentMonthSpent: Double,
        currentMonthProjected: Double,
        currentMonthIncome: Double,
        expectedMonthIncome: Double,
        cal: Calendar
    ) -> [MonthlySpendingData] {
        var out: [MonthlySpendingData] = []
        var cursor = rangeStart
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        while cursor <= currentMonthStart {
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: cursor)) ?? cursor
            let nextStart = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            let isCurrent = cal.isDate(monthStart, equalTo: currentMonthStart, toGranularity: .month)

            let monthTxns = store.transactions.filter { $0.date >= monthStart && $0.date < nextStart }
            let actual: Double
            let income: Double
            let forecastValue: Double
            if isCurrent {
                actual = currentMonthSpent
                income = currentMonthIncome + expectedMonthIncome
                forecastValue = currentMonthProjected
            } else {
                actual = monthTxns.filter { $0.type == .expense }.reduce(0.0) { $0 + Double($1.amount) / 100.0 }
                income = monthTxns.filter { $0.type == .income }.reduce(0.0) { $0 + Double($1.amount) / 100.0 }
                forecastValue = 0
            }

            out.append(MonthlySpendingData(
                monthStart: monthStart,
                label: formatter.string(from: monthStart),
                actual: actual,
                forecast: forecastValue,
                income: income
            ))
            cursor = nextStart
        }
        return out
    }

    // MARK: - Quick rule-based insights

    private static func generateInsights(forecast: MonthForecast, categories: [CategoryProjection]) -> [String] {
        var out: [String] = []
        if forecast.totalBudget > 0 && forecast.projectedSpending > forecast.totalBudget {
            let over = forecast.projectedSpending - forecast.totalBudget
            out.append(String(format: "Projected to overrun budget by $%.0f", over))
        }
        if let over = categories.first(where: { $0.isOverBudget }) {
            out.append("\(over.name) on pace to exceed its budget")
        }
        if forecast.surplus < 0 {
            out.append("Projected spending exceeds income this month")
        }
        return out
    }

    // MARK: - Helpers

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }
}
