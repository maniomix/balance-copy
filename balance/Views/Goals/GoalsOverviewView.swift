import SwiftUI

// MARK: - Goals Overview View

struct GoalsOverviewView: View {

    @StateObject private var goalManager = GoalManager.shared
    @State private var showCreateGoal = false
    @State private var goalToEdit: Goal?
    @State private var showCompleted = false
    @State private var sortBy: SortOption = .priority

    enum SortOption: String, CaseIterable {
        case priority = "Priority"
        case newest = "Newest"
        case progress = "Progress"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Summary
                summaryCard

                // Active Goals
                if !sortedActiveGoals.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Active Goals")
                                .font(DS.Typography.section)
                                .foregroundStyle(DS.Colors.text)

                            Spacer()

                            Menu {
                                ForEach(SortOption.allCases, id: \.self) { option in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) { sortBy = option }
                                    } label: {
                                        HStack {
                                            Text(option.rawValue)
                                            if sortBy == option {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(sortBy.rawValue)
                                        .font(DS.Typography.caption)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundStyle(DS.Colors.subtext)
                            }
                        }
                        .padding(.horizontal, 4)

                        ForEach(sortedActiveGoals) { goal in
                            NavigationLink(destination: GoalDetailView(goal: goal)) {
                                GoalCardView(goal: goal)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { goalToEdit = goal } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    Task { _ = await goalManager.deleteGoal(goal) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                // Behind schedule alert
                if !goalManager.behindGoals.isEmpty {
                    behindAlert
                }

                // Completed
                if !goalManager.completedGoals.isEmpty {
                    DisclosureGroup(
                        isExpanded: $showCompleted,
                        content: {
                            VStack(spacing: 8) {
                                ForEach(goalManager.completedGoals) { goal in
                                    NavigationLink(destination: GoalDetailView(goal: goal)) {
                                        GoalCardView(goal: goal)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 8)
                        },
                        label: {
                            Text("Completed (\(goalManager.completedGoals.count))")
                                .font(DS.Typography.section)
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    )
                    .tint(DS.Colors.subtext)
                }

                // Empty State
                if goalManager.goals.isEmpty && !goalManager.isLoading {
                    emptyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .background(DS.Colors.bg.ignoresSafeArea())
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("goals")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateGoal = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DS.Colors.accent)
                }
            }
        }
        .sheet(isPresented: $showCreateGoal) {
            CreateEditGoalView(mode: .create)
        }
        .sheet(item: $goalToEdit) { goal in
            CreateEditGoalView(mode: .edit(goal))
        }
        .task {
            await goalManager.fetchGoals()
        }
        .refreshable {
            await goalManager.fetchGoals()
        }
    }

    // MARK: - Sorted Goals

    private var sortedActiveGoals: [Goal] {
        switch sortBy {
        case .priority:
            return goalManager.goalsByPriority
        case .newest:
            return goalManager.activeGoals
        case .progress:
            return goalManager.activeGoals.sorted { $0.progress > $1.progress }
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        DS.Card {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Saved")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                        Text(DS.Format.money(goalManager.totalSaved))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Colors.text)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Target")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                        Text(DS.Format.money(goalManager.totalTarget))
                            .font(DS.Typography.number)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }

                // Overall progress
                GoalProgressBar(progress: goalManager.overallProgress, height: 6)

                HStack {
                    Text("\(goalManager.activeGoals.count) active")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)

                    if !goalManager.completedGoals.isEmpty {
                        Text("·")
                            .foregroundStyle(DS.Colors.subtext)
                        Text("\(goalManager.completedGoals.count) done")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.positive)
                    }

                    Spacer()

                    Text("\(Int(goalManager.overallProgress * 100))%")
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(DS.Colors.accent)
                }
            }
        }
    }

    // MARK: - Behind Alert

    private var behindAlert: some View {
        DS.Card {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.Colors.warning)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(goalManager.behindGoals.count) goal\(goalManager.behindGoals.count > 1 ? "s" : "") behind schedule")
                        .font(DS.Typography.body.weight(.medium))
                        .foregroundStyle(DS.Colors.text)

                    Text(goalManager.behindGoals.map { $0.name }.joined(separator: ", "))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "target")
                .font(.system(size: 44))
                .foregroundStyle(DS.Colors.subtext.opacity(0.4))

            Text("No Goals Yet")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.text)

            Text("Set savings goals to track your progress toward things that matter.")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showCreateGoal = true
            } label: {
                Label("Create Goal", systemImage: "plus")
                    .font(DS.Typography.body.weight(.semibold))
            }
            .buttonStyle(DS.ColoredButton())
            .padding(.horizontal, 60)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Goal Card View

struct GoalCardView: View {
    let goal: Goal

    private var themeColor: Color {
        GoalColorHelper.color(for: goal.colorToken)
    }

    var body: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    // Icon with goal-specific color
                    Image(systemName: goal.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(themeColor)
                        .frame(width: 32, height: 32)
                        .background(themeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.name)
                            .font(DS.Typography.body.weight(.semibold))
                            .foregroundStyle(DS.Colors.text)

                        Text(goal.type.displayName)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }

                    Spacer()

                    // Status
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(DS.Format.money(goal.currentAmount))
                            .font(DS.Typography.number)
                            .foregroundStyle(DS.Colors.text)

                        Text("of \(DS.Format.money(goal.targetAmount))")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }

                // Progress bar with goal-specific color
                GoalProgressBar(progress: goal.progress, height: 5, tintColor: themeColor)

                // Bottom row
                HStack {
                    Text("\(goal.progressPercent)%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(themeColor)

                    Spacer()

                    if let days = goal.daysRemaining, days >= 0 {
                        Text("\(days)d left")
                            .font(.system(size: 11))
                            .foregroundStyle(days <= 14 ? DS.Colors.warning : DS.Colors.subtext)
                    } else if let date = goal.targetDate {
                        Text(date, format: .dateTime.month(.abbreviated).day().year())
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Colors.danger)
                    }

                    if goal.isCompleted {
                        Label("Done", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Colors.positive)
                    } else {
                        let status = goal.trackingStatus
                        HStack(spacing: 3) {
                            Image(systemName: status.icon)
                                .font(.system(size: 9))
                            Text(status.label)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(statusColor(status))
                    }
                }
            }
        }
    }

    private func statusColor(_ status: Goal.TrackingStatus) -> Color {
        switch status {
        case .ahead: return DS.Colors.positive
        case .onTrack: return DS.Colors.accent
        case .behind: return DS.Colors.danger
        case .completed: return DS.Colors.positive
        case .noTarget: return DS.Colors.subtext
        }
    }
}

// MARK: - Reusable Progress Bar

struct GoalProgressBar: View {
    let progress: Double
    var height: CGFloat = 5
    var tintColor: Color = DS.Colors.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(DS.Colors.surface2)
                    .frame(height: height)

                RoundedRectangle(cornerRadius: height / 2)
                    .fill(tintColor)
                    .frame(width: max(0, geo.size.width * min(progress, 1.0)), height: height)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Goal Color Helper

enum GoalColorHelper {
    static func color(for token: String) -> Color {
        switch token {
        case "positive": return DS.Colors.positive
        case "warning": return DS.Colors.warning
        case "danger": return DS.Colors.danger
        case "accent": return DS.Colors.accent
        case "subtext": return DS.Colors.subtext
        // Extended palette for goal variety
        case "blue": return Color(hexValue: 0x4A90D9)
        case "purple": return Color(hexValue: 0x8B5CF6)
        case "teal": return Color(hexValue: 0x14B8A6)
        case "pink": return Color(hexValue: 0xEC4899)
        case "indigo": return Color(hexValue: 0x6366F1)
        default: return DS.Colors.accent
        }
    }
}
