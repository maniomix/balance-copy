import SwiftUI

// MARK: - Goal Detail View

struct GoalDetailView: View {

    let goal: Goal

    @StateObject private var goalManager = GoalManager.shared
    @State private var contributions: [GoalContribution] = []
    @State private var projection: GoalProjection?
    @State private var showAddContribution = false
    @State private var showWithdraw = false
    @State private var contributionAmountText = ""
    @State private var contributionNote = ""
    @State private var withdrawAmountText = ""
    @State private var withdrawNote = ""
    @State private var showEditSheet = false
    @State private var showAllContributions = false

    private var themeColor: Color {
        GoalColorHelper.color(for: goal.colorToken)
    }

    /// Live goal from GoalManager (reflects updates)
    private var liveGoal: Goal {
        goalManager.goals.first { $0.id == goal.id } ?? goal
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                progressCard
                projectionCard
                quickActions
                contributionSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .background(DS.Colors.bg.ignoresSafeArea())
        .navigationTitle(liveGoal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditSheet = true }
                    .foregroundStyle(DS.Colors.accent)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            CreateEditGoalView(mode: .edit(liveGoal))
        }
        .alert("Add Contribution", isPresented: $showAddContribution) {
            TextField("Amount", text: $contributionAmountText)
                .keyboardType(.decimalPad)
            TextField("Note (optional)", text: $contributionNote)
            Button("Cancel", role: .cancel) {
                contributionAmountText = ""
                contributionNote = ""
            }
            Button("Add") {
                Task { await addContribution() }
            }
        } message: {
            Text("Enter the amount to add toward \(liveGoal.name).")
        }
        .alert("Withdraw", isPresented: $showWithdraw) {
            TextField("Amount", text: $withdrawAmountText)
                .keyboardType(.decimalPad)
            TextField("Reason (optional)", text: $withdrawNote)
            Button("Cancel", role: .cancel) {
                withdrawAmountText = ""
                withdrawNote = ""
            }
            Button("Withdraw", role: .destructive) {
                Task { await withdraw() }
            }
        } message: {
            Text("Withdraw funds from \(liveGoal.name). Current balance: \(DS.Format.money(liveGoal.currentAmount))")
        }
        .task { await loadData() }
    }

    // MARK: - Progress Card

    private var progressCard: some View {
        DS.Card {
            VStack(spacing: 16) {
                // Icon + amount
                Image(systemName: liveGoal.icon)
                    .font(.title2)
                    .foregroundStyle(themeColor)
                    .frame(width: 50, height: 50)
                    .background(themeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(DS.Format.money(liveGoal.currentAmount))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)

                Text("of \(DS.Format.money(liveGoal.targetAmount))")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.subtext)

                // Progress bar
                GoalProgressBar(progress: liveGoal.progress, height: 8, tintColor: themeColor)

                HStack {
                    Text("\(liveGoal.progressPercent)%")
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(themeColor)

                    Spacer()

                    Text("\(DS.Format.money(liveGoal.remainingAmount)) remaining")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                }

                // Status badge
                if liveGoal.isCompleted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Goal completed")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Colors.positive)
                } else {
                    let status = liveGoal.trackingStatus
                    HStack(spacing: 6) {
                        Image(systemName: status.icon)
                            .font(.system(size: 11))
                        Circle()
                            .fill(statusColor(status))
                            .frame(width: 6, height: 6)
                        Text(status.label)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(statusColor(status))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor(status).opacity(0.1), in: Capsule())
                }

                // Days remaining
                if let days = liveGoal.daysRemaining {
                    if days > 0 {
                        Text("\(days) days remaining")
                            .font(DS.Typography.caption)
                            .foregroundStyle(days <= 14 ? DS.Colors.warning : DS.Colors.subtext)
                    } else if days < 0 {
                        Text("\(abs(days)) days overdue")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.danger)
                    } else {
                        Text("Due today")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.danger)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Projection Card

    private var projectionCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Projection")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                if let proj = projection {
                    VStack(spacing: 0) {
                        // Required monthly
                        if let required = proj.requiredMonthly, required > 0 {
                            projectionRow(
                                icon: "arrow.up.circle",
                                "Required monthly",
                                DS.Format.money(required),
                                color: DS.Colors.warning
                            )
                            Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 6)
                        }

                        // Average monthly
                        projectionRow(
                            icon: "chart.line.uptrend.xyaxis",
                            "Avg. monthly saving",
                            proj.averageMonthly > 0 ? DS.Format.money(proj.averageMonthly) : "—",
                            color: DS.Colors.accent
                        )

                        // Weekly rate
                        if proj.weeklyRate > 0 {
                            Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 6)
                            projectionRow(
                                icon: "calendar.badge.clock",
                                "Weekly pace (4w avg)",
                                DS.Format.money(proj.weeklyRate),
                                color: DS.Colors.subtext
                            )
                        }

                        // Estimated completion
                        if let est = proj.estimatedCompletion {
                            Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 6)
                            projectionRow(
                                icon: "flag.checkered",
                                "Est. completion",
                                est.formatted(.dateTime.month(.abbreviated).year()),
                                color: DS.Colors.positive
                            )
                        }

                        // Target date
                        if let target = liveGoal.targetDate {
                            Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 6)
                            projectionRow(
                                icon: "calendar",
                                "Target date",
                                target.formatted(.dateTime.month(.abbreviated).day().year()),
                                color: DS.Colors.subtext
                            )
                        }

                        // Pace status
                        Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 6)
                        HStack(spacing: 8) {
                            Image(systemName: proj.paceStatus.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(paceColor(proj.paceStatus))
                            Text("Status")
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.subtext)
                            Spacer()
                            Text(proj.paceStatus.label)
                                .font(DS.Typography.body.weight(.semibold))
                                .foregroundStyle(paceColor(proj.paceStatus))
                        }

                        // Contribution stats
                        if proj.contributionCount > 0 {
                            Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 6)
                            projectionRow(
                                icon: "number",
                                "Total contributions",
                                "\(proj.contributionCount)",
                                color: DS.Colors.subtext
                            )

                            if proj.totalWithdrawn > 0 {
                                Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 6)
                                projectionRow(
                                    icon: "arrow.down.circle",
                                    "Total withdrawn",
                                    DS.Format.money(proj.totalWithdrawn),
                                    color: DS.Colors.danger
                                )
                            }
                        }
                    }
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(DS.Colors.subtext)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }

                // Notes
                if let notes = liveGoal.notes, !notes.isEmpty {
                    Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 4)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "note.text")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Colors.subtext)
                        Text(notes)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
            }
        }
    }

    private func projectionRow(icon: String, _ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(label)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
            Spacer()
            Text(value)
                .font(DS.Typography.body.weight(.semibold))
                .foregroundStyle(DS.Colors.text)
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            if !liveGoal.isCompleted {
                Button {
                    showAddContribution = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Funds")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DS.PrimaryButton())
            }

            if liveGoal.currentAmount > 0 {
                Button {
                    showWithdraw = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                        Text("Withdraw")
                    }
                    .font(DS.Typography.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                    .foregroundStyle(DS.Colors.text)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Contributions Section

    private var contributionSection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Contributions")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    if contributions.count > 10 {
                        Button {
                            showAllContributions.toggle()
                        } label: {
                            Text(showAllContributions ? "Show Less" : "Show All")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.accent)
                        }
                    }
                }

                if contributions.isEmpty {
                    Text("No contributions yet")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    let items = showAllContributions ? contributions : Array(contributions.prefix(10))
                    ForEach(items) { c in
                        HStack {
                            // Source icon
                            Image(systemName: c.amount >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(c.amount >= 0 ? DS.Colors.positive : DS.Colors.danger)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(c.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                                        .font(DS.Typography.body.weight(.medium))
                                        .foregroundStyle(DS.Colors.text)

                                    if c.source != .manual {
                                        Text(c.source.rawValue.capitalized)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(DS.Colors.subtext)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(DS.Colors.surface2, in: Capsule())
                                    }
                                }

                                if let note = c.note, !note.isEmpty {
                                    Text(note)
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text("\(c.amount >= 0 ? "+" : "") \(DS.Format.money(abs(c.amount)))")
                                .font(DS.Typography.number)
                                .foregroundStyle(c.amount >= 0 ? DS.Colors.positive : DS.Colors.danger)
                        }

                        if c.id != items.last?.id {
                            Divider().foregroundStyle(DS.Colors.grid)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data

    private func loadData() async {
        contributions = await goalManager.fetchContributions(for: liveGoal)
        projection = await goalManager.projection(for: liveGoal)
    }

    private func addContribution() async {
        let cents = DS.Format.cents(from: contributionAmountText)
        guard cents > 0 else { return }
        _ = await goalManager.addContribution(
            to: liveGoal,
            amount: cents,
            note: contributionNote.isEmpty ? nil : contributionNote
        )
        contributionAmountText = ""
        contributionNote = ""
        await loadData()
    }

    private func withdraw() async {
        let cents = DS.Format.cents(from: withdrawAmountText)
        guard cents > 0 else { return }
        _ = await goalManager.withdrawContribution(
            from: liveGoal,
            amount: cents,
            note: withdrawNote.isEmpty ? nil : withdrawNote
        )
        withdrawAmountText = ""
        withdrawNote = ""
        await loadData()
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

    private func paceColor(_ pace: GoalProjection.PaceStatus) -> Color {
        switch pace {
        case .ahead: return DS.Colors.positive
        case .onTrack: return DS.Colors.accent
        case .behind: return DS.Colors.danger
        case .completed: return DS.Colors.positive
        case .noDeadline: return DS.Colors.subtext
        }
    }
}
