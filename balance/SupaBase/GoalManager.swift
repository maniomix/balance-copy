import Foundation
import Supabase
import Combine

// MARK: - Goal Manager

@MainActor
class GoalManager: ObservableObject {

    static let shared = GoalManager()

    @Published var goals: [Goal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var client: SupabaseClient { SupabaseManager.shared.client }

    private var currentUserId: String? {
        AuthManager.shared.currentUser?.uid.lowercased()
    }

    private init() {}

    // MARK: - Fetch Goals

    func fetchGoals() async {
        guard let userId = currentUserId else { return }
        isLoading = true

        do {
            let response: [Goal] = try await client
                .from("goals")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.goals = response
            SecureLogger.info("Fetched \(response.count) goals")
        } catch {
            self.errorMessage = AppConfig.shared.safeErrorMessage(
                detail: error.localizedDescription,
                fallback: "Could not load goals. Please try again."
            )
            SecureLogger.error("Fetch goals failed", error)
        }

        isLoading = false
    }

    // MARK: - Create Goal

    func createGoal(_ goal: Goal) async -> Bool {
        errorMessage = nil
        do {
            try await client.from("goals").insert(goal).execute()
            SecureLogger.info("Goal created")
            AnalyticsManager.shared.track(.goalCreated)
            AnalyticsManager.shared.checkFirstGoal()
            await fetchGoals()
            return true
        } catch {
            errorMessage = AppConfig.shared.safeErrorMessage(
                detail: error.localizedDescription,
                fallback: "Could not create goal. Please try again."
            )
            SecureLogger.error("Create goal failed", error)
            return false
        }
    }

    // MARK: - Update Goal

    func updateGoal(_ goal: Goal) async -> Bool {
        errorMessage = nil
        var updated = goal
        updated.updatedAt = Date()

        do {
            try await client.from("goals")
                .update(updated)
                .eq("id", value: updated.id.uuidString)
                .execute()
            SecureLogger.info("Goal updated")
            await fetchGoals()
            return true
        } catch {
            errorMessage = AppConfig.shared.safeErrorMessage(
                detail: error.localizedDescription,
                fallback: "Could not update goal. Please try again."
            )
            SecureLogger.error("Update goal failed", error)
            return false
        }
    }

    // MARK: - Delete Goal

    func deleteGoal(_ goal: Goal) async -> Bool {
        guard let userId = currentUserId else {
            SecureLogger.warning("deleteGoal: No authenticated user")
            return false
        }
        errorMessage = nil

        do {
            // Delete contributions first (scoped to user's goal)
            try await client.from("goal_contributions")
                .delete()
                .eq("goal_id", value: goal.id.uuidString)
                .execute()

            // Delete the goal itself — filter by user_id to prevent cross-user deletion
            try await client.from("goals")
                .delete()
                .eq("id", value: goal.id.uuidString)
                .eq("user_id", value: userId)
                .execute()

            await fetchGoals()

            // Notify so transaction references can be cleaned up
            NotificationCenter.default.post(
                name: .goalDidDelete,
                object: nil,
                userInfo: ["goalId": goal.id]
            )

            return true
        } catch {
            errorMessage = AppConfig.shared.safeErrorMessage(
                detail: error.localizedDescription,
                fallback: "Could not delete goal. Please try again."
            )
            SecureLogger.error("Delete goal failed", error)
            return false
        }
    }

    // MARK: - Contributions

    func addContribution(
        to goal: Goal,
        amount: Int,
        note: String? = nil,
        source: GoalContribution.ContributionSource = .manual,
        linkedTransactionId: UUID? = nil,
        linkedRuleId: UUID? = nil
    ) async -> Bool {
        let contribution = GoalContribution(
            goalId: goal.id,
            amount: amount,
            note: note,
            source: source,
            linkedTransactionId: linkedTransactionId,
            linkedRuleId: linkedRuleId
        )
        errorMessage = nil

        do {
            try await client.from("goal_contributions").insert(contribution).execute()

            // Update goal's current amount + detect 25/50/75/100% milestones.
            // Phase 10 polish: fire haptics when crossing a quarter threshold.
            var updated = goal
            let preTier = milestoneTier(amount: goal.currentAmount, target: goal.targetAmount)
            updated.currentAmount += amount
            let postTier = milestoneTier(amount: updated.currentAmount, target: updated.targetAmount)

            if updated.currentAmount >= updated.targetAmount {
                let wasCompleted = updated.isCompleted
                updated.isCompleted = true
                if !wasCompleted {
                    AnalyticsManager.shared.track(.goalCompleted)
                    Haptics.goalCompleted()
                }
            } else if postTier > preTier {
                Haptics.goalMilestone()
            }
            AnalyticsManager.shared.track(.goalContribution)
            updated.updatedAt = Date()

            try await client.from("goals")
                .update(updated)
                .eq("id", value: updated.id.uuidString)
                .execute()

            await fetchGoals()
            SecureLogger.info("Goal contribution added")
            return true
        } catch {
            errorMessage = AppConfig.shared.safeErrorMessage(detail: error.localizedDescription)
            SecureLogger.error("Goal contribution failed", error)
            return false
        }
    }

    /// Withdraw from a goal (negative contribution)
    func withdrawContribution(from goal: Goal, amount: Int, note: String? = nil) async -> Bool {
        let withdrawAmount = min(amount, goal.currentAmount)
        guard withdrawAmount > 0 else { return false }

        let contribution = GoalContribution(
            goalId: goal.id,
            amount: -withdrawAmount,
            note: note ?? "Withdrawal",
            source: .manual
        )
        errorMessage = nil

        do {
            try await client.from("goal_contributions").insert(contribution).execute()

            var updated = goal
            updated.currentAmount = max(0, updated.currentAmount - withdrawAmount)
            // Only un-complete if the withdrawal drops balance below target.
            // A 1¢ withdrawal from a fully-funded goal should keep it completed.
            if updated.currentAmount < updated.targetAmount {
                updated.isCompleted = false
            }
            updated.updatedAt = Date()

            try await client.from("goals")
                .update(updated)
                .eq("id", value: updated.id.uuidString)
                .execute()

            await fetchGoals()
            SecureLogger.info("Goal withdrawal processed")
            return true
        } catch {
            errorMessage = AppConfig.shared.safeErrorMessage(detail: error.localizedDescription)
            SecureLogger.error("Goal withdrawal failed", error)
            return false
        }
    }

    /// Returns 0 for <25%, 1 for 25–49%, 2 for 50–74%, 3 for 75–99%, 4 for ≥100%.
    /// Used to detect milestone crossings on a contribution.
    private func milestoneTier(amount: Int, target: Int) -> Int {
        guard target > 0 else { return 0 }
        let pct = Double(amount) / Double(target)
        if pct >= 1.0 { return 4 }
        if pct >= 0.75 { return 3 }
        if pct >= 0.5 { return 2 }
        if pct >= 0.25 { return 1 }
        return 0
    }

    /// Soft-reverse a contribution: marks `is_reversed = true` and rolls back
    /// the goal's denorm balance. Reversed rows remain in history for audit.
    /// Idempotent — calling twice is a no-op.
    func reverseContribution(_ contribution: GoalContribution, in goal: Goal) async -> Bool {
        guard !contribution.isReversed else { return false }
        errorMessage = nil

        var reversed = contribution
        reversed.isReversed = true
        reversed.reversedAt = Date()

        do {
            try await client.from("goal_contributions")
                .update(reversed)
                .eq("id", value: contribution.id.uuidString)
                .execute()

            var updated = goal
            updated.currentAmount = max(0, updated.currentAmount - contribution.amount)
            if updated.currentAmount < updated.targetAmount {
                updated.isCompleted = false
            }
            updated.updatedAt = Date()

            try await client.from("goals")
                .update(updated)
                .eq("id", value: updated.id.uuidString)
                .execute()

            await fetchGoals()
            SecureLogger.info("Goal contribution reversed")
            return true
        } catch {
            errorMessage = AppConfig.shared.safeErrorMessage(detail: error.localizedDescription)
            SecureLogger.error("Reverse contribution failed", error)
            return false
        }
    }

    func fetchContributions(for goal: Goal) async -> [GoalContribution] {
        do {
            let response: [GoalContribution] = try await client
                .from("goal_contributions")
                .select()
                .eq("goal_id", value: goal.id.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            return response
        } catch {
            return []
        }
    }

    // MARK: - Projections

    /// Average monthly contribution for a goal based on its history
    func averageMonthlyContribution(for goal: Goal) async -> Int {
        let contributions = await fetchContributions(for: goal)
        let positiveOnly = contributions.filter { $0.amount > 0 }
        guard !positiveOnly.isEmpty else { return 0 }

        let total = positiveOnly.reduce(0) { $0 + $1.amount }
        let months = max(1, Calendar.current.dateComponents(
            [.month], from: goal.createdAt, to: Date()
        ).month ?? 1)

        return total / months
    }

    /// Detailed projection for a goal
    func projection(for goal: Goal) async -> GoalProjection {
        let avgMonthly = await averageMonthlyContribution(for: goal)
        let contributions = await fetchContributions(for: goal)

        let totalContributed = contributions.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
        let totalWithdrawn = contributions.filter { $0.amount < 0 }.reduce(0) { $0 + abs($1.amount) }
        let contributionCount = contributions.count

        // Average per contribution
        let positiveContributions = contributions.filter { $0.amount > 0 }
        let avgPerContribution = positiveContributions.isEmpty ? 0 : totalContributed / positiveContributions.count

        // Weekly rate (last 4 weeks)
        let fourWeeksAgo = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let recentTotal = contributions
            .filter { $0.amount > 0 && $0.createdAt >= fourWeeksAgo }
            .reduce(0) { $0 + $1.amount }
        let weeklyRate = recentTotal / 4

        // Estimated completion
        let estimatedDate = goal.estimatedCompletion(averageMonthly: avgMonthly)

        // On-track assessment
        let onTrackPace: Int? = {
            guard goal.targetDate != nil else { return nil }
            return goal.requiredMonthlySaving
        }()

        let paceStatus: GoalProjection.PaceStatus = {
            guard let required = onTrackPace, required > 0 else {
                if goal.isCompleted { return .completed }
                return .noDeadline
            }
            if avgMonthly == 0 { return .behind }
            let ratio = Double(avgMonthly) / Double(required)
            if ratio >= 1.1 { return .ahead }
            if ratio >= 0.9 { return .onTrack }
            return .behind
        }()

        return GoalProjection(
            averageMonthly: avgMonthly,
            averagePerContribution: avgPerContribution,
            weeklyRate: weeklyRate,
            totalContributed: totalContributed,
            totalWithdrawn: totalWithdrawn,
            contributionCount: contributionCount,
            estimatedCompletion: estimatedDate,
            requiredMonthly: goal.requiredMonthlySaving,
            paceStatus: paceStatus
        )
    }

    // MARK: - Computed

    var activeGoals: [Goal] {
        goals.filter { !$0.isCompleted && !$0.isArchived && $0.pausedAt == nil }
    }

    var pausedGoals: [Goal] {
        goals.filter { $0.pausedAt != nil && !$0.isArchived }
    }

    var archivedGoals: [Goal] {
        goals.filter { $0.isArchived }
    }

    var completedGoals: [Goal] {
        goals.filter { $0.isCompleted && !$0.isArchived }
    }

    var totalSaved: Int {
        goals.reduce(0) { $0 + $1.currentAmount }
    }

    var totalTarget: Int {
        goals.reduce(0) { $0 + $1.targetAmount }
    }

    var overallProgress: Double {
        guard totalTarget > 0 else { return 0 }
        return min(Double(totalSaved) / Double(totalTarget), 1.0)
    }

    /// Goals with upcoming deadlines (next 30 days)
    var upcomingDeadlines: [Goal] {
        let thirtyDays = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        return activeGoals.filter { goal in
            guard let target = goal.targetDate else { return false }
            return target <= thirtyDays && target >= Date()
        }.sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
    }

    /// Goals sorted by explicit user priority (desc), with deadline as tiebreaker.
    /// Goals with priority == 0 fall back to the legacy deadline/progress order.
    var goalsByPriority: [Goal] {
        activeGoals.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            if a.targetDate != nil && b.targetDate == nil { return true }
            if a.targetDate == nil && b.targetDate != nil { return false }
            if let ad = a.targetDate, let bd = b.targetDate { return ad < bd }
            return a.progress < b.progress
        }
    }

    /// Goals that are behind schedule
    var behindGoals: [Goal] {
        activeGoals.filter { $0.trackingStatus == .behind }
    }

    /// Goals that are overdue (past deadline, not completed)
    var overdueGoals: [Goal] {
        activeGoals.filter { $0.isOverdue }
    }

    /// Total required monthly contributions across all active goals with deadlines
    var totalRequiredMonthly: Int {
        activeGoals.compactMap { $0.requiredMonthlySaving }.reduce(0, +)
    }

    /// The single most urgent goal: overdue first, then behind-schedule closest to deadline
    var mostUrgentGoal: Goal? {
        // Overdue goals first (sorted by how overdue)
        if let overdue = overdueGoals.sorted(by: {
            ($0.targetDate ?? .distantPast) < ($1.targetDate ?? .distantPast)
        }).first {
            return overdue
        }
        // Behind schedule, closest deadline
        if let behind = behindGoals.sorted(by: {
            ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture)
        }).first {
            return behind
        }
        // Closest upcoming deadline
        return upcomingDeadlines.first
    }

    // MARK: - Planning Insights

    /// Generates a snapshot of planning insights for the dashboard.
    /// This is a synchronous read of current state — no async fetches needed.
    var planningSnapshot: PlanningSnapshot {
        let behind = behindGoals
        let overdue = overdueGoals
        let urgent = mostUrgentGoal
        let totalRequired = totalRequiredMonthly
        let active = activeGoals

        return PlanningSnapshot(
            activeGoalCount: active.count,
            behindCount: behind.count,
            overdueCount: overdue.count,
            totalRequiredMonthly: totalRequired,
            mostUrgentGoal: urgent,
            totalSaved: totalSaved,
            totalTarget: totalTarget,
            overallProgress: overallProgress
        )
    }
}

// MARK: - Planning Snapshot (value type for dashboard)

struct PlanningSnapshot {
    let activeGoalCount: Int
    let behindCount: Int
    let overdueCount: Int
    let totalRequiredMonthly: Int
    let mostUrgentGoal: Goal?
    let totalSaved: Int
    let totalTarget: Int
    let overallProgress: Double

    /// Whether there are any planning alerts worth showing
    var hasAlerts: Bool {
        overdueCount > 0 || behindCount > 0
    }

    /// Human-readable summary line for the most urgent issue
    var urgentSummary: String? {
        if overdueCount > 0 {
            if let goal = mostUrgentGoal {
                return "\(goal.name) is overdue — \(DS.Format.money(goal.remainingAmount)) still needed"
            }
            return "\(overdueCount) goal\(overdueCount == 1 ? " is" : "s are") overdue"
        }
        if behindCount > 0 {
            if let goal = mostUrgentGoal {
                return "\(goal.name) is behind schedule"
            }
            return "\(behindCount) goal\(behindCount == 1 ? " is" : "s are") behind schedule"
        }
        return nil
    }
}

// MARK: - Goal Projection Model

struct GoalProjection {
    let averageMonthly: Int
    let averagePerContribution: Int
    let weeklyRate: Int
    let totalContributed: Int
    let totalWithdrawn: Int
    let contributionCount: Int
    let estimatedCompletion: Date?
    let requiredMonthly: Int?
    let paceStatus: PaceStatus

    enum PaceStatus {
        case ahead, onTrack, behind, completed, noDeadline

        var label: String {
            switch self {
            case .ahead: return "Ahead of schedule"
            case .onTrack: return "On track"
            case .behind: return "Behind schedule"
            case .completed: return "Completed"
            case .noDeadline: return "No deadline"
            }
        }

        var icon: String {
            switch self {
            case .ahead: return "arrow.up.right"
            case .onTrack: return "checkmark.circle"
            case .behind: return "exclamationmark.triangle"
            case .completed: return "checkmark.circle.fill"
            case .noDeadline: return "clock"
            }
        }
    }
}
