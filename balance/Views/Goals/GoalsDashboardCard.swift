import SwiftUI

// MARK: - Goals Dashboard Card

/// Compact goals summary for the main Dashboard. Top 2 active goals with
/// per-row identity color and one contextual subline. Tap → GoalsOverviewView.
struct GoalsDashboardCard: View {

    @Binding var store: Store
    @StateObject private var goalManager = GoalManager.shared

    var body: some View {
        if !goalManager.goals.isEmpty {
            NavigationLink(destination: GoalsOverviewView(store: $store)) {
                DS.Card {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        GoalProgressBar(progress: goalManager.overallProgress, height: 5)
                        topGoalsList
                        if let subline = contextualSubline {
                            subline
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Goals: \(DS.Format.money(goalManager.totalSaved)) of \(DS.Format.money(goalManager.totalTarget)) across \(goalManager.activeGoals.count) goals")
            .accessibilityHint("Opens goals overview")
            .task {
                if goalManager.goals.isEmpty {
                    await goalManager.fetchGoals()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(DS.Format.money(goalManager.totalSaved))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                    Text("of \(DS.Format.money(goalManager.totalTarget))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                }
                Text("\(goalManager.activeGoals.count) tracked")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.Colors.subtext)
            }

            Spacer()

            progressRing
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Colors.subtext.opacity(0.4))
                .padding(.leading, 4)
        }
    }

    private var progressRing: some View {
        let progress = goalManager.overallProgress
        return ZStack {
            Circle()
                .stroke(DS.Colors.surface2, lineWidth: 4)
                .frame(width: 44, height: 44)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.001, progress)))
                .stroke(progress > 0 ? DS.Colors.accent : DS.Colors.subtext,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(progress > 0 ? DS.Colors.accent : DS.Colors.subtext)
        }
    }

    // MARK: - Top goals list

    private var topGoalsList: some View {
        VStack(spacing: 10) {
            ForEach(goalManager.goalsByPriority.prefix(2)) { goal in
                miniGoalRow(goal)
            }
        }
    }

    private func miniGoalRow(_ goal: Goal) -> some View {
        let tint = GoalColorHelper.color(for: goal.colorToken)
        let progressColor = goal.progress > 0 ? tint : DS.Colors.subtext.opacity(0.6)
        let percentColor: Color = goal.progress > 0 ? tint : DS.Colors.subtext

        return HStack(spacing: 10) {
            Image(systemName: goal.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(goal.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.text)
                        .lineLimit(1)

                    Spacer()

                    if let days = goal.daysRemaining, days >= 0, days <= 60 {
                        Text("\(days)d")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(days <= 14 ? DS.Colors.warning : DS.Colors.subtext)
                    }

                    Text("\(goal.progressPercent)%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(percentColor)
                }

                GoalProgressBar(progress: max(0.001, goal.progress), height: 4, tintColor: progressColor)
            }
        }
    }

    // MARK: - Contextual subline

    /// Shows the single most pressing item: overdue > behind > upcoming.
    /// Returns nil when nothing notable, keeping the card visually quiet.
    @ViewBuilder
    private var contextualSubline: (some View)? {
        let snapshot = goalManager.planningSnapshot

        if snapshot.overdueCount > 0 {
            sublineRow(
                icon: "exclamationmark.triangle.fill",
                text: "\(snapshot.overdueCount) overdue",
                color: DS.Colors.danger
            )
        } else if snapshot.behindCount > 0 {
            sublineRow(
                icon: "exclamationmark.triangle.fill",
                text: "\(snapshot.behindCount) behind schedule",
                color: DS.Colors.warning
            )
        } else if let next = goalManager.upcomingDeadlines.first,
                  let date = next.targetDate {
            sublineRow(
                icon: "clock",
                text: "\(next.name) due \(date.formatted(.dateTime.month(.abbreviated).day()))",
                color: DS.Colors.warning
            )
        } else {
            EmptyView()
        }
    }

    private func sublineRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 10)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.top, 2)
    }
}
