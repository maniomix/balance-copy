import SwiftUI

struct PlanningInsightsDashboardCard: View {

    @StateObject private var engine = ForecastEngine.shared
    @StateObject private var goalManager = GoalManager.shared

    var body: some View {
        let insights = buildInsights()

        if !insights.isEmpty {
            DS.Card {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Header ──
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Colors.warning)
                            .frame(width: 34, height: 34)
                            .background(DS.Colors.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Planning Insights")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.Colors.text)
                            Text("\(insights.count) item\(insights.count == 1 ? "" : "s") need attention")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DS.Colors.subtext)
                        }

                        Spacer()

                        // Severity badge — show highest level
                        let topColor = insights.first?.color ?? DS.Colors.warning
                        Circle()
                            .fill(topColor.opacity(0.15))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: insights.first?.icon ?? "exclamationmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(topColor)
                            )
                    }
                    .padding(.bottom, 12)

                    // ── Insight rows ──
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(insights.prefix(4).enumerated()), id: \.offset) { idx, insight in
                            if idx > 0 {
                                Rectangle()
                                    .fill(DS.Colors.grid.opacity(0.6))
                                    .frame(height: 0.5)
                                    .padding(.leading, 36)
                            }
                            insightRow(insight)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Insight Row

    private func insightRow(_ insight: PlanningInsight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(insight.color)
                .frame(width: 3, height: 36)

            // Icon
            Image(systemName: insight.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(insight.color)
                .frame(width: 22, height: 22)
                .background(insight.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.top, 1)

            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(1)

                Text(insight.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.subtext)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let action = insight.actionLabel {
                    Text(action)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(insight.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(insight.color.opacity(0.1), in: Capsule())
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Build Insights

    private func buildInsights() -> [PlanningInsight] {
        var insights: [PlanningInsight] = []
        let snapshot = goalManager.planningSnapshot

        if snapshot.overdueCount > 0, let goal = snapshot.mostUrgentGoal, goal.isOverdue {
            insights.append(PlanningInsight(
                icon: "exclamationmark.triangle.fill",
                color: DS.Colors.danger,
                title: "\(goal.name) is overdue",
                detail: "\(DS.Format.money(goal.remainingAmount)) still needed — deadline passed \(daysAgoText(goal.targetDate))",
                actionLabel: "Review goal",
                priority: 100
            ))
        }

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

        if snapshot.totalRequiredMonthly > 0 && snapshot.activeGoalCount > 0 {
            insights.append(PlanningInsight(
                icon: "arrow.up.circle",
                color: DS.Colors.accent,
                title: "Save \(DS.Format.money(snapshot.totalRequiredMonthly)) this month",
                detail: "Needed across \(snapshot.activeGoalCount) active goal\(snapshot.activeGoalCount == 1 ? "" : "s") to stay on track",
                actionLabel: nil,
                priority: 60
            ))
        }

        if let f = engine.forecast {
            if f.safeToSpend.isOvercommitted {
                insights.append(PlanningInsight(
                    icon: "xmark.shield.fill",
                    color: DS.Colors.danger,
                    title: "Over-committed by \(DS.Format.money(f.safeToSpend.overcommitAmount))",
                    detail: "Bills (\(DS.Format.money(f.safeToSpend.reservedForBills))) + goals (\(DS.Format.money(f.safeToSpend.reservedForGoals))) exceed remaining budget",
                    actionLabel: "Adjust goals or budget",
                    priority: 95
                ))
            }

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

            if f.projected30Day < 0 && f.riskLevel == .highRisk {
                insights.append(PlanningInsight(
                    icon: "chart.line.downtrend.xyaxis",
                    color: DS.Colors.danger,
                    title: "30-day outlook is negative",
                    detail: "Projected at \(DS.Format.money(f.projected30Day)) — reduce spending to stay positive",
                    actionLabel: nil,
                    priority: 85
                ))
            }

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

            if f.budgetIsMissing && f.safeToSpend.totalAmount > 0 {
                insights.append(PlanningInsight(
                    icon: "questionmark.circle",
                    color: DS.Colors.subtext,
                    title: "No budget set",
                    detail: "Safe-to-spend is estimated from income history. Set a budget for better accuracy.",
                    actionLabel: "Set budget",
                    priority: 30
                ))
            }

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

        return insights.sorted { $0.priority > $1.priority }
    }

    private func daysAgoText(_ date: Date?) -> String {
        guard let date else { return "" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        return "\(days) days ago"
    }
}

// MARK: - Model

private struct PlanningInsight: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let actionLabel: String?
    let priority: Int
}
