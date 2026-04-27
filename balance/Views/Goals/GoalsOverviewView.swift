import SwiftUI

// MARK: - Goals Overview View

struct GoalsOverviewView: View {

    @Binding var store: Store
    @StateObject private var goalManager = GoalManager.shared
    @StateObject private var householdManager = HouseholdManager.shared
    @State private var showCreateGoal = false
    @State private var goalToEdit: Goal?
    @State private var showCompleted = false
    @State private var showArchived = false
    @State private var sortBy: SortOption = .priority

    enum SortOption: String, CaseIterable, Identifiable {
        case priority = "Priority"
        case eta = "ETA"
        case progress = "Progress"
        case recent = "Recent"

        var id: String { rawValue }
        var iconName: String {
            switch self {
            case .priority: return "star"
            case .eta:      return "clock"
            case .progress: return "chart.bar"
            case .recent:   return "calendar"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !goalManager.goals.isEmpty || goalManager.isLoading {
                    summaryCard
                }

                if !activeGoals.isEmpty {
                    sortPills
                }

                if !almostThere.isEmpty {
                    section(title: "Almost there", systemImage: "sparkles") {
                        ForEach(almostThere) { goal in
                            goalRowLink(goal)
                        }
                    }
                }

                if !mainActive.isEmpty {
                    section(title: "Active", systemImage: "target") {
                        ForEach(mainActive) { goal in
                            goalRowLink(goal)
                        }
                    }
                }

                if !goalManager.behindGoals.isEmpty {
                    behindAlert
                }

                if !householdManager.activeSharedGoals.isEmpty {
                    section(title: "Household", systemImage: "person.2.fill") {
                        ForEach(householdManager.activeSharedGoals) { shared in
                            NavigationLink(destination: HouseholdOverviewView(store: $store)) {
                                SharedGoalRowView(goal: shared)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !goalManager.pausedGoals.isEmpty {
                    section(title: "Paused", systemImage: "pause.circle") {
                        ForEach(goalManager.pausedGoals) { goal in
                            goalRowLink(goal)
                        }
                    }
                }

                if !goalManager.completedGoals.isEmpty {
                    DisclosureGroup(isExpanded: $showCompleted) {
                        VStack(spacing: 8) {
                            ForEach(goalManager.completedGoals) { goal in
                                goalRowLink(goal)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("Completed (\(goalManager.completedGoals.count))",
                              systemImage: "checkmark.circle.fill")
                            .font(DS.Typography.section)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    .tint(DS.Colors.subtext)
                    .padding(.horizontal, 4)
                }

                if !goalManager.archivedGoals.isEmpty {
                    DisclosureGroup(isExpanded: $showArchived) {
                        VStack(spacing: 8) {
                            ForEach(goalManager.archivedGoals) { goal in
                                goalRowLink(goal)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("Archived (\(goalManager.archivedGoals.count))",
                              systemImage: "archivebox")
                            .font(DS.Typography.section)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    .tint(DS.Colors.subtext)
                    .padding(.horizontal, 4)
                }

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
                .accessibilityLabel("Create goal")
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

    // MARK: - Section helper

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(DS.Typography.section)
                .foregroundStyle(DS.Colors.text)
                .padding(.horizontal, 4)
            content()
        }
    }

    @ViewBuilder
    private func goalRowLink(_ goal: Goal) -> some View {
        NavigationLink(destination: GoalDetailView(goal: goal, store: $store)) {
            GoalCardView(goal: goal)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                goalToEdit = goal
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            if !goal.isArchived {
                Button {
                    Task { await archive(goal) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            } else {
                Button {
                    Task { await unarchive(goal) }
                } label: {
                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                }
            }

            Button(role: .destructive) {
                Task { _ = await goalManager.deleteGoal(goal) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Derived collections

    /// Active goals after the user's chosen sort.
    private var activeGoals: [Goal] {
        let base: [Goal]
        switch sortBy {
        case .priority:
            base = goalManager.goalsByPriority
        case .eta:
            base = goalManager.activeGoals.sorted { lhs, rhs in
                switch (lhs.targetDate, rhs.targetDate) {
                case let (l?, r?): return l < r
                case (_?, nil):    return true
                case (nil, _?):    return false
                default:           return lhs.createdAt > rhs.createdAt
                }
            }
        case .progress:
            base = goalManager.activeGoals.sorted { $0.progress > $1.progress }
        case .recent:
            base = goalManager.activeGoals.sorted { $0.createdAt > $1.createdAt }
        }
        return base
    }

    /// Active goals at >= 80% but not yet complete.
    private var almostThere: [Goal] {
        activeGoals.filter { $0.progress >= 0.8 && $0.progress < 1.0 }
    }

    /// Active goals not in the "almost there" bucket.
    private var mainActive: [Goal] {
        let almostIds = Set(almostThere.map(\.id))
        return activeGoals.filter { !almostIds.contains($0.id) }
    }

    // MARK: - Sort pills

    private var sortPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SortOption.allCases) { option in
                    sortPill(option)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func sortPill(_ option: SortOption) -> some View {
        let selected = sortBy == option
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { sortBy = option }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option.iconName)
                    .font(.system(size: 10, weight: .semibold))
                Text(option.rawValue)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Color.white : DS.Colors.subtext)
            .background(
                Capsule()
                    .fill(selected ? DS.Colors.accent : DS.Colors.surface2)
            )
            .overlay(
                Capsule()
                    .stroke(selected ? Color.clear : DS.Colors.grid, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(option.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Summary

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

                GoalProgressBar(progress: goalManager.overallProgress, height: 6)

                HStack {
                    Text("\(goalManager.activeGoals.count) active")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)

                    if !goalManager.completedGoals.isEmpty {
                        Text("·").foregroundStyle(DS.Colors.subtext)
                        Text("\(goalManager.completedGoals.count) done")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.positive)
                    }

                    Spacer()

                    Text(progressPercentText)
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(goalManager.overallProgress > 0
                                         ? DS.Colors.accent
                                         : DS.Colors.subtext)
                }
            }
        }
    }

    private var progressPercentText: String {
        "\(Int(goalManager.overallProgress * 100))%"
    }

    // MARK: - Behind alert

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
                    Text(goalManager.behindGoals.map(\.name).joined(separator: ", "))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 44))
                .foregroundStyle(DS.Colors.subtext.opacity(0.4))

            Text("No goals yet")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.text)

            Text("Pick a starting point or build something custom.")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                templateButton(.emergencyFund, label: "Emergency", subtitle: "3–6 months")
                templateButton(.vacation,     label: "Vacation",  subtitle: "Trip fund")
                templateButton(.home,         label: "Home",      subtitle: "Down payment")
                templateButton(.custom,       label: "Custom",    subtitle: "Anything")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            Button {
                showCreateGoal = true
            } label: {
                Label("Create Goal", systemImage: "plus")
                    .font(DS.Typography.body.weight(.semibold))
            }
            .buttonStyle(DS.PrimaryButton())
            .padding(.top, 4)
        }
        .padding(.vertical, 32)
    }

    private func templateButton(_ type: GoalType, label: String, subtitle: String) -> some View {
        Button {
            showCreateGoal = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: type.defaultIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(GoalColorHelper.color(for: type.defaultColor))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Colors.subtext)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Colors.grid, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mutations

    private func archive(_ goal: Goal) async {
        var updated = goal
        updated.isArchived = true
        _ = await goalManager.updateGoal(updated)
    }

    private func unarchive(_ goal: Goal) async {
        var updated = goal
        updated.isArchived = false
        _ = await goalManager.updateGoal(updated)
    }
}

// MARK: - Goal Card View

struct GoalCardView: View {
    let goal: Goal

    private var themeColor: Color {
        GoalColorHelper.color(for: goal.colorToken)
    }

    private var accessibilitySummary: String {
        var parts = ["\(goal.name), \(goal.progressPercent) percent of \(DS.Format.money(goal.targetAmount))"]
        if let days = goal.daysRemaining {
            if days >= 0 { parts.append("\(days) days remaining") }
            else { parts.append("\(abs(days)) days overdue") }
        }
        if goal.isCompleted { parts.append("completed") }
        else if goal.isArchived { parts.append("archived") }
        else if goal.pausedAt != nil { parts.append("paused") }
        return parts.joined(separator: ", ")
    }

    /// Identity color is suppressed when there's no progress yet, per
    /// `feedback_one_accent_per_card` (0% values use subtext, not saturated tint).
    private var progressTint: Color {
        goal.progress > 0 ? themeColor : DS.Colors.subtext.opacity(0.6)
    }

    private var percentTint: Color {
        goal.progress > 0 ? themeColor : DS.Colors.subtext
    }

    var body: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: goal.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(themeColor)
                        .frame(width: 32, height: 32)
                        .background(
                            themeColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.name)
                            .font(DS.Typography.body.weight(.semibold))
                            .foregroundStyle(DS.Colors.text)

                        Text(secondaryLabel)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(DS.Format.money(goal.currentAmount))
                            .font(DS.Typography.number)
                            .foregroundStyle(DS.Colors.text)
                        Text("of \(DS.Format.money(goal.targetAmount))")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }

                GoalProgressBar(progress: goal.progress, height: 5, tintColor: progressTint)

                HStack(spacing: 8) {
                    Text("\(goal.progressPercent)%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(percentTint)

                    if let etaText {
                        Text("·").foregroundStyle(DS.Colors.subtext)
                        Text(etaText)
                            .font(.system(size: 11))
                            .foregroundStyle(etaColor)
                    }

                    Spacer()

                    statusBadge
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var secondaryLabel: String {
        if goal.isArchived { return "Archived" }
        if goal.pausedAt != nil { return "Paused" }
        return goal.type.displayName
    }

    private var etaText: String? {
        if goal.isCompleted { return nil }
        if let days = goal.daysRemaining {
            if days >= 0 { return "\(days)d left" }
            return "\(abs(days))d overdue"
        }
        return nil
    }

    private var etaColor: Color {
        guard let days = goal.daysRemaining else { return DS.Colors.subtext }
        if days < 0 { return DS.Colors.danger }
        if days <= 14 { return DS.Colors.warning }
        return DS.Colors.subtext
    }

    @ViewBuilder
    private var statusBadge: some View {
        if goal.isCompleted {
            badge("Done", systemImage: "checkmark.circle.fill", color: DS.Colors.positive)
        } else if goal.progress >= 0.8 && goal.progress < 1.0 {
            badge("Almost there", systemImage: "sparkles", color: DS.Colors.positive)
        } else {
            switch goal.trackingStatus {
            case .behind:
                badge("Behind", systemImage: "exclamationmark.triangle", color: DS.Colors.danger)
            case .ahead:
                badge("Ahead", systemImage: "arrow.up.right", color: DS.Colors.positive)
            case .onTrack, .completed, .noTarget:
                EmptyView()
            }
        }
    }

    private func badge(_ label: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Shared Goal Row

/// Compact row for a household-shared goal. Reads `SharedGoal` directly
/// (no model unification with `Goal`). Tap navigates to
/// `HouseholdOverviewView` where contributions live.
struct SharedGoalRowView: View {
    let goal: SharedGoal

    private var tint: Color { DS.Colors.accent }

    private var progressTint: Color {
        goal.progress > 0 ? tint : DS.Colors.subtext.opacity(0.6)
    }

    var body: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: goal.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(
                            tint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.name)
                            .font(DS.Typography.body.weight(.semibold))
                            .foregroundStyle(DS.Colors.text)
                        Text("Shared")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(DS.Format.money(goal.currentAmount))
                            .font(DS.Typography.number)
                            .foregroundStyle(DS.Colors.text)
                        Text("of \(DS.Format.money(goal.targetAmount))")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }

                GoalProgressBar(progress: goal.progress, height: 5, tintColor: progressTint)

                HStack {
                    Text("\(goal.progressPercent)%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(goal.progress > 0 ? tint : DS.Colors.subtext)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext.opacity(0.5))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(goal.name), shared, \(goal.progressPercent) percent of \(DS.Format.money(goal.targetAmount)). Opens household.")
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
        case "warning":  return DS.Colors.warning
        case "danger":   return DS.Colors.danger
        case "accent":   return DS.Colors.accent
        case "subtext":  return DS.Colors.subtext
        case "blue":     return Color(hexValue: 0x4A90D9)
        case "purple":   return Color(hexValue: 0x8B5CF6)
        case "teal":     return Color(hexValue: 0x14B8A6)
        case "pink":     return Color(hexValue: 0xEC4899)
        case "indigo":   return Color(hexValue: 0x6366F1)
        default:         return DS.Colors.accent
        }
    }
}
