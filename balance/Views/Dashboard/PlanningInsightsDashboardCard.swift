import SwiftUI

// MARK: - Planning Insights Dashboard Card

/// Surfaces the most important money-guidance insights on the Dashboard.
/// Combines signals from ForecastEngine and GoalManager to show
/// actionable alerts: overdue goals, overspending risk, recommended
/// contributions, and budget warnings.
///
/// Design: only shows when there's something worth saying. If everything
/// is on track, the card is hidden — no noise.
struct PlanningInsightsDashboardCard: View {

    @StateObject private var engine = ForecastEngine.shared
    @StateObject private var goalManager = GoalManager.shared

    var body: some View {
        let insights = buildInsights()

        if !insights.isEmpty {
            DS.Card {
                VStack(alignment: .leading, spacing: 10) {
                    // Header
                    HStack(spacing: 5) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Colors.warning)
                        Text("Planning Insights")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                        Spacer()
                        Text("\(insights.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Colors.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Colors.warning.opacity(0.12), in: Capsule())
                    }

                    ForEach(Array(insights.prefix(4).enumerated()), id: \.offset) { _, insight in
                        insightRow(insight)

                        if insight.id != insights.prefix(4).last?.id {
                            Divider().foregroundStyle(DS.Colors.grid)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Insight Row

    private func insightRow(_ insight: PlanningInsight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(insight.color)
                .frame(width: 24, height: 24)
                .background(insight.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(1)

                Text(insight.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.subtext)
                    .lineLimit(2)

                if let action = insight.actionLabel {
                    Text(action)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(insight.color)
                        .padding(.top, 1)
                }
            }
        }
    }

    // MARK: - Build Insights (deterministic, priority-ordered)

    private func buildInsights() -> [PlanningInsight] {
        var insights: [PlanningInsight] = []

        // ── Goal-based insights ──

        let snapshot = goalManager.planningSnapshot

        // 1. Overdue goals (highest priority)
        if snapshot.overdueCount > 0 {
            if let goal = snapshot.mostUrgentGoal, goal.isOverdue {
                insights.append(PlanningInsight(
                    icon: "exclamationmark.triangle.fill",
                    color: DS.Colors.danger,
                    title: "\(goal.name) is overdue",
                    detail: "\(DS.Format.money(goal.remainingAmount)) still needed — deadline passed \(daysAgoText(goal.targetDate))",
                    actionLabel: "Review goal →",
                    priority: 100
                ))
            }
        }

        // 2. Behind schedule goals
        let behindNonOverdue = goalManager.behindGoals.filter { !$0.isOverdue }
        if !behindNonOverdue.isEmpty {
            let goal = behindNonOverdue.sorted {
                ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture)
            }.first!
            let required = goal.requiredMonthlySaving ?? goal.remainingAmount
            insights.append(PlanningInsight(
                icon: "exclamationmark.triangle",
                color: DS.Colors.warning,
                title: "\(goal.name) is behind schedule",
                detail: "Need \(DS.Format.money(required))/mo to catch up — \(goal.progressPercent)% complete",
                actionLabel: behindNonOverdue.count > 1 ? "+\(behindNonOverdue.count - 1) more behind" : nil,
                priority: 90
            ))
        }

        // 3. Recommended monthly contribution
        if snapshot.totalRequiredMonthly > 0 && snapshot.activeGoalCount > 0 {
            insights.append(PlanningInsight(
                icon: "arrow.up.circle",
                color: DS.Colors.accent,
                title: "Save \(DS.Format.money(snapshot.totalRequiredMonthly)) this month",
                detail: "Total needed across \(snapshot.activeGoalCount) active goal\(snapshot.activeGoalCount == 1 ? "" : "s") to stay on track",
                actionLabel: nil,
                priority: 60
            ))
        }

        // ── Forecast-based insights ──

        if let f = engine.forecast {
            // 4. Overcommitted (bills + goals exceed remaining)
            if f.safeToSpend.isOvercommitted {
                insights.append(PlanningInsight(
                    icon: "xmark.shield.fill",
                    color: DS.Colors.danger,
                    title: "Over-committed by \(DS.Format.money(f.safeToSpend.overcommitAmount))",
                    detail: "Bills (\(DS.Format.money(f.safeToSpend.reservedForBills))) + goals (\(DS.Format.money(f.safeToSpend.reservedForGoals))) exceed remaining budget",
                    actionLabel: "Adjust goals or budget →",
                    priority: 95
                ))
            }

            // 5. Already over budget
            if f.currentRemaining < 0 {
                insights.append(PlanningInsight(
                    icon: "creditcard.trianglebadge.exclamationmark",
                    color: DS.Colors.danger,
                    title: "Over budget by \(DS.Format.money(abs(f.currentRemaining)))",
                    detail: "Spending has exceeded your \(f.budgetIsMissing ? "estimated" : "") budget for this month",
                    actionLabel: nil,
                    priority: 98
                ))
            }

            // 6. Negative 30-day projection
            if f.projected30Day < 0 && f.riskLevel == .highRisk {
                insights.append(PlanningInsight(
                    icon: "chart.line.downtrend.xyaxis",
                    color: DS.Colors.danger,
                    title: "30-day outlook is negative",
                    detail: "Budget remaining projected at \(DS.Format.money(f.projected30Day)) in 30 days",
                    actionLabel: "Reduce spending to stay positive",
                    priority: 85
                ))
            }

            // 7. Overdue bills
            if f.overdueBillCount > 0 {
                insights.append(PlanningInsight(
                    icon: "bell.badge.fill",
                    color: DS.Colors.warning,
                    title: "\(f.overdueBillCount) overdue bill\(f.overdueBillCount == 1 ? "" : "s")",
                    detail: "Past-due recurring payments may incur late fees",
                    actionLabel: nil,
                    priority: 80
                ))
            }

            // 8. No budget set warning
            if f.budgetIsMissing && f.safeToSpend.totalAmount > 0 {
                insights.append(PlanningInsight(
                    icon: "questionmark.circle",
                    color: DS.Colors.subtext,
                    title: "No budget set",
                    detail: "Safe-to-spend is estimated from your income history. Set a budget for better accuracy.",
                    actionLabel: "Set budget →",
                    priority: 30
                ))
            }

            // 9. Low data confidence warning
            if f.dataConfidence == .low {
                insights.append(PlanningInsight(
                    icon: "chart.bar.xaxis",
                    color: DS.Colors.subtext,
                    title: "Limited spending history",
                    detail: "Forecasts improve with more data. Keep tracking for accurate projections.",
                    actionLabel: nil,
                    priority: 20
                ))
            }
        }

        // Sort by priority (highest first) and return
        return insights.sorted { $0.priority > $1.priority }
    }

    // MARK: - Helpers

    private func daysAgoText(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        return "\(days) days ago"
    }
}

// MARK: - Planning Insight Model

private struct PlanningInsight: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let actionLabel: String?
    let priority: Int  // higher = more urgent, shown first
}
