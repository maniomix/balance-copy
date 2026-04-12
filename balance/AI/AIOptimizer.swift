import Foundation
import Combine

// ============================================================
// MARK: - AI Optimization Layer (Phase 8)
// ============================================================
//
// Financial optimization engine that turns raw data into
// practical, explainable recommendations and plans.
//
// Builds on existing engines:
//   • AISafeToSpend — daily/weekly allowances, affordability
//   • AIBudgetRescue — 80% threshold activation, reduction targets
//   • SubscriptionEngine — recurring detection, unused/overpriced
//   • GoalManager — savings pace, deadlines, behind/overdue
//   • AccountManager — balances, net worth, liabilities
//
// Adds:
//   • Budget reallocation optimizer
//   • Goal catch-up planner
//   • Subscription cleanup ranker
//   • Lean month / paycheck allocator
//   • Tradeoff comparison engine
//   • Unified optimization result model
//
// ============================================================

// ══════════════════════════════════════════════════════════════
// MARK: - Optimization Model
// ══════════════════════════════════════════════════════════════

/// Kind of optimization.
enum OptimizationType: String, Codable, CaseIterable {
    case safeToSpend           = "safe_to_spend"
    case budgetRescue          = "budget_rescue"
    case budgetReallocation    = "budget_reallocation"
    case goalCatchUp           = "goal_catch_up"
    case subscriptionCleanup   = "subscription_cleanup"
    case leanMonthPlan         = "lean_month_plan"
    case paycheckAllocation    = "paycheck_allocation"
    case spendingFreeze        = "spending_freeze"
    case tradeoffComparison    = "tradeoff_comparison"

    var title: String {
        switch self {
        case .safeToSpend:        return "Safe to Spend"
        case .budgetRescue:       return "Budget Rescue"
        case .budgetReallocation: return "Budget Reallocation"
        case .goalCatchUp:        return "Goal Catch-Up"
        case .subscriptionCleanup:return "Subscription Cleanup"
        case .leanMonthPlan:      return "Lean Month Plan"
        case .paycheckAllocation: return "Paycheck Allocation"
        case .spendingFreeze:     return "Spending Freeze"
        case .tradeoffComparison: return "Compare Options"
        }
    }

    var icon: String {
        switch self {
        case .safeToSpend:        return "shield.checkered"
        case .budgetRescue:       return "lifepreserver.fill"
        case .budgetReallocation: return "arrow.left.arrow.right"
        case .goalCatchUp:        return "target"
        case .subscriptionCleanup:return "repeat"
        case .leanMonthPlan:      return "leaf.fill"
        case .paycheckAllocation: return "banknote.fill"
        case .spendingFreeze:     return "snowflake"
        case .tradeoffComparison: return "scale.3d"
        }
    }
}

/// A single actionable recommendation inside an optimization.
struct OptimizationRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    var amountCents: Int?           // savings or allocation amount
    var categoryRef: String?        // category storage key
    var goalRef: String?            // goal name
    var subscriptionRef: String?    // subscription merchant
    var priority: Int               // lower = higher priority
    var impact: Impact              // how much this matters

    enum Impact: String {
        case high   = "high"
        case medium = "medium"
        case low    = "low"

        var icon: String {
            switch self {
            case .high:   return "exclamationmark.triangle.fill"
            case .medium: return "minus.circle.fill"
            case .low:    return "arrow.down.circle.fill"
            }
        }
    }
}

/// A scenario for tradeoff comparison.
struct OptimizationScenario: Identifiable {
    let id = UUID()
    let label: String
    let description: String
    var projectedSavings: Int       // cents saved over period
    var timelineWeeks: Int?         // weeks to achieve result
    var riskLevel: String           // "low", "moderate", "high"
    var impactedCategories: [String]
    var impactedGoals: [String]
    var pros: [String]
    var cons: [String]
}

/// The full result of an optimization run.
struct OptimizationResult: Identifiable {
    let id = UUID()
    let type: OptimizationType
    let title: String
    var summary: String
    var recommendations: [OptimizationRecommendation]
    var projectedSavings: Int?      // total projected savings in cents
    var projectedImpact: String?    // human-readable impact summary
    var confidence: Double          // 0.0–1.0
    var assumptions: [String]       // what we assumed to be true
    let createdAt: Date
    var scenarios: [OptimizationScenario] // for tradeoff comparisons
    var relatedCategories: [String]
    var relatedGoals: [String]
    var relatedSubscriptions: [String]
}

// ══════════════════════════════════════════════════════════════
// MARK: - Optimization Engine
// ══════════════════════════════════════════════════════════════

@MainActor
class AIOptimizer: ObservableObject {
    static let shared = AIOptimizer()

    @Published var latestResult: OptimizationResult?
    @Published private(set) var resultHistory: [OptimizationResult] = []

    private init() {}

    // Keep last N results for reference
    private let maxHistory = 10

    private func record(_ result: OptimizationResult) {
        // Phase 9: Apply mode emphasis before storing
        let emphasized = applyModeEmphasis(result)
        latestResult = emphasized
        resultHistory.insert(emphasized, at: 0)
        if resultHistory.count > maxHistory { resultHistory.removeLast() }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Phase 9: Mode-Aware Framing
    // ══════════════════════════════════════════════════════════

    /// Apply mode-based emphasis to an optimization result's summary.
    private func applyModeEmphasis(_ result: OptimizationResult) -> OptimizationResult {
        let emphasis = AIAssistantModeManager.shared.optimizationEmphasis
        guard emphasis != .moderate else { return result } // Default — no change

        var modified = result
        let prefix = emphasis.prefix
        if !prefix.isEmpty {
            modified.summary = "\(prefix) \(result.summary)"
        }

        // In optional mode, soften confidence
        if emphasis == .optional && modified.confidence > 0.7 {
            modified.confidence = modified.confidence * 0.85
        }
        // In strong mode, boost confidence for actionability
        if emphasis == .strong && modified.confidence < 0.9 {
            modified.confidence = min(1.0, modified.confidence * 1.1)
        }

        return modified
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Safe to Spend
    // ══════════════════════════════════════════════════════════

    func safeToSpend(store: Store) -> OptimizationResult {
        let sts = AISafeToSpend.shared.calculate(store: store)
        let cal = Calendar.current
        let now = Date()

        var recs: [OptimizationRecommendation] = []
        var assumptions: [String] = []

        let budget = store.budgetsByMonth[Store.monthKey(now)] ?? 0
        assumptions.append("Monthly budget: \(fmtCents(budget))")
        assumptions.append("Spending so far: \(fmtCents(store.spent(for: now)))")
        assumptions.append("Days remaining: \(sts.daysLeftInMonth)")

        // Core recommendation
        recs.append(OptimizationRecommendation(
            title: "Daily allowance: \(fmtCents(sts.trueAllowance))",
            detail: "Conservative estimate after reserving for goals and upcoming bills.",
            amountCents: sts.trueAllowance,
            priority: 0,
            impact: .high
        ))

        recs.append(OptimizationRecommendation(
            title: "Weekly budget: \(fmtCents(sts.weeklyAllowance))",
            detail: "\(fmtCents(sts.weeklyAllowance)) for the next \(min(7, sts.daysLeftInMonth)) days.",
            amountCents: sts.weeklyAllowance,
            priority: 1,
            impact: .medium
        ))

        // Upcoming bills warning
        let upcoming = SubscriptionEngine.shared.renewingWithin(days: 7)
        if !upcoming.isEmpty {
            let billTotal = upcoming.reduce(0) { $0 + $1.expectedAmount }
            recs.append(OptimizationRecommendation(
                title: "\(fmtCents(billTotal)) in bills this week",
                detail: "\(upcoming.count) subscription(s) renewing within 7 days.",
                amountCents: billTotal,
                priority: 2,
                impact: billTotal > sts.weeklyAllowance / 2 ? .high : .medium
            ))
            assumptions.append("Upcoming bills: \(fmtCents(billTotal))")
        }

        // Goal reserve
        if sts.goalReserve > 0 {
            recs.append(OptimizationRecommendation(
                title: "\(fmtCents(sts.goalReserve)) reserved for goals",
                detail: "Monthly savings needed to keep active goals on track.",
                amountCents: sts.goalReserve,
                priority: 3,
                impact: .medium
            ))
            assumptions.append("Goal reserve: \(fmtCents(sts.goalReserve))/month")
        }

        // Burn rate warning
        if !sts.isOnTrack {
            recs.append(OptimizationRecommendation(
                title: "Projected overspend: \(fmtCents(sts.projectedMonthEnd - budget))",
                detail: "At current pace (\(fmtCents(Int(sts.burnRate)))/day), you'll exceed budget by \(fmtCents(sts.projectedMonthEnd - budget)).",
                amountCents: sts.projectedMonthEnd - budget,
                priority: 0,
                impact: .high
            ))
        }

        // Survival days
        if sts.survivalDays < sts.daysLeftInMonth && sts.survivalDays > 0 {
            recs.append(OptimizationRecommendation(
                title: "Budget runs out in \(sts.survivalDays) days",
                detail: "At current spending rate, budget exhausts before month end.",
                priority: 0,
                impact: .high
            ))
        }

        let summary = sts.isOnTrack
            ? "You can safely spend \(fmtCents(sts.trueAllowance))/day (\(fmtCents(sts.weeklyAllowance))/week). You're on track."
            : "⚠️ Spending is ahead of pace. Safe daily limit: \(fmtCents(sts.trueAllowance)). Consider reducing discretionary spending."

        let result = OptimizationResult(
            type: .safeToSpend,
            title: "Safe to Spend",
            summary: summary,
            recommendations: recs.sorted { $0.priority < $1.priority },
            projectedSavings: nil,
            projectedImpact: sts.isOnTrack ? "On track to finish within budget" : "Risk of exceeding budget by \(fmtCents(sts.projectedMonthEnd - budget))",
            confidence: budget > 0 ? 0.8 : 0.5,
            assumptions: assumptions,
            createdAt: Date(),
            scenarios: [],
            relatedCategories: [],
            relatedGoals: [],
            relatedSubscriptions: upcoming.map(\.merchantName)
        )
        record(result)
        return result
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Budget Rescue & Reallocation
    // ══════════════════════════════════════════════════════════

    func budgetRescue(store: Store) -> OptimizationResult {
        let cal = Calendar.current
        let now = Date()
        let monthKey = Store.monthKey(now)
        let budget = store.budgetsByMonth[monthKey] ?? 0
        let spent = store.spent(for: now)
        let remaining = budget - spent
        let dayOfMonth = cal.component(.day, from: now)
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let daysLeft = max(1, daysInMonth - dayOfMonth)

        // Category spending breakdown
        let monthExpenses = store.transactions.filter {
            $0.type == .expense && cal.isDate($0.date, equalTo: now, toGranularity: .month)
        }
        var catSpending: [String: Int] = [:]
        for t in monthExpenses { catSpending[t.category.storageKey, default: 0] += t.amount }

        let essentialKeys = Set(["rent", "bills", "health", "transport", "groceries"])
        let discretionary = catSpending.filter { !essentialKeys.contains($0.key) }
            .sorted { $0.value > $1.value }

        var recs: [OptimizationRecommendation] = []
        var totalPotentialSavings = 0
        var assumptions: [String] = [
            "Budget: \(fmtCents(budget))",
            "Spent: \(fmtCents(spent)) (\(budget > 0 ? spent * 100 / budget : 0)%)",
            "Days left: \(daysLeft)"
        ]

        // Daily limit
        let dailyLimit = remaining > 0 ? remaining / daysLeft : 0
        recs.append(OptimizationRecommendation(
            title: "Strict daily limit: \(fmtCents(dailyLimit))",
            detail: "Maximum daily spending to stay within remaining budget.",
            amountCents: dailyLimit,
            priority: 0,
            impact: .high
        ))

        // Category reduction targets — suggest 30% cut on top discretionary
        for (idx, (catKey, amount)) in discretionary.prefix(4).enumerated() {
            let catName = Category(storageKey: catKey)?.title ?? catKey
            let reduction = amount * 30 / 100
            if reduction > 500 { // > $5 savings threshold
                totalPotentialSavings += reduction
                recs.append(OptimizationRecommendation(
                    title: "Reduce \(catName) by \(fmtCents(reduction))",
                    detail: "Currently \(fmtCents(amount)) this month. Cut ~30% for the rest of the month.",
                    amountCents: reduction,
                    categoryRef: catKey,
                    priority: idx + 1,
                    impact: reduction > 2000 ? .high : .medium
                ))
            }
        }

        // Essential spend summary
        let essentialTotal = catSpending.filter { essentialKeys.contains($0.key) }.values.reduce(0, +)
        if essentialTotal > 0 {
            recs.append(OptimizationRecommendation(
                title: "Essential spending: \(fmtCents(essentialTotal))",
                detail: "Rent, bills, health, groceries, transport — these are protected.",
                amountCents: essentialTotal,
                priority: 10,
                impact: .low
            ))
        }

        // Subscription savings
        let subSavings = SubscriptionEngine.shared.potentialMonthlySavings
        if subSavings > 0 {
            totalPotentialSavings += subSavings
            recs.append(OptimizationRecommendation(
                title: "Cancel unused subscriptions: \(fmtCents(subSavings))/mo",
                detail: "\(SubscriptionEngine.shared.unusedSubs.count) subscription(s) appear unused.",
                amountCents: subSavings,
                priority: 5,
                impact: subSavings > 2000 ? .high : .medium
            ))
        }

        // Goal contribution pause
        let goalReserve = computeGoalReserve()
        if goalReserve > 0 && remaining < 0 {
            recs.append(OptimizationRecommendation(
                title: "Pause goal contributions: frees \(fmtCents(goalReserve))/mo",
                detail: "Temporarily pause savings goals to recover budget. Resume next month.",
                amountCents: goalReserve,
                priority: 8,
                impact: goalReserve > 5000 ? .high : .medium
            ))
            totalPotentialSavings += goalReserve
        }

        let overBy = max(0, spent - budget)
        let severity = budget > 0 ? (spent > budget ? "over budget" : "\(spent * 100 / budget)% used") : "no budget set"
        let summary = remaining >= 0
            ? "Budget is tight (\(severity)). Cut \(fmtCents(totalPotentialSavings)) by adjusting \(discretionary.prefix(3).count) categories."
            : "Over budget by \(fmtCents(overBy)). Strict mode: \(fmtCents(dailyLimit))/day. Cut plan saves \(fmtCents(totalPotentialSavings))."

        let result = OptimizationResult(
            type: .budgetRescue,
            title: "Budget Rescue Plan",
            summary: summary,
            recommendations: recs.sorted { $0.priority < $1.priority },
            projectedSavings: totalPotentialSavings,
            projectedImpact: totalPotentialSavings > 0 ? "Could recover \(fmtCents(totalPotentialSavings)) this month" : nil,
            confidence: budget > 0 ? 0.75 : 0.4,
            assumptions: assumptions,
            createdAt: Date(),
            scenarios: [],
            relatedCategories: discretionary.prefix(4).map(\.key),
            relatedGoals: [],
            relatedSubscriptions: SubscriptionEngine.shared.unusedSubs.map(\.merchantName)
        )
        record(result)
        return result
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Goal Catch-Up
    // ══════════════════════════════════════════════════════════

    func goalCatchUp(store: Store) -> OptimizationResult {
        let goals = GoalManager.shared.goals.filter { !$0.isCompleted }
        let behind = goals.filter { $0.trackingStatus == .behind || $0.isOverdue }
        let onTrack = goals.filter { $0.trackingStatus == .onTrack || $0.trackingStatus == .ahead }

        var recs: [OptimizationRecommendation] = []
        var assumptions: [String] = [
            "Active goals: \(goals.count)",
            "Behind/overdue: \(behind.count)"
        ]

        // Sort: overdue first, then by remaining amount
        let prioritized = behind.sorted { a, b in
            if a.isOverdue != b.isOverdue { return a.isOverdue }
            return a.remainingAmount < b.remainingAmount
        }

        var totalRequired = 0

        for (idx, goal) in prioritized.prefix(5).enumerated() {
            let monthly = goal.requiredMonthlySaving ?? goal.remainingAmount
            totalRequired += monthly

            let status = goal.isOverdue ? "Overdue" : "Behind pace"
            let timeline: String
            if let months = goal.monthsToTarget, months > 0 {
                timeline = "\(months) month(s) left"
            } else {
                timeline = "deadline passed"
            }

            recs.append(OptimizationRecommendation(
                title: "\(goal.name): \(fmtCents(monthly))/month needed",
                detail: "\(status) — \(goal.progressPercent)% done, \(fmtCents(goal.remainingAmount)) remaining. \(timeline).",
                amountCents: monthly,
                goalRef: goal.name,
                priority: idx,
                impact: goal.isOverdue ? .high : .medium
            ))
        }

        // If multiple goals, suggest prioritization
        if prioritized.count >= 2 {
            let topGoal = prioritized[0]
            recs.append(OptimizationRecommendation(
                title: "Focus on \"\(topGoal.name)\" first",
                detail: "Concentrate contributions on the most urgent goal, then spread to others.",
                goalRef: topGoal.name,
                priority: prioritized.count,
                impact: .medium
            ))
        }

        // Budget headroom check
        let budget = store.budgetsByMonth[Store.monthKey(Date())] ?? 0
        let spent = store.spent(for: Date())
        let remaining = budget - spent
        if totalRequired > 0 && budget > 0 {
            let pctOfBudget = totalRequired * 100 / max(budget, 1)
            assumptions.append("Goal funding: \(pctOfBudget)% of monthly budget")
            if totalRequired > remaining {
                recs.append(OptimizationRecommendation(
                    title: "Goal funding exceeds remaining budget",
                    detail: "Need \(fmtCents(totalRequired))/month but only \(fmtCents(max(0, remaining))) remains. Consider extending deadlines.",
                    amountCents: totalRequired - max(0, remaining),
                    priority: 0,
                    impact: .high
                ))
            }
        }

        // Suggest pausing lower-priority on-track goals to fund behind ones
        if !onTrack.isEmpty && totalRequired > remaining && remaining > 0 {
            let pausable = onTrack.sorted { ($0.requiredMonthlySaving ?? 0) > ($1.requiredMonthlySaving ?? 0) }
            if let topPause = pausable.first, let pauseAmt = topPause.requiredMonthlySaving {
                recs.append(OptimizationRecommendation(
                    title: "Pause \"\(topPause.name)\" temporarily",
                    detail: "Redirect \(fmtCents(pauseAmt))/month to behind goals. \(topPause.name) is on track and can absorb a delay.",
                    amountCents: pauseAmt,
                    goalRef: topPause.name,
                    priority: prioritized.count + 1,
                    impact: .low
                ))
            }
        }

        let summary = behind.isEmpty
            ? "All goals are on track. Keep it up!"
            : "\(behind.count) goal(s) need attention. Total catch-up: \(fmtCents(totalRequired))/month."

        let result = OptimizationResult(
            type: .goalCatchUp,
            title: "Goal Catch-Up Plan",
            summary: summary,
            recommendations: recs.sorted { $0.priority < $1.priority },
            projectedSavings: nil,
            projectedImpact: behind.isEmpty ? "All goals on track" : "Close \(behind.count) gap(s) with \(fmtCents(totalRequired))/month",
            confidence: goals.isEmpty ? 0.3 : 0.7,
            assumptions: assumptions,
            createdAt: Date(),
            scenarios: [],
            relatedCategories: [],
            relatedGoals: behind.map(\.name),
            relatedSubscriptions: []
        )
        record(result)
        return result
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Subscription Cleanup
    // ══════════════════════════════════════════════════════════

    func subscriptionCleanup() -> OptimizationResult {
        let engine = SubscriptionEngine.shared
        let unused = engine.unusedSubs
        let priceUp = engine.priceIncreasedSubs
        let all = engine.subscriptions.filter { $0.status == .active }

        var recs: [OptimizationRecommendation] = []
        var totalSavings = 0
        var assumptions: [String] = [
            "Active subscriptions: \(all.count)",
            "Monthly total: \(fmtCents(engine.monthlyTotal))"
        ]

        // Unused subscriptions — highest priority
        for (idx, sub) in unused.sorted(by: { $0.expectedAmount > $1.expectedAmount }).prefix(5).enumerated() {
            let monthly = sub.billingCycle == .yearly ? sub.expectedAmount / 12 : sub.expectedAmount
            totalSavings += monthly
            recs.append(OptimizationRecommendation(
                title: "Cancel \(sub.merchantName): \(fmtCents(monthly))/mo",
                detail: "No recent usage detected. Last charge: \(fmtDate(sub.lastChargeDate ?? Date())).",
                amountCents: monthly,
                subscriptionRef: sub.merchantName,
                priority: idx,
                impact: monthly > 1500 ? .high : .medium
            ))
        }

        // Price increased subscriptions
        for sub in priceUp.prefix(3) {
            let pIdx = recs.count
            recs.append(OptimizationRecommendation(
                title: "\(sub.merchantName): price increased",
                detail: "Current: \(fmtCents(sub.lastAmount)). Expected: \(fmtCents(sub.expectedAmount)). Review plan options.",
                amountCents: max(0, sub.lastAmount - sub.expectedAmount),
                subscriptionRef: sub.merchantName,
                priority: pIdx + unused.count,
                impact: .medium
            ))
        }

        // Overlap detection — simple name-based grouping
        let musicKeywords = ["spotify", "apple music", "youtube music", "tidal", "deezer"]
        let musicSubs = all.filter { s in musicKeywords.contains(where: { s.merchantName.lowercased().contains($0) }) }
        if musicSubs.count >= 2 {
            let total = musicSubs.reduce(0) { $0 + $1.expectedAmount }
            recs.append(OptimizationRecommendation(
                title: "Multiple music services: \(fmtCents(total))/mo",
                detail: "\(musicSubs.map(\.merchantName).joined(separator: ", ")) — consider keeping one.",
                amountCents: total / 2, // estimate saving half
                priority: recs.count,
                impact: .medium
            ))
            totalSavings += total / 2
        }

        let streamKeywords = ["netflix", "hulu", "disney", "hbo", "paramount", "peacock", "apple tv"]
        let streamSubs = all.filter { s in streamKeywords.contains(where: { s.merchantName.lowercased().contains($0) }) }
        if streamSubs.count >= 3 {
            let total = streamSubs.reduce(0) { $0 + $1.expectedAmount }
            let cheapest = streamSubs.min(by: { $0.expectedAmount < $1.expectedAmount })
            recs.append(OptimizationRecommendation(
                title: "\(streamSubs.count) streaming services: \(fmtCents(total))/mo",
                detail: "Consider rotating services monthly. Cheapest: \(cheapest?.merchantName ?? "?").",
                amountCents: total / 3,
                priority: recs.count,
                impact: total > 5000 ? .high : .medium
            ))
            totalSavings += total / 3
        }

        let summary = totalSavings > 0
            ? "Could save \(fmtCents(totalSavings))/month by cleaning up \(unused.count + priceUp.count) subscription(s)."
            : "Subscriptions look clean. No obvious savings found."

        let result = OptimizationResult(
            type: .subscriptionCleanup,
            title: "Subscription Cleanup",
            summary: summary,
            recommendations: recs.sorted { $0.priority < $1.priority },
            projectedSavings: totalSavings,
            projectedImpact: totalSavings > 0 ? "\(fmtCents(totalSavings))/month = \(fmtCents(totalSavings * 12))/year" : nil,
            confidence: all.isEmpty ? 0.3 : 0.7,
            assumptions: assumptions,
            createdAt: Date(),
            scenarios: [],
            relatedCategories: [],
            relatedGoals: [],
            relatedSubscriptions: (unused + priceUp).map(\.merchantName)
        )
        record(result)
        return result
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Lean Month Plan
    // ══════════════════════════════════════════════════════════

    func leanMonthPlan(store: Store, availableFunds: Int? = nil) -> OptimizationResult {
        let cal = Calendar.current
        let now = Date()
        let monthKey = Store.monthKey(now)
        let budget = store.budgetsByMonth[monthKey] ?? 0
        let funds = availableFunds ?? budget

        // Gather spending history for allocation ratios
        let monthExpenses = store.transactions.filter {
            $0.type == .expense && cal.isDate($0.date, equalTo: now, toGranularity: .month)
        }
        var catSpending: [String: Int] = [:]
        for t in monthExpenses { catSpending[t.category.storageKey, default: 0] += t.amount }

        // Essential-first allocation tiers
        let tiers: [(name: String, keys: [String], pctOfFunds: Int)] = [
            ("Housing",      ["rent"],                                     30),
            ("Groceries",    ["groceries"],                                15),
            ("Utilities",    ["bills"],                                    10),
            ("Transport",    ["transport"],                                 8),
            ("Health",       ["health"],                                    5),
            ("Debt minimum", [],                                           5), // placeholder
            ("Goals",        [],                                           10),
            ("Discretionary",["dining", "shopping", "education", "other"], 17),
        ]

        var recs: [OptimizationRecommendation] = []
        var allocated = 0
        var assumptions: [String] = [
            "Available funds: \(fmtCents(funds))",
            "Lean allocation mode: essentials first"
        ]

        for (idx, tier) in tiers.enumerated() {
            let tierAmount = funds * tier.pctOfFunds / 100
            allocated += tierAmount

            let currentSpend = tier.keys.reduce(0) { $0 + (catSpending[$1] ?? 0) }
            let vs = currentSpend > 0 ? " (current: \(fmtCents(currentSpend)))" : ""

            recs.append(OptimizationRecommendation(
                title: "\(tier.name): \(fmtCents(tierAmount))",
                detail: "\(tier.pctOfFunds)% of available funds\(vs).",
                amountCents: tierAmount,
                categoryRef: tier.keys.first,
                priority: idx,
                impact: idx < 4 ? .high : (idx < 6 ? .medium : .low)
            ))
        }

        // Buffer
        let buffer = funds - allocated
        if buffer > 0 {
            recs.append(OptimizationRecommendation(
                title: "Emergency buffer: \(fmtCents(buffer))",
                detail: "Unallocated reserve for unexpected expenses.",
                amountCents: buffer,
                priority: tiers.count,
                impact: .medium
            ))
        }

        // Upcoming bills within month
        let upcoming = SubscriptionEngine.shared.renewingWithin(days: 30)
        if !upcoming.isEmpty {
            let billTotal = upcoming.reduce(0) { $0 + $1.expectedAmount }
            assumptions.append("Recurring bills: \(fmtCents(billTotal)) (\(upcoming.count) subscriptions)")
        }

        let result = OptimizationResult(
            type: .leanMonthPlan,
            title: "Lean Month Plan",
            summary: "Essentials-first allocation of \(fmtCents(funds)). Housing and food: \(fmtCents(funds * 45 / 100)). Discretionary: \(fmtCents(funds * 17 / 100)).",
            recommendations: recs,
            projectedSavings: nil,
            projectedImpact: "Covers essentials with \(fmtCents(buffer)) buffer",
            confidence: funds > 0 ? 0.7 : 0.3,
            assumptions: assumptions,
            createdAt: Date(),
            scenarios: [],
            relatedCategories: tiers.flatMap(\.keys),
            relatedGoals: [],
            relatedSubscriptions: []
        )
        record(result)
        return result
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Paycheck Allocation
    // ══════════════════════════════════════════════════════════

    func paycheckAllocation(store: Store, paycheckAmount: Int) -> OptimizationResult {
        let cal = Calendar.current
        let now = Date()
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let dayOfMonth = cal.component(.day, from: now)
        let daysLeft = max(1, daysInMonth - dayOfMonth)

        // Upcoming bills
        let upcoming = SubscriptionEngine.shared.renewingWithin(days: daysLeft)
        let billTotal = upcoming.reduce(0) { $0 + $1.expectedAmount }

        // Goal contributions
        let goalMonthly = GoalManager.shared.totalRequiredMonthly
        let goalProrated = goalMonthly * daysLeft / daysInMonth

        // Remaining budget gap
        let budget = store.budgetsByMonth[Store.monthKey(now)] ?? 0
        let spent = store.spent(for: now)
        let budgetGap = max(0, spent - budget)

        var recs: [OptimizationRecommendation] = []
        var remaining = paycheckAmount
        var assumptions = ["Paycheck: \(fmtCents(paycheckAmount))", "Days left in month: \(daysLeft)"]

        // 1. Bills
        let billAlloc = min(remaining, billTotal)
        if billAlloc > 0 {
            recs.append(OptimizationRecommendation(
                title: "Upcoming bills: \(fmtCents(billAlloc))",
                detail: "\(upcoming.count) recurring payment(s) due within \(daysLeft) days.",
                amountCents: billAlloc,
                priority: 0,
                impact: .high
            ))
            remaining -= billAlloc
        }

        // 2. Budget recovery
        if budgetGap > 0 && remaining > 0 {
            let recoveryAlloc = min(remaining, budgetGap)
            recs.append(OptimizationRecommendation(
                title: "Budget recovery: \(fmtCents(recoveryAlloc))",
                detail: "Cover the \(fmtCents(budgetGap)) overspend gap.",
                amountCents: recoveryAlloc,
                priority: 1,
                impact: .high
            ))
            remaining -= recoveryAlloc
        }

        // 3. Essential spending
        let essentialDaily = max(0, budget * 50 / 100) / daysInMonth // ~50% of budget is essentials
        let essentialAlloc = min(remaining, essentialDaily * daysLeft)
        if essentialAlloc > 0 {
            recs.append(OptimizationRecommendation(
                title: "Essential spending: \(fmtCents(essentialAlloc))",
                detail: "Food, transport, basics for the next \(daysLeft) days.",
                amountCents: essentialAlloc,
                priority: 2,
                impact: .high
            ))
            remaining -= essentialAlloc
        }

        // 4. Goals
        let goalAlloc = min(remaining, goalProrated)
        if goalAlloc > 0 {
            recs.append(OptimizationRecommendation(
                title: "Goal contributions: \(fmtCents(goalAlloc))",
                detail: "Prorated savings for active goals.",
                amountCents: goalAlloc,
                priority: 3,
                impact: .medium
            ))
            remaining -= goalAlloc
        }

        // 5. Discretionary
        if remaining > 0 {
            recs.append(OptimizationRecommendation(
                title: "Discretionary: \(fmtCents(remaining))",
                detail: "Available for flexible spending (\(fmtCents(remaining / daysLeft))/day).",
                amountCents: remaining,
                priority: 4,
                impact: .low
            ))
        }

        let result = OptimizationResult(
            type: .paycheckAllocation,
            title: "Paycheck Allocation",
            summary: "Allocated \(fmtCents(paycheckAmount)): bills \(fmtCents(billAlloc)), essentials \(fmtCents(essentialAlloc)), goals \(fmtCents(goalAlloc)), flex \(fmtCents(remaining)).",
            recommendations: recs,
            projectedSavings: goalAlloc,
            projectedImpact: "Covers \(daysLeft) days with \(fmtCents(remaining)) discretionary",
            confidence: 0.7,
            assumptions: assumptions,
            createdAt: Date(),
            scenarios: [],
            relatedCategories: [],
            relatedGoals: GoalManager.shared.activeGoals.map(\.name),
            relatedSubscriptions: upcoming.map(\.merchantName)
        )
        record(result)
        return result
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Tradeoff Comparison
    // ══════════════════════════════════════════════════════════

    func compareTradeoffs(
        scenarioA: (label: String, description: String),
        scenarioB: (label: String, description: String),
        store: Store,
        amountCents: Int,
        timelineWeeks: Int = 4
    ) -> OptimizationResult {
        let budget = store.budgetsByMonth[Store.monthKey(Date())] ?? 0
        let remaining = budget - store.spent(for: Date())
        let goalMonthly = GoalManager.shared.totalRequiredMonthly

        // Scenario A: typically "spend now" or "aggressive" path
        let aImpactOnBudget = amountCents > remaining
        let aDelaysGoals = amountCents > remaining && goalMonthly > 0
        let scA = OptimizationScenario(
            label: scenarioA.label,
            description: scenarioA.description,
            projectedSavings: 0,
            timelineWeeks: 0,
            riskLevel: aImpactOnBudget ? "high" : "moderate",
            impactedCategories: aImpactOnBudget ? ["budget"] : [],
            impactedGoals: aDelaysGoals ? GoalManager.shared.activeGoals.prefix(2).map(\.name) : [],
            pros: [
                "Immediate result",
                amountCents <= remaining ? "Within budget" : "Addresses need now"
            ],
            cons: aImpactOnBudget
                ? ["Exceeds remaining budget", "May require category cuts", aDelaysGoals ? "Delays goal progress" : ""].filter { !$0.isEmpty }
                : ["Reduces remaining budget by \(fmtCents(amountCents))"]
        )

        // Scenario B: typically "wait" or "conservative" path
        let bSavings = amountCents
        let scB = OptimizationScenario(
            label: scenarioB.label,
            description: scenarioB.description,
            projectedSavings: bSavings,
            timelineWeeks: timelineWeeks,
            riskLevel: "low",
            impactedCategories: [],
            impactedGoals: [],
            pros: [
                "Preserves budget",
                "Goals stay on track",
                "\(fmtCents(amountCents)) remains available",
                timelineWeeks > 0 ? "Allows \(timelineWeeks) week(s) to plan" : ""
            ].filter { !$0.isEmpty },
            cons: [
                "Delayed gratification",
                timelineWeeks > 0 ? "\(timelineWeeks) week(s) wait" : "Requires discipline"
            ]
        )

        let result = OptimizationResult(
            type: .tradeoffComparison,
            title: "Compare: \(scenarioA.label) vs \(scenarioB.label)",
            summary: aImpactOnBudget
                ? "\(scenarioA.label) exceeds budget. \(scenarioB.label) saves \(fmtCents(bSavings)) and keeps goals intact."
                : "Both options are feasible. \(scenarioA.label) costs \(fmtCents(amountCents)); \(scenarioB.label) preserves it.",
            recommendations: [
                OptimizationRecommendation(
                    title: aImpactOnBudget ? "Recommendation: \(scenarioB.label)" : "Both feasible — your call",
                    detail: aImpactOnBudget
                        ? "The conservative option protects your budget and goals."
                        : "Choose based on your priorities. The purchase fits within budget.",
                    amountCents: amountCents,
                    priority: 0,
                    impact: aImpactOnBudget ? .high : .low
                )
            ],
            projectedSavings: bSavings,
            projectedImpact: "\(scenarioB.label) preserves \(fmtCents(bSavings))",
            confidence: 0.65,
            assumptions: [
                "Amount: \(fmtCents(amountCents))",
                "Remaining budget: \(fmtCents(remaining))",
                "Timeline: \(timelineWeeks) week(s)"
            ],
            createdAt: Date(),
            scenarios: [scA, scB],
            relatedCategories: [],
            relatedGoals: GoalManager.shared.activeGoals.prefix(2).map(\.name),
            relatedSubscriptions: []
        )
        record(result)
        return result
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Spending Freeze Plan
    // ══════════════════════════════════════════════════════════

    func spendingFreeze(store: Store, durationDays: Int = 7) -> OptimizationResult {
        let cal = Calendar.current
        let now = Date()
        let monthExpenses = store.transactions.filter {
            $0.type == .expense && cal.isDate($0.date, equalTo: now, toGranularity: .month)
        }
        var catSpending: [String: Int] = [:]
        for t in monthExpenses { catSpending[t.category.storageKey, default: 0] += t.amount }

        let essentialKeys = Set(["rent", "bills", "health", "transport", "groceries"])

        var recs: [OptimizationRecommendation] = []
        var freezeSavings = 0

        // Freeze all discretionary
        let discretionary = catSpending.filter { !essentialKeys.contains($0.key) }
        let dayOfMonth = cal.component(.day, from: now)
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let dailyDiscretionary = discretionary.values.reduce(0, +) / max(dayOfMonth, 1)
        let projectedFreezeSavings = dailyDiscretionary * durationDays
        freezeSavings = projectedFreezeSavings

        recs.append(OptimizationRecommendation(
            title: "Freeze discretionary: save ~\(fmtCents(projectedFreezeSavings))",
            detail: "No dining, shopping, entertainment for \(durationDays) days.",
            amountCents: projectedFreezeSavings,
            priority: 0,
            impact: .high
        ))

        // Essential-only allowance
        let essentialDaily = essentialKeys.reduce(0) { $0 + (catSpending[$1] ?? 0) } / max(dayOfMonth, 1)
        recs.append(OptimizationRecommendation(
            title: "Essential-only: \(fmtCents(essentialDaily))/day",
            detail: "Groceries, transport, health only during freeze period.",
            amountCents: essentialDaily,
            priority: 1,
            impact: .medium
        ))

        // Subscription pause suggestion
        let pausableSubs = SubscriptionEngine.shared.subscriptions.filter {
            $0.status == .active && !essentialKeys.contains($0.category.storageKey)
        }
        if !pausableSubs.isEmpty {
            let subSavings = pausableSubs.prefix(3).reduce(0) { $0 + $1.expectedAmount }
            recs.append(OptimizationRecommendation(
                title: "Pause \(pausableSubs.prefix(3).count) subscription(s): \(fmtCents(subSavings))/mo",
                detail: "Pause non-essential subscriptions during the freeze.",
                amountCents: subSavings,
                priority: 2,
                impact: .medium
            ))
        }

        let result = OptimizationResult(
            type: .spendingFreeze,
            title: "\(durationDays)-Day Spending Freeze",
            summary: "Freeze discretionary spending for \(durationDays) days. Estimated savings: \(fmtCents(freezeSavings)).",
            recommendations: recs,
            projectedSavings: freezeSavings,
            projectedImpact: "Save \(fmtCents(freezeSavings)) over \(durationDays) days",
            confidence: 0.6,
            assumptions: [
                "Based on current month's daily averages",
                "Essential spending continues normally",
                "Duration: \(durationDays) days"
            ],
            createdAt: Date(),
            scenarios: [],
            relatedCategories: Array(discretionary.keys),
            relatedGoals: [],
            relatedSubscriptions: pausableSubs.prefix(3).map(\.merchantName)
        )
        record(result)
        return result
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Quick Affordability Check
    // ══════════════════════════════════════════════════════════

    /// Quick check: "Can I afford X?"
    func canAfford(amount: Int, store: Store) -> OptimizationResult {
        let aff = AISafeToSpend.shared.canAfford(amount: amount, store: store)
        let sts = AISafeToSpend.shared.calculate(store: store)

        var recs: [OptimizationRecommendation] = []

        recs.append(OptimizationRecommendation(
            title: aff.canAfford ? "Yes — \(impactLabel(aff.impact)) impact" : "Not recommended",
            detail: aff.message,
            amountCents: amount,
            priority: 0,
            impact: aff.impact == .minimal ? .low : (aff.impact == .moderate ? .medium : .high)
        ))

        recs.append(OptimizationRecommendation(
            title: "After purchase: \(fmtCents(aff.remainingAfter)) remaining",
            detail: aff.remainingAfter < 0 ? "Would put you over budget." : "Still within budget.",
            amountCents: aff.remainingAfter,
            priority: 1,
            impact: aff.remainingAfter < 0 ? .high : .low
        ))

        if !aff.canAfford {
            recs.append(OptimizationRecommendation(
                title: "Alternative: wait \(max(1, amount / max(sts.trueAllowance, 1))) day(s)",
                detail: "Save \(fmtCents(sts.trueAllowance))/day to afford this in \(max(1, amount / max(sts.trueAllowance, 1))) day(s).",
                amountCents: sts.trueAllowance,
                priority: 2,
                impact: .medium
            ))
        }

        let result = OptimizationResult(
            type: .safeToSpend,
            title: "Can I Afford \(fmtCents(amount))?",
            summary: aff.message,
            recommendations: recs,
            projectedSavings: nil,
            projectedImpact: aff.canAfford ? "Affordable with \(impactLabel(aff.impact)) impact" : "Exceeds safe spending limit",
            confidence: 0.8,
            assumptions: ["Daily allowance: \(fmtCents(sts.trueAllowance))", "Remaining budget: \(fmtCents(sts.remainingBudget))"],
            createdAt: Date(),
            scenarios: [],
            relatedCategories: [],
            relatedGoals: [],
            relatedSubscriptions: []
        )
        record(result)
        return result
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Helpers
    // ══════════════════════════════════════════════════════════

    private func fmtCents(_ cents: Int) -> String {
        let isNeg = cents < 0
        let str = String(format: "$%.2f", Double(abs(cents)) / 100.0)
        return isNeg ? "-\(str)" : str
    }

    private func impactLabel(_ impact: AffordabilityResult.Impact) -> String {
        switch impact {
        case .minimal:  return "minimal"
        case .moderate: return "moderate"
        case .severe:   return "severe"
        }
    }

    private func fmtDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }

    /// Compute goal reserve independently (mirrors AISafeToSpend private method).
    private func computeGoalReserve() -> Int {
        GoalManager.shared.goals
            .filter { !$0.isCompleted }
            .compactMap(\.requiredMonthlySaving)
            .reduce(0, +)
    }
}
