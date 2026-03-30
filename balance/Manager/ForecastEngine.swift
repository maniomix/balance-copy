import Foundation
import SwiftUI
import Combine

// ============================================================
// MARK: - Forecast Engine
// ============================================================
//
// Deterministic, transparent forecasting for personal finance.
//
// IMPORTANT — base metric semantics:
// All projections are BUDGET-BASED, NOT cash/account-balance-based.
// The engine does NOT read real account balances from AccountManager.
// "Remaining" means (budget + income - spending), not money-in-bank.
//
// Inputs:
//   - Monthly budget (user-set, or fallback to avg income)
//   - Recurring transactions (upcoming bills/subscriptions)
//   - Historical spending trends (3-month average)
//   - Historical income (3-month average)
//   - Active goal contributions
//
// Outputs:
//   - Projected budget remaining at end-of-month and 30/60/90 day horizons
//   - Safe-to-spend amount (budget remaining minus reserved obligations)
//   - Risk level (safe / caution / high risk)
//   - Day-by-day budget-remaining timeline
//
// All amounts are in cents (Int) for precision.
// ============================================================

@MainActor
class ForecastEngine: ObservableObject {

    static let shared = ForecastEngine()

    @Published var forecast: ForecastResult?
    @Published var isLoading = false

    private init() {}

    // MARK: - Main Calculation

    /// Generate a complete forecast from current app state.
    /// Call this whenever data changes (transactions, budgets, recurring transactions).
    func generate(store: Store) async {
        isLoading = true

        // Read goal data on MainActor before detaching to background
        let activeGoals = GoalManager.shared.activeGoals

        let result = await Task.detached(priority: .userInitiated) {
            Self.compute(store: store, activeGoals: activeGoals)
        }.value

        self.forecast = result
        isLoading = false
    }

    // MARK: - Pure Computation (off main thread)

    /// All calculations happen here. Pure function, no side effects.
    /// activeGoals is passed in to avoid @MainActor access from background.
    /// Uses store.selectedMonth as the reference month so results change
    /// when the user navigates between months.
    nonisolated static func compute(store: Store, activeGoals: [Goal]) -> ForecastResult {
        let cal = Calendar.current
        let realToday = Date()
        let selectedMonth = store.selectedMonth

        // Is the selected month the current real month?
        let isCurrentMonth = cal.isDate(realToday, equalTo: selectedMonth, toGranularity: .month)
        // Is the selected month in the past?
        let isPastMonth: Bool = {
            let selComps = cal.dateComponents([.year, .month], from: selectedMonth)
            let nowComps = cal.dateComponents([.year, .month], from: realToday)
            if let sy = selComps.year, let sm = selComps.month,
               let ny = nowComps.year, let nm = nowComps.month {
                return (sy * 12 + sm) < (ny * 12 + nm)
            }
            return false
        }()

        // Reference date: for current month use today, for past month use end of that month,
        // for future month use start of that month
        let referenceDate: Date
        if isCurrentMonth {
            referenceDate = realToday
        } else if isPastMonth {
            // Last day of the selected month
            let startOfNextMonth = cal.date(byAdding: .month, value: 1,
                to: cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!)!
            referenceDate = cal.date(byAdding: .day, value: -1, to: startOfNextMonth)!
        } else {
            // Future month: first day of that month
            referenceDate = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!
        }

        // ─── Step 1: Gather historical data (3 months before the selected month) ───

        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!
        let threeMonthsAgo = cal.date(byAdding: .month, value: -3, to: monthStart)!
        let pastTransactions = store.transactions.filter { $0.date < monthStart && $0.date >= threeMonthsAgo }

        let monthsOfData = countDistinctMonths(transactions: pastTransactions, cal: cal)
        let divisor = max(1, monthsOfData)

        let totalExpenses3m = pastTransactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }

        let totalIncome3m = pastTransactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amount }

        let avgMonthlyExpense = totalExpenses3m / divisor
        let avgMonthlyIncome = totalIncome3m / divisor

        // Average daily expense (for projection)
        let avgDailyExpense = avgMonthlyExpense / 30

        // ─── Step 2: Selected month state ───

        let selectedMonthTx = store.transactions.filter {
            cal.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
        }

        let spentThisMonth = selectedMonthTx
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }

        let incomeThisMonth = selectedMonthTx
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amount }

        let daysInMonth = cal.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30

        // Day of month and days remaining depend on whether this is current/past/future
        let dayOfMonth: Int
        let daysRemaining: Int

        if isCurrentMonth {
            dayOfMonth = cal.component(.day, from: realToday)
            daysRemaining = max(0, daysInMonth - dayOfMonth)
        } else if isPastMonth {
            // Past month: fully elapsed
            dayOfMonth = daysInMonth
            daysRemaining = 0
        } else {
            // Future month: nothing elapsed yet
            dayOfMonth = 0
            daysRemaining = daysInMonth
        }

        // Daily average spend (actual)
        let actualDailySpend = dayOfMonth > 0 ? spentThisMonth / dayOfMonth : 0

        // Use actual pace if we have enough data (7+ days in current month), else historical
        let projectionDailyRate: Int
        if isCurrentMonth && dayOfMonth >= 7 {
            projectionDailyRate = actualDailySpend
        } else {
            projectionDailyRate = avgDailyExpense
        }

        // ─── Step 3: Recurring transactions forecast ───

        let recurringExpenses = computeRecurringExpenses(
            recurring: store.recurringTransactions,
            from: referenceDate,
            days: 90,
            cal: cal
        )

        let monthlyRecurringExpense = recurringExpenses.monthly
        let next30Recurring = recurringExpenses.next30
        let next60Recurring = recurringExpenses.next60
        let next90Recurring = recurringExpenses.next90
        let upcomingBills = recurringExpenses.upcoming

        // ─── Step 4: Goal contributions ───

        let monthlyGoalContributions = activeGoals.compactMap { goal -> Int? in
            goal.requiredMonthlySaving
        }.reduce(0, +)

        // ─── Step 5: Budget for selected month ───

        let rawBudget = store.budget(for: selectedMonth)

        // If no budget is set (0), fall back to average monthly income as a reasonable ceiling.
        // This prevents safe-to-spend from showing 0 when user hasn't configured a budget.
        let budget: Int
        let budgetIsMissing: Bool
        if rawBudget > 0 {
            budget = rawBudget
            budgetIsMissing = false
        } else if avgMonthlyIncome > 0 {
            budget = avgMonthlyIncome
            budgetIsMissing = true
        } else {
            budget = incomeThisMonth > 0 ? incomeThisMonth : 0
            budgetIsMissing = true
        }

        // ─── Step 5b: Projected end-of-month budget remaining ───

        let projectedMonthSpend: Int
        if isPastMonth {
            // Past month: actual spending IS the total
            projectedMonthSpend = spentThisMonth
        } else {
            projectedMonthSpend = spentThisMonth + (projectionDailyRate * daysRemaining)
        }
        let projectedMonthEnd = budget + incomeThisMonth - projectedMonthSpend

        // ─── Step 6: 30/60/90 day projections ───

        let monthlyNet = avgMonthlyIncome - avgMonthlyExpense - monthlyGoalContributions
        let currentRemaining = budget + incomeThisMonth - spentThisMonth

        let proj30: Int
        let proj60: Int
        let proj90: Int

        if isPastMonth {
            // Past month: no future projections, show actuals
            proj30 = currentRemaining
            proj60 = currentRemaining
            proj90 = currentRemaining
        } else {
            // Note: projectionDailyRate already embeds recurring charges from historical
            // transaction data, so we do NOT subtract next30Recurring separately to avoid
            // double-counting. Recurring expenses are implicit in the daily spending rate.
            let daysInto30 = max(0, 30 - daysRemaining)
            proj30 = currentRemaining
                - (projectionDailyRate * daysRemaining)
                - (avgDailyExpense * daysInto30)
                + (avgMonthlyIncome * daysInto30 / 30)
                + (daysRemaining > 0 ? 0 : avgMonthlyIncome)

            proj60 = proj30 + monthlyNet
            proj90 = proj60 + monthlyNet
        }

        // ─── Step 7: Safe to spend ───

        // Detect overdue bills (due before today but still in upcoming list)
        let overdueBillCount = upcomingBills.filter { $0.dueDate < realToday }.count

        // Filter bills to month-end for safe-to-spend calculation.
        // upcomingBills spans a 30-day rolling window which may cross into next month,
        // but safe-to-spend is labeled "this month" so only reserve bills due this month.
        let monthEnd = cal.date(byAdding: .day, value: -1,
            to: cal.date(byAdding: .month, value: 1, to: monthStart)!)!
        let billsDueThisMonth = upcomingBills.filter { $0.dueDate <= monthEnd }

        let safeToSpend = computeSafeToSpend(
            currentRemaining: currentRemaining,
            daysRemaining: daysRemaining,
            upcomingBills: billsDueThisMonth,
            monthlyGoalContributions: monthlyGoalContributions,
            budget: budget,
            budgetIsMissing: budgetIsMissing
        )

        // ─── Step 8: Risk level (with hysteresis for stability) ───

        let riskLevel = computeRiskLevel(
            safeToSpend: safeToSpend,
            projectedMonthEnd: projectedMonthEnd,
            budget: budget,
            spentRatio: budget > 0 ? Double(spentThisMonth) / Double(budget) : 0,
            dayRatio: daysInMonth > 0 ? Double(dayOfMonth) / Double(daysInMonth) : 0,
            currentRemaining: currentRemaining,
            overdueBillCount: overdueBillCount
        )

        // ─── Step 9: Timeline (daily projections for chart) ───

        let timeline: [ForecastPoint]
        if isPastMonth {
            // Past month: build timeline from actual daily spending
            timeline = computePastTimeline(
                transactions: selectedMonthTx,
                budget: budget,
                incomeThisMonth: incomeThisMonth,
                selectedMonth: selectedMonth,
                cal: cal
            )
        } else {
            timeline = computeTimeline(
                startBalance: currentRemaining,
                dailyExpense: projectionDailyRate,
                avgDailyIncome: avgMonthlyIncome / 30,
                recurring: store.recurringTransactions,
                days: isCurrentMonth ? 30 : daysInMonth,
                startDate: referenceDate,
                cal: cal
            )
        }

        // ─── Step 10: Spending breakdown ───

        let spendingByCategory = computeCategoryBreakdown(
            transactions: selectedMonthTx.filter { $0.type == .expense }
        )

        // ─── Compute data confidence ───
        let dataConfidence: DataConfidence
        if monthsOfData >= 3 {
            dataConfidence = .high
        } else if monthsOfData >= 1 {
            dataConfidence = .medium
        } else {
            dataConfidence = .low
        }

        return ForecastResult(
            // Current state
            spentThisMonth: spentThisMonth,
            incomeThisMonth: incomeThisMonth,
            budget: budget,
            budgetIsMissing: budgetIsMissing,
            currentRemaining: currentRemaining,
            daysRemainingInMonth: daysRemaining,
            dayOfMonth: dayOfMonth,
            daysInMonth: daysInMonth,

            // Averages
            avgMonthlyExpense: avgMonthlyExpense,
            avgMonthlyIncome: avgMonthlyIncome,
            avgDailyExpense: projectionDailyRate,
            monthsOfData: monthsOfData,

            // Recurring
            monthlyRecurringExpense: monthlyRecurringExpense,
            upcomingBills: upcomingBills,
            overdueBillCount: overdueBillCount,

            // Goals
            monthlyGoalContributions: monthlyGoalContributions,

            // Projections
            projectedMonthEnd: projectedMonthEnd,
            projected30Day: proj30,
            projected60Day: proj60,
            projected90Day: proj90,

            // Safe to spend
            safeToSpend: safeToSpend,
            riskLevel: riskLevel,

            // Data quality
            dataConfidence: dataConfidence,

            // Timeline
            timeline: timeline,

            // Breakdown
            topCategories: spendingByCategory,

            generatedAt: realToday
        )
    }

    // MARK: - Recurring Expenses Projection

    private struct RecurringForecast {
        let monthly: Int
        let next30: Int
        let next60: Int
        let next90: Int
        let upcoming: [UpcomingBill]
    }

    nonisolated private static func computeRecurringExpenses(
        recurring: [RecurringTransaction],
        from start: Date,
        days: Int,
        cal: Calendar
    ) -> RecurringForecast {

        let active = recurring.filter { $0.isActive }
        var total30 = 0
        var total60 = 0
        var total90 = 0
        var monthly = 0
        var bills: [UpcomingBill] = []

        let end30 = cal.date(byAdding: .day, value: 30, to: start)!
        let end60 = cal.date(byAdding: .day, value: 60, to: start)!
        let end90 = cal.date(byAdding: .day, value: 90, to: start)!

        for item in active {
            // Estimate monthly cost
            switch item.frequency {
            case .daily: monthly += item.amount * 30
            case .weekly: monthly += item.amount * 4
            case .monthly: monthly += item.amount
            case .yearly: monthly += item.amount / 12
            }

            // Project occurrences in each window
            var date = item.nextOccurrence(from: start) ?? start
            var count30 = 0
            var count60 = 0
            var count90 = 0

            while date <= end90 {
                if date <= end30 {
                    count30 += 1
                    // Track as upcoming bill
                    if bills.count < 20 && date <= end30 {
                        bills.append(UpcomingBill(
                            name: item.name,
                            amount: item.amount,
                            dueDate: date,
                            category: item.category,
                            isRecurring: true
                        ))
                    }
                }
                if date <= end60 { count60 += 1 }
                count90 += 1

                // Advance to next occurrence
                guard let next = advanceDate(date, frequency: item.frequency, cal: cal) else { break }
                if next <= date { break } // Safety: prevent infinite loop
                date = next
            }

            total30 += item.amount * count30
            total60 += item.amount * count60
            total90 += item.amount * count90
        }

        bills.sort { $0.dueDate < $1.dueDate }

        return RecurringForecast(
            monthly: monthly,
            next30: total30,
            next60: total60,
            next90: total90,
            upcoming: bills
        )
    }

    nonisolated private static func advanceDate(_ date: Date, frequency: RecurringFrequency, cal: Calendar) -> Date? {
        switch frequency {
        case .daily: return cal.date(byAdding: .day, value: 1, to: date)
        case .weekly: return cal.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly: return cal.date(byAdding: .month, value: 1, to: date)
        case .yearly: return cal.date(byAdding: .year, value: 1, to: date)
        }
    }

    // MARK: - Safe to Spend

    /// Safe to spend = what you can spend today without jeopardizing
    /// bills, goal contributions, or budget limits.
    ///
    /// Formula:
    ///   remaining_budget
    ///   - upcoming_bills_this_month
    ///   - remaining_goal_contributions_this_month
    ///   = safe_to_spend
    ///
    /// Then divide by days remaining to get daily safe amount.
    nonisolated static func computeSafeToSpend(
        currentRemaining: Int,
        daysRemaining: Int,
        upcomingBills: [UpcomingBill],
        monthlyGoalContributions: Int,
        budget: Int,
        budgetIsMissing: Bool
    ) -> SafeToSpend {

        // Sum of bills due within the selected month (pre-filtered by caller)
        let billsThisMonth = upcomingBills
            .reduce(0) { $0 + $1.amount }

        // Goal contributions remaining for this month (assume not yet contributed)
        let goalReserve = monthlyGoalContributions

        // Total amount — can go negative to show overcommitment clearly
        let rawSafe = currentRemaining - billsThisMonth - goalReserve
        let totalSafe = max(0, rawSafe)

        // Per day
        let perDay = daysRemaining > 0 ? totalSafe / daysRemaining : totalSafe

        // Detect if user is overcommitted (bills + goals exceed remaining)
        let isOvercommitted = rawSafe < 0

        return SafeToSpend(
            totalAmount: totalSafe,
            perDay: perDay,
            daysRemaining: daysRemaining,
            reservedForBills: billsThisMonth,
            reservedForGoals: goalReserve,
            budgetRemaining: currentRemaining,
            isOvercommitted: isOvercommitted,
            overcommitAmount: isOvercommitted ? abs(rawSafe) : 0,
            budgetIsMissing: budgetIsMissing
        )
    }

    // MARK: - Risk Level

    /// Determine risk level from multiple signals with scoring for stability.
    ///
    /// Uses a point-based system instead of hard thresholds to avoid
    /// the risk level flipping between states on small data changes.
    ///
    /// Score thresholds: 0-2 = SAFE, 3-5 = CAUTION, 6+ = HIGH RISK
    nonisolated private static func computeRiskLevel(
        safeToSpend: SafeToSpend,
        projectedMonthEnd: Int,
        budget: Int,
        spentRatio: Double,
        dayRatio: Double,
        currentRemaining: Int,
        overdueBillCount: Int
    ) -> RiskLevel {

        var riskScore = 0

        // Signal 1: Safe-to-spend exhausted (strong high-risk signal)
        if safeToSpend.totalAmount <= 0 {
            riskScore += 6
        } else if safeToSpend.isOvercommitted {
            riskScore += 4
        }

        // Signal 2: Projected to overshoot budget
        if projectedMonthEnd < 0 {
            riskScore += 4
        } else if budget > 0 && projectedMonthEnd < budget / 10 {
            riskScore += 2 // tight but not negative
        }

        // Signal 3: Spending pace vs time pace
        if spentRatio > 0 && dayRatio > 0.1 { // need at least ~3 days of data
            let paceRatio = spentRatio / dayRatio
            if paceRatio > 1.3 {
                riskScore += 4
            } else if paceRatio > 1.1 {
                riskScore += 2
            } else if paceRatio > 1.0 {
                riskScore += 1
            }
        }

        // Signal 4: Low safe-to-spend per day relative to budget
        if budget > 0 && safeToSpend.perDay > 0 && safeToSpend.perDay < budget / 20 {
            riskScore += 2
        }

        // Signal 5: Overdue bills present
        if overdueBillCount > 0 {
            riskScore += 2
        }

        // Signal 6: Already in negative remaining
        if currentRemaining < 0 {
            riskScore += 3
        }

        // Score to level
        if riskScore >= 6 { return .highRisk }
        if riskScore >= 3 { return .caution }
        return .safe
    }

    // MARK: - Timeline

    /// Daily budget-remaining projection for chart.
    /// NOTE: startBudgetRemaining is (budget + income - spent), NOT an account balance.
    nonisolated private static func computeTimeline(
        startBalance: Int,
        dailyExpense: Int,
        avgDailyIncome: Int,
        recurring: [RecurringTransaction],
        days: Int,
        startDate: Date,
        cal: Calendar
    ) -> [ForecastPoint] {

        var points: [ForecastPoint] = []
        var balance = startBalance

        for i in 0..<days {
            guard let date = cal.date(byAdding: .day, value: i, to: startDate) else { continue }

            // Check for recurring transaction on this day
            var recurringHit = 0
            for item in recurring where item.isActive {
                if let next = item.nextOccurrence(from: cal.date(byAdding: .day, value: -1, to: date)!) {
                    if cal.isDate(next, inSameDayAs: date) {
                        recurringHit += item.amount
                    }
                }
            }

            // Daily change: income - spending - recurring
            let dailyNet = avgDailyIncome - dailyExpense - recurringHit
            if i > 0 { balance += dailyNet }

            points.append(ForecastPoint(
                date: date,
                budgetRemaining: balance,
                dayIndex: i
            ))
        }

        return points
    }

    /// Build a timeline from actual transactions for a past (completed) month.
    /// Shows how budget remaining changed day by day based on real spending data.
    nonisolated private static func computePastTimeline(
        transactions: [Transaction],
        budget: Int,
        incomeThisMonth: Int,
        selectedMonth: Date,
        cal: Calendar
    ) -> [ForecastPoint] {
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!
        let daysInMonth = cal.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30

        // Group spending by day
        var dailyExpense: [Int: Int] = [:]   // day number -> total expense
        var dailyIncome: [Int: Int] = [:]    // day number -> total income
        for tx in transactions {
            let day = cal.component(.day, from: tx.date)
            if tx.type == .expense {
                dailyExpense[day, default: 0] += tx.amount
            } else {
                dailyIncome[day, default: 0] += tx.amount
            }
        }

        var points: [ForecastPoint] = []
        var balance = budget + incomeThisMonth // start with full budget
        // Actually compute running balance: budget - cumulative spending + cumulative income
        var cumulativeSpent = 0
        var cumulativeIncome = 0

        for day in 1...daysInMonth {
            cumulativeSpent += dailyExpense[day] ?? 0
            cumulativeIncome += dailyIncome[day] ?? 0
            balance = budget + cumulativeIncome - cumulativeSpent

            guard let date = cal.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            points.append(ForecastPoint(
                date: date,
                budgetRemaining: balance,
                dayIndex: day - 1
            ))
        }

        return points
    }

    // MARK: - Category Breakdown

    nonisolated private static func computeCategoryBreakdown(transactions: [Transaction]) -> [CategorySpend] {
        var byCategory: [String: Int] = [:]

        for tx in transactions {
            let key = tx.category.title
            byCategory[key, default: 0] += tx.amount
        }

        let total = max(1, transactions.reduce(0) { $0 + $1.amount })

        return byCategory
            .map { CategorySpend(name: $0.key, amount: $0.value, percentage: Double($0.value) / Double(total)) }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Helpers

    nonisolated private static func countDistinctMonths(transactions: [Transaction], cal: Calendar) -> Int {
        var months = Set<String>()
        for tx in transactions {
            let y = cal.component(.year, from: tx.date)
            let m = cal.component(.month, from: tx.date)
            months.insert("\(y)-\(m)")
        }
        return months.count
    }
}

// ============================================================
// MARK: - Data Models
// ============================================================

/// All projection values are BUDGET-BASED (budget + income - spending).
/// They do NOT represent real account/cash balances.
struct ForecastResult {
    // Current state
    let spentThisMonth: Int
    let incomeThisMonth: Int
    let budget: Int
    let budgetIsMissing: Bool
    /// Budget remaining = budget + incomeThisMonth - spentThisMonth.
    /// This is NOT a bank/account balance.
    let currentRemaining: Int
    let daysRemainingInMonth: Int
    let dayOfMonth: Int
    let daysInMonth: Int

    // Historical averages
    let avgMonthlyExpense: Int
    let avgMonthlyIncome: Int
    let avgDailyExpense: Int
    let monthsOfData: Int

    // Recurring
    let monthlyRecurringExpense: Int
    let upcomingBills: [UpcomingBill]
    let overdueBillCount: Int

    // Goals
    let monthlyGoalContributions: Int

    // Budget-based projections (NOT account balance projections)
    /// Projected budget remaining at end of the selected month.
    let projectedMonthEnd: Int
    /// Projected budget remaining 30 days out.
    let projected30Day: Int
    /// Projected budget remaining 60 days out.
    let projected60Day: Int
    /// Projected budget remaining 90 days out.
    let projected90Day: Int

    // Safe to spend
    let safeToSpend: SafeToSpend
    let riskLevel: RiskLevel

    // Data quality
    let dataConfidence: DataConfidence

    // Timeline — daily budget-remaining projection for chart
    let timeline: [ForecastPoint]

    // Top spending categories
    let topCategories: [CategorySpend]

    let generatedAt: Date

    // Convenience
    var monthProgressRatio: Double {
        guard daysInMonth > 0 else { return 0 }
        return Double(dayOfMonth) / Double(daysInMonth)
    }

    var spentRatio: Double {
        guard budget > 0 else { return 0 }
        return Double(spentThisMonth) / Double(budget)
    }

    /// The most urgent risk to surface on the dashboard
    var urgentRiskSummary: String? {
        if safeToSpend.isOvercommitted {
            return "Over-committed by \(DS.Format.money(safeToSpend.overcommitAmount)) — bills + goals exceed budget"
        }
        if currentRemaining < 0 {
            return "Over budget by \(DS.Format.money(abs(currentRemaining)))"
        }
        if overdueBillCount > 0 {
            return "\(overdueBillCount) overdue bill\(overdueBillCount == 1 ? "" : "s") need attention"
        }
        if riskLevel == .highRisk && projected30Day < 0 {
            return "30-day projection is negative — reduce spending"
        }
        if budgetIsMissing {
            return "No budget set — safe-to-spend is estimated from income"
        }
        return nil
    }
}

struct SafeToSpend {
    let totalAmount: Int      // Total you can safely spend
    let perDay: Int           // Daily safe amount
    let daysRemaining: Int
    let reservedForBills: Int
    let reservedForGoals: Int
    let budgetRemaining: Int
    let isOvercommitted: Bool   // bills + goals exceed remaining
    let overcommitAmount: Int   // how much over (0 if not overcommitted)
    let budgetIsMissing: Bool   // budget was estimated, not user-set
}

enum DataConfidence {
    case high      // 3+ months of history
    case medium    // 1-2 months of history
    case low       // no history, projections unreliable

    var label: String {
        switch self {
        case .high: return "High confidence"
        case .medium: return "Moderate confidence"
        case .low: return "Limited data"
        }
    }

    var icon: String {
        switch self {
        case .high: return "checkmark.circle"
        case .medium: return "circle.lefthalf.filled"
        case .low: return "exclamationmark.circle"
        }
    }
}

struct UpcomingBill: Identifiable {
    let id = UUID()
    let name: String
    let amount: Int
    let dueDate: Date
    let category: Category
    let isRecurring: Bool
}

struct ForecastPoint: Identifiable {
    let id = UUID()
    let date: Date
    /// Budget remaining projected for this day. NOT an account balance.
    let budgetRemaining: Int
    let dayIndex: Int
}

struct CategorySpend: Identifiable {
    let id = UUID()
    let name: String
    let amount: Int
    let percentage: Double
}

enum RiskLevel {
    case safe, caution, highRisk

    var label: String {
        switch self {
        case .safe: return "Safe"
        case .caution: return "Caution"
        case .highRisk: return "High Risk"
        }
    }

    var icon: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .highRisk: return "xmark.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .safe: return DS.Colors.positive
        case .caution: return DS.Colors.warning
        case .highRisk: return DS.Colors.danger
        }
    }
}

// ============================================================
// MARK: - Household Forecast
// ============================================================
//
// Combines individual forecasts with household shared data
// to produce a unified "Our Finances" view.
//
// ============================================================

struct HouseholdForecastResult {
    let myForecast: ForecastResult
    let combinedSafeToSpend: Int              // my safe + shared budget remaining
    let combinedSafePerDay: Int
    let sharedBudgetTotal: Int                // household shared budget
    let sharedSpentThisMonth: Int             // total shared spending
    let sharedRemaining: Int                  // shared budget - shared spent
    let myContributionRatio: Double           // 0.0 – 1.0 (my share of shared expenses)
    let sharedBillsThisMonth: Int             // shared recurring costs
    let sharedGoalContributions: Int          // reserved for shared goals
    let combinedRiskLevel: RiskLevel          // worst of individual + shared
    let partnerName: String
}

extension ForecastEngine {

    /// Generate a household-aware forecast combining personal and shared finances.
    @MainActor
    func computeHousehold(store: Store) -> HouseholdForecastResult? {
        guard let myForecast = forecast else { return nil }

        let hm = HouseholdManager.shared
        guard let household = hm.household, household.partner != nil else { return nil }

        let cal = Calendar.current
        let y = cal.component(.year, from: store.selectedMonth)
        let m = cal.component(.month, from: store.selectedMonth)
        let monthKey = String(format: "%04d-%02d", y, m)
        let userId = household.createdBy // current user

        // Shared budget for this month
        let sharedBudget = hm.sharedBudget(for: monthKey)
        let sharedBudgetTotal = sharedBudget?.totalAmount ?? 0

        // Shared spending this month
        let monthSplits = hm.splitExpenses.filter { expense in
            let expMonth = cal.component(.month, from: expense.date)
            let expYear = cal.component(.year, from: expense.date)
            return expMonth == m && expYear == y
        }
        let sharedSpentThisMonth = monthSplits.reduce(0) { $0 + $1.amount }
        let sharedRemaining = max(0, sharedBudgetTotal - sharedSpentThisMonth)

        // My contribution ratio (what % of shared expenses I paid)
        let myPaidAmount = monthSplits
            .filter { $0.paidBy.lowercased() == userId.lowercased() }
            .reduce(0) { $0 + $1.amount }
        let myContributionRatio = sharedSpentThisMonth > 0
            ? Double(myPaidAmount) / Double(sharedSpentThisMonth)
            : 0.5

        // Shared goals contribution
        let sharedGoalContributions = hm.sharedGoals
            .filter { !$0.isCompleted }
            .reduce(0) { total, goal in
                let monthly = goal.targetAmount > 0
                    ? goal.remainingAmount / max(1, 6)  // estimate 6-month horizon
                    : 0
                return total + monthly
            }

        // Combined safe-to-spend: my personal + my share of shared remaining
        let myShareOfShared = Int(Double(sharedRemaining) * myContributionRatio)
        let combinedSafe = myForecast.safeToSpend.totalAmount + myShareOfShared
        let combinedPerDay = myForecast.daysRemainingInMonth > 0
            ? combinedSafe / myForecast.daysRemainingInMonth
            : 0

        // Combined risk: worst of personal risk and shared budget pressure
        let sharedRisk: RiskLevel
        if sharedBudgetTotal > 0 {
            let sharedRatio = Double(sharedSpentThisMonth) / Double(sharedBudgetTotal)
            if sharedRatio >= 1.0 { sharedRisk = .highRisk }
            else if sharedRatio >= 0.8 { sharedRisk = .caution }
            else { sharedRisk = .safe }
        } else {
            sharedRisk = .safe
        }
        let combinedRisk: RiskLevel = {
            let severity: (RiskLevel) -> Int = { level in
                switch level {
                case .safe: return 0
                case .caution: return 1
                case .highRisk: return 2
                }
            }
            return severity(myForecast.riskLevel) >= severity(sharedRisk)
                ? myForecast.riskLevel
                : sharedRisk
        }()

        return HouseholdForecastResult(
            myForecast: myForecast,
            combinedSafeToSpend: combinedSafe,
            combinedSafePerDay: combinedPerDay,
            sharedBudgetTotal: sharedBudgetTotal,
            sharedSpentThisMonth: sharedSpentThisMonth,
            sharedRemaining: sharedRemaining,
            myContributionRatio: myContributionRatio,
            sharedBillsThisMonth: 0,  // TODO: compute from shared recurring transactions
            sharedGoalContributions: sharedGoalContributions,
            combinedRiskLevel: combinedRisk,
            partnerName: household.partner?.displayName ?? "Partner"
        )
    }
}
