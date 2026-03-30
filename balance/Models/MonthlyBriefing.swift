import Foundation

// ============================================================
// MARK: - Monthly Briefing Model
// ============================================================
// The output of BriefingEngine: a structured, personalized
// financial summary synthesizing all 4 engines (Forecast,
// Review, Subscription, Household).
//
// Template-driven — no AI/LLM. Each section is conditionally
// populated based on available data.
// ============================================================

struct MonthlyBriefing: Identifiable {
    let id = UUID()
    let monthKey: String                   // YYYY-MM
    let generatedAt: Date

    // Sections (nil = section omitted)
    let overview: OverviewSection
    let spending: SpendingSection?
    let forecast: ForecastSection?
    let subscriptions: SubscriptionSection?
    let review: ReviewSection?
    let goals: GoalSection?
    let household: HouseholdSection?
    let healthScore: Int?                  // 0-100 (nil until P3-F7)

    var monthDisplayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return monthKey }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return monthKey }
        return formatter.string(from: date)
    }
}

// MARK: - Sections

struct OverviewSection {
    let headline: String                   // "You spent €1,234 in March"
    let subheadline: String                // "That's 12% below your average"
    let budgetTotal: Int                   // cents
    let totalSpent: Int                    // cents
    let totalIncome: Int                   // cents
    let remaining: Int                     // cents
    let spentRatio: Double                 // 0.0 – 1.0+
    let vsAverage: ComparisonResult?       // vs 3-month average
}

struct SpendingSection {
    let topCategories: [(category: String, amount: Int, percent: Double)]
    let concentrationWarning: String?      // "62% of spending in Groceries"
    let smallExpenseAlert: String?         // "14 small purchases added up to €89"
    let dailyAverage: Int                  // cents
}

struct ForecastSection {
    let safeToSpendTotal: Int              // cents
    let safeToSpendPerDay: Int             // cents
    let riskLevel: String                  // "safe" / "caution" / "highRisk"
    let riskSummary: String?               // urgent risk text if any
    let projected30Day: Int
    let projectedMonthEnd: Int
    let upcomingBillCount: Int
    let overdueBillCount: Int
    let dataConfidence: String             // "high" / "medium" / "low"
}

struct SubscriptionSection {
    let activeCount: Int
    let monthlyTotal: Int                  // cents
    let unusedCount: Int
    let potentialSavings: Int              // cents/month
    let priceIncreaseCount: Int
    let renewingSoonCount: Int
    let headline: String                   // "3 subscriptions may be unused"
}

struct ReviewSection {
    let pendingCount: Int
    let highPriorityCount: Int
    let duplicateCount: Int
    let uncategorizedCount: Int
    let headline: String                   // "5 transactions need review"
}

struct GoalSection {
    let activeGoalCount: Int
    let totalProgress: Double              // 0.0 – 1.0
    let behindCount: Int
    let headline: String                   // "2 goals on track, 1 behind"
    let topGoalName: String?
    let topGoalProgress: Double?
}

struct HouseholdSection {
    let partnerName: String
    let sharedSpending: Int                // cents this month
    let sharedBudget: Int                  // cents
    let netBalance: Int                    // cents (positive = they owe you)
    let unsettledCount: Int
    let headline: String                   // "You and Alex spent €456 together"
}

// MARK: - Helpers

struct ComparisonResult {
    let avgAmount: Int                     // 3-month average in cents
    let delta: Int                         // current - average
    let percentChange: Double              // -0.12 = 12% below
    let direction: Direction

    enum Direction {
        case above
        case below
        case equal
    }
}
