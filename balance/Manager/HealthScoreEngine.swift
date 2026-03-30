import Foundation

// ============================================================
// MARK: - Financial Health Score Engine
// ============================================================
//
// Computes a 0-100 health score from weighted components:
//   Budget adherence     25%
//   Forecast health      20%
//   Review cleanliness   15%
//   Subscription savings 15%
//   Goal progress        15%
//   Household health     10%
//
// Score persisted monthly for trend tracking.
//
// ============================================================

@MainActor
enum HealthScoreEngine {

    struct HealthScore {
        let total: Int                        // 0-100
        let budgetScore: Int                  // 0-100
        let forecastScore: Int                // 0-100
        let reviewScore: Int                  // 0-100
        let subscriptionScore: Int            // 0-100
        let goalScore: Int                    // 0-100
        let householdScore: Int               // 0-100
        let generatedAt: Date

        var label: String {
            switch total {
            case 80...100: return "Excellent"
            case 60..<80: return "Good"
            case 40..<60: return "Fair"
            case 20..<40: return "Needs Work"
            default: return "Critical"
            }
        }

        var color: Int {
            switch total {
            case 80...100: return 0x2ED573  // green
            case 60..<80: return 0x4559F5   // blue
            case 40..<60: return 0xFF9F0A   // orange
            default: return 0xFF3B30        // red
            }
        }
    }

    /// Compute the health score from current app state.
    static func compute(
        store: Store,
        forecast: ForecastResult?,
        reviewSnapshot: ReviewSnapshot?,
        subscriptionSnapshot: SubscriptionSnapshot?,
        householdSnapshot: HouseholdSnapshot?,
        goalManager: GoalManager?
    ) -> HealthScore {

        let budget = computeBudgetScore(store: store)
        let forecastS = computeForecastScore(forecast: forecast)
        let review = computeReviewScore(snapshot: reviewSnapshot, store: store)
        let subscription = computeSubscriptionScore(snapshot: subscriptionSnapshot)
        let goal = computeGoalScore(goalManager: goalManager)
        let household = computeHouseholdScore(snapshot: householdSnapshot)

        // Weighted total
        let total = Int(
            Double(budget) * 0.25 +
            Double(forecastS) * 0.20 +
            Double(review) * 0.15 +
            Double(subscription) * 0.15 +
            Double(goal) * 0.15 +
            Double(household) * 0.10
        )

        let score = HealthScore(
            total: min(100, max(0, total)),
            budgetScore: budget,
            forecastScore: forecastS,
            reviewScore: review,
            subscriptionScore: subscription,
            goalScore: goal,
            householdScore: household,
            generatedAt: Date()
        )

        // Persist for trend tracking
        persistScore(score, store: store)

        return score
    }

    /// Get historical scores for trend chart.
    static func scoreHistory() -> [(monthKey: String, score: Int)] {
        guard let data = UserDefaults.standard.data(forKey: "healthscore.history"),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return []
        }
        return dict.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    // MARK: - Component Scores

    /// Budget adherence: 100 if under budget, scales down linearly.
    /// No budget set = 50 (neutral).
    private static func computeBudgetScore(store: Store) -> Int {
        let summary = Analytics.monthSummary(store: store)
        guard summary.budgetCents > 0 else { return 50 }

        let ratio = summary.spentRatio
        if ratio <= 0.85 { return 100 }
        if ratio <= 1.0 { return Int(100 - (ratio - 0.85) / 0.15 * 40) }  // 100 -> 60
        if ratio <= 1.2 { return Int(60 - (ratio - 1.0) / 0.2 * 40) }     // 60 -> 20
        return max(0, Int(20 - (ratio - 1.2) * 100))
    }

    /// Forecast health: based on risk level and safe-to-spend.
    private static func computeForecastScore(forecast: ForecastResult?) -> Int {
        guard let f = forecast else { return 50 }

        switch f.riskLevel {
        case .safe:
            return f.safeToSpend.isOvercommitted ? 60 : 100
        case .caution:
            return f.safeToSpend.isOvercommitted ? 30 : 55
        case .highRisk:
            return f.safeToSpend.isOvercommitted ? 10 : 25
        }
    }

    /// Review cleanliness: inverse of pending items relative to total transactions.
    private static func computeReviewScore(snapshot: ReviewSnapshot?, store: Store) -> Int {
        guard let rs = snapshot else { return 80 }  // no review engine = assume clean
        if rs.pendingCount == 0 { return 100 }

        let monthTx = Analytics.monthTransactions(store: store)
        guard !monthTx.isEmpty else { return 80 }

        let ratio = Double(rs.pendingCount) / Double(monthTx.count)
        if ratio <= 0.05 { return 90 }
        if ratio <= 0.15 { return 70 }
        if ratio <= 0.30 { return 50 }
        return 30
    }

    /// Subscription efficiency: penalizes unused subs relative to total cost.
    private static func computeSubscriptionScore(snapshot: SubscriptionSnapshot?) -> Int {
        guard let ss = snapshot, ss.activeCount > 0 else { return 80 }

        if ss.unusedCount == 0 && ss.priceIncreaseCount == 0 { return 100 }

        let wasteRatio = ss.monthlyTotal > 0
            ? Double(ss.potentialSavings) / Double(ss.monthlyTotal)
            : 0

        if wasteRatio <= 0.1 { return 85 }
        if wasteRatio <= 0.25 { return 65 }
        if wasteRatio <= 0.5 { return 40 }
        return 20
    }

    /// Goal progress: weighted average of active goals.
    private static func computeGoalScore(goalManager: GoalManager?) -> Int {
        guard let gm = goalManager else { return 50 }

        let active = gm.activeGoals
        guard !active.isEmpty else { return 70 }  // no goals = neutral-good

        let behindCount = gm.behindGoals.count
        let onTrackCount = active.count - behindCount

        if behindCount == 0 { return 100 }
        let ratio = Double(onTrackCount) / Double(active.count)
        return max(20, Int(ratio * 100))
    }

    /// Household health: settlement freshness + shared budget adherence.
    private static func computeHouseholdScore(snapshot: HouseholdSnapshot?) -> Int {
        guard let hs = snapshot, hs.hasPartner else { return 70 }  // no household = neutral

        var score = 100

        // Penalty for unsettled expenses
        if hs.unsettledCount > 5 { score -= 30 }
        else if hs.unsettledCount > 2 { score -= 15 }

        // Penalty for owing money
        if hs.youOwe > 0 { score -= 15 }

        // Penalty for over shared budget
        if hs.isOverBudget { score -= 20 }
        else if let util = hs.budgetUtilization, util > 0.9 { score -= 10 }

        return max(0, score)
    }

    // MARK: - Persistence

    private static func persistScore(_ score: HealthScore, store: Store) {
        let cal = Calendar.current
        let y = cal.component(.year, from: store.selectedMonth)
        let m = cal.component(.month, from: store.selectedMonth)
        let monthKey = String(format: "%04d-%02d", y, m)

        var history: [String: Int]
        if let data = UserDefaults.standard.data(forKey: "healthscore.history"),
           let existing = try? JSONDecoder().decode([String: Int].self, from: data) {
            history = existing
        } else {
            history = [:]
        }

        history[monthKey] = score.total

        // Keep last 12 months
        if history.count > 12 {
            let sorted = history.keys.sorted()
            for key in sorted.prefix(history.count - 12) {
                history.removeValue(forKey: key)
            }
        }

        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "healthscore.history")
        }
    }
}
