import Foundation

// ============================================================
// MARK: - Monthly Briefing Model
// ============================================================
// Data-driven shape: a briefing is an ordered list of sections.
// The engine decides which sections appear and in what order
// based on what's relevant this month. The view just iterates.
//
// Adding a new section = add a Kind case + one switch arm in
// the view. No new optional struct fields, no view-side ordering.
//
// Template-driven (no LLM). Typed payloads, not stringly-typed.
// ============================================================

struct MonthlyBriefing: Identifiable {
    let id = UUID()
    let monthKey: String                // YYYY-MM (anchored to store.selectedMonth)
    let generatedAt: Date
    let sections: [BriefingSection]

    var monthDisplayName: String {
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return monthKey }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return monthKey }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Section

struct BriefingSection: Identifiable {
    let id = UUID()
    let kind: Kind
    let confidence: Confidence

    enum Confidence {
        case high       // enough data, recent, trustworthy
        case medium     // partial data or short history
        case low        // very little data — show with caveat
    }

    enum Kind {
        case overview(OverviewPayload)
        case spending(SpendingPayload)
        case forecast(ForecastPayload)
        case subscriptions(SubscriptionPayload)
        case review(ReviewPayload)
        case goals(GoalPayload)
        case household(HouseholdPayload)
    }
}

// MARK: - Payloads

struct OverviewPayload {
    let headline: String                // "You spent €1,234 in March"
    let subheadline: String             // "That's 12% below your average"
    let budgetTotal: Int                // cents
    let totalSpent: Int                 // cents
    let totalIncome: Int                // cents
    let remaining: Int                  // cents
    let spentRatio: Double              // 0.0 – 1.0+
    let vsAverage: ComparisonResult?    // vs 3-month average
}

struct SpendingPayload {
    let topCategories: [CategoryRow]
    let concentrationWarning: String?   // "62% of spending in Groceries"
    let smallExpenseAlert: String?      // "14 small purchases added up to €89"
    let dailyAverage: Int               // cents

    struct CategoryRow {
        let category: String
        let amount: Int                 // cents
        let percent: Double             // 0.0 – 1.0
    }
}

struct ForecastPayload {
    let safeToSpendTotal: Int           // cents
    let safeToSpendPerDay: Int          // cents
    let riskLevel: RiskLevel
    let riskSummary: String?            // urgent risk text if any
    let projectedMonthEnd: Int          // cents
    let upcomingBillCount: Int
    let overdueBillCount: Int

    enum RiskLevel {
        case safe
        case caution
        case highRisk
    }
}

struct SubscriptionPayload {
    let activeCount: Int
    let monthlyTotal: Int               // cents
    let unusedCount: Int
    let potentialSavings: Int           // cents/month
    let priceIncreaseCount: Int
    let renewingSoonCount: Int
    let headline: String
}

struct ReviewPayload {
    let pendingCount: Int
    let highPriorityCount: Int
    let duplicateCount: Int
    let uncategorizedCount: Int
    let headline: String
}

struct GoalPayload {
    let activeGoalCount: Int
    let totalProgress: Double           // 0.0 – 1.0
    let behindCount: Int
    let headline: String
    let topGoalName: String?
    let topGoalProgress: Double?
}

struct HouseholdPayload {
    let partnerName: String
    let sharedSpending: Int             // cents this month
    let sharedBudget: Int               // cents (0 = not set)
    let netBalance: Int                 // cents (positive = they owe you)
    let unsettledCount: Int
    let headline: String
}

// MARK: - Helpers

struct ComparisonResult {
    let avgAmount: Int                  // 3-month average in cents
    let delta: Int                      // current - average
    let percentChange: Double           // -0.12 = 12% below
    let direction: Direction

    enum Direction {
        case above
        case below
        case equal
    }
}
