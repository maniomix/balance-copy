import SwiftUI

// MARK: - Goals Dashboard Card

/// Compact goals summary card for the main Dashboard.
/// Shows top active goals with progress. Taps into full GoalsOverviewView.
struct GoalsDashboardCard: View {

    @StateObject private var goalManager = GoalManager.shared

    var body: some View {
        if !goalManager.goals.isEmpty {
            NavigationLink(destination: GoalsOverviewView()) {
                DS.Card {
                    VStack(alignment: .leading, spacing: 10) {
                        // Header
                        HStack {
                            HStack(spacing: 5) {
                                Image(systemName: "target")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DS.Colors.accent)
                                Text("Goals")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                            }

                            Spacer()

                            // Overall progress
                            Text("\(Int(goalManager.overallProgress * 100))%")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.accent)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.Colors.subtext.opacity(0.4))
                        }

                        // Total saved / target
                        HStack(spacing: 4) {
                            Text(DS.Format.money(goalManager.totalSaved))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.text)
                            Text("/ \(DS.Format.money(goalManager.totalTarget))")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Colors.subtext)
                        }

                        // Overall progress bar
                        GoalProgressBar(progress: goalManager.overallProgress, height: 4)

                        // Top 3 goals
                        ForEach(goalManager.goalsByPriority.prefix(3)) { goal in
                            HStack(spacing: 10) {
                                Image(systemName: goal.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(GoalColorHelper.color(for: goal.colorToken))
                                    .frame(width: 24, height: 24)
                                    .background(GoalColorHelper.color(for: goal.colorToken).opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(goal.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(DS.Colors.text)
                                            .lineLimit(1)

                                        Spacer()

                                        Text("\(goal.progressPercent)%")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundStyle(GoalColorHelper.color(for: goal.colorToken))
                                    }

                                    GoalProgressBar(progress: goal.progress, height: 3, tintColor: GoalColorHelper.color(for: goal.colorToken))
                                }
                            }
                        }

                        // Pacing summary for top goals
                        ForEach(goalManager.goalsByPriority.prefix(3)) { goal in
                            if let required = goal.requiredMonthlySaving, required > 0,
                               goal.trackingStatus == .behind || goal.trackingStatus == .onTrack {
                                HStack(spacing: 4) {
                                    Image(systemName: goal.trackingStatus == .behind
                                        ? "exclamationmark.triangle"
                                        : "arrow.up.circle")
                                        .font(.system(size: 9))
                                    Text("\(goal.name): \(DS.Format.money(required))/mo needed")
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(goal.trackingStatus == .behind ? DS.Colors.warning : DS.Colors.subtext)
                            }
                        }

                        // Behind/overdue summary
                        let snapshot = goalManager.planningSnapshot
                        if snapshot.overdueCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                Text("\(snapshot.overdueCount) overdue")
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(DS.Colors.danger)
                            .padding(.top, 2)
                        } else if snapshot.behindCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                Text("\(snapshot.behindCount) behind schedule")
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(DS.Colors.warning)
                            .padding(.top, 2)
                        }
                        // Upcoming deadline warning
                        else if let next = goalManager.upcomingDeadlines.first,
                           let date = next.targetDate {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10))
                                Text("\(next.name) due \(date, format: .dateTime.month(.abbreviated).day())")
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(DS.Colors.warning)
                            .padding(.top, 2)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .task {
                if goalManager.goals.isEmpty {
                    await goalManager.fetchGoals()
                }
            }
        }
    }
}
