import SwiftUI
import Charts

// MARK: - Goal Detail View

struct GoalDetailView: View {

    let goal: Goal
    @Binding var store: Store

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
    @State private var showRulesSheet = false
    @State private var showAllContributions = false
    @State private var failureMessage: String?

    private var themeColor: Color {
        GoalColorHelper.color(for: liveGoal.colorToken)
    }

    private var liveGoal: Goal {
        goalManager.goals.first { $0.id == goal.id } ?? goal
    }

    /// Active (non-reversed) contributions, newest first.
    private var activeContributions: [GoalContribution] {
        contributions.filter { !$0.isReversed }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                heroCard
                quickActions
                paceChart
                projectionCard
                rulesCard
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
        .sheet(isPresented: $showRulesSheet) {
            GoalRulesView(goal: liveGoal, store: $store)
        }
        .alert("Add Contribution", isPresented: $showAddContribution) {
            TextField("Amount", text: $contributionAmountText).keyboardType(.decimalPad)
            TextField("Note (optional)", text: $contributionNote)
            Button("Cancel", role: .cancel) { resetAddFields() }
            Button("Add") { Task { await addContribution() } }
        } message: {
            Text("Add to \(liveGoal.name).")
        }
        .alert("Withdraw", isPresented: $showWithdraw) {
            TextField("Amount", text: $withdrawAmountText).keyboardType(.decimalPad)
            TextField("Reason (optional)", text: $withdrawNote)
            Button("Cancel", role: .cancel) { resetWithdrawFields() }
            Button("Withdraw", role: .destructive) { Task { await withdraw() } }
        } message: {
            Text("Current balance: \(DS.Format.money(liveGoal.currentAmount))")
        }
        .alert(
            "Couldn't update goal",
            isPresented: Binding(
                get: { failureMessage != nil },
                set: { if !$0 { failureMessage = nil } }
            ),
            presenting: failureMessage
        ) { _ in
            Button("OK", role: .cancel) { failureMessage = nil }
        } message: { msg in
            Text(msg)
        }
        .task { await loadData() }
    }

    // MARK: - Hero (progress ring)

    private var heroCard: some View {
        DS.Card {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(DS.Colors.surface2, lineWidth: 12)
                        .frame(width: 168, height: 168)

                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.001, liveGoal.progress)))
                        .stroke(themeColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 168, height: 168)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.4), value: liveGoal.progress)

                    VStack(spacing: 2) {
                        Image(systemName: liveGoal.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(themeColor)
                            .padding(.bottom, 2)

                        Text(DS.Format.money(liveGoal.currentAmount))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Colors.text)

                        Text("\(liveGoal.progressPercent)%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(liveGoal.progress > 0 ? themeColor : DS.Colors.subtext)
                    }
                }

                VStack(spacing: 4) {
                    Text("of \(DS.Format.money(liveGoal.targetAmount))")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)

                    Text("\(DS.Format.money(liveGoal.remainingAmount)) remaining")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                }

                heroBadge

                if let days = liveGoal.daysRemaining {
                    deadlineLabel(days: days)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(liveGoal.name): \(DS.Format.money(liveGoal.currentAmount)) of \(DS.Format.money(liveGoal.targetAmount)), \(liveGoal.progressPercent) percent")
        }
    }

    @ViewBuilder
    private var heroBadge: some View {
        if liveGoal.isCompleted {
            badgeView("Goal completed", systemImage: "checkmark.circle.fill", color: DS.Colors.positive)
        } else if liveGoal.isArchived {
            badgeView("Archived", systemImage: "archivebox", color: DS.Colors.subtext)
        } else if liveGoal.pausedAt != nil {
            badgeView("Paused", systemImage: "pause.circle", color: DS.Colors.subtext)
        } else if liveGoal.progress >= 0.8 && liveGoal.progress < 1.0 {
            badgeView("Almost there", systemImage: "sparkles", color: DS.Colors.positive)
        } else {
            let s = liveGoal.trackingStatus
            switch s {
            case .ahead, .behind, .onTrack:
                badgeView(s.label, systemImage: s.icon, color: trackingColor(s))
            case .completed, .noTarget:
                EmptyView()
            }
        }
    }

    private func badgeView(_ label: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
            Text(label).font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func deadlineLabel(days: Int) -> some View {
        Group {
            if days > 0 {
                Text("\(days) day\(days == 1 ? "" : "s") to deadline")
                    .foregroundStyle(days <= 14 ? DS.Colors.warning : DS.Colors.subtext)
            } else if days < 0 {
                Text("\(abs(days)) day\(abs(days) == 1 ? "" : "s") overdue")
                    .foregroundStyle(DS.Colors.danger)
            } else {
                Text("Due today").foregroundStyle(DS.Colors.danger)
            }
        }
        .font(DS.Typography.caption)
    }

    private func trackingColor(_ status: Goal.TrackingStatus) -> Color {
        switch status {
        case .ahead, .completed: return DS.Colors.positive
        case .onTrack:           return DS.Colors.accent
        case .behind:            return DS.Colors.danger
        case .noTarget:          return DS.Colors.subtext
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            if !liveGoal.isCompleted && !liveGoal.isArchived {
                Button {
                    showAddContribution = true
                } label: {
                    Label("Add Funds", systemImage: "plus.circle.fill")
                        .font(DS.Typography.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DS.PrimaryButton())
                .accessibilityLabel("Add funds to \(liveGoal.name)")
                .accessibilityHint("Opens an amount entry alert")
            }

            if liveGoal.currentAmount > 0 {
                Button {
                    showWithdraw = true
                } label: {
                    Label("Withdraw", systemImage: "arrow.down.circle")
                        .font(DS.Typography.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(DS.Colors.text)
                        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(DS.Colors.grid, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Withdraw from \(liveGoal.name)")
                .accessibilityHint("Current balance \(DS.Format.money(liveGoal.currentAmount))")
            }
        }
    }

    // MARK: - Pace chart (last 6 months)

    private struct MonthBucket: Identifiable {
        let id = UUID()
        let monthStart: Date
        let amount: Int
    }

    private var monthlyBuckets: [MonthBucket] {
        let cal = Calendar.current
        guard let sixMonthsAgo = cal.date(byAdding: .month, value: -5, to: Date()) else { return [] }
        let startOfWindow = cal.dateInterval(of: .month, for: sixMonthsAgo)?.start ?? sixMonthsAgo

        // Build empty buckets for each of the last 6 months.
        var buckets: [Date: Int] = [:]
        for offset in 0..<6 {
            if let d = cal.date(byAdding: .month, value: offset, to: startOfWindow),
               let monthStart = cal.dateInterval(of: .month, for: d)?.start {
                buckets[monthStart] = 0
            }
        }

        // Sum positive non-reversed contributions into their month bucket.
        for c in contributions where !c.isReversed && c.amount > 0 && c.createdAt >= startOfWindow {
            if let monthStart = cal.dateInterval(of: .month, for: c.createdAt)?.start {
                buckets[monthStart, default: 0] += c.amount
            }
        }

        return buckets.keys.sorted().map { MonthBucket(monthStart: $0, amount: buckets[$0] ?? 0) }
    }

    @ViewBuilder
    private var paceChart: some View {
        let buckets = monthlyBuckets
        let total = buckets.reduce(0) { $0 + $1.amount }
        if total > 0 {
            DS.Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Pace")
                            .font(DS.Typography.section)
                            .foregroundStyle(DS.Colors.text)
                        Spacer()
                        Text("Last 6 months")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }

                    Chart(buckets) { bucket in
                        BarMark(
                            x: .value("Month", bucket.monthStart, unit: .month),
                            y: .value("Saved", Double(bucket.amount) / 100.0)
                        )
                        .foregroundStyle(themeColor.gradient)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month)) { value in
                            AxisValueLabel(format: .dateTime.month(.narrow))
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(DS.Colors.grid)
                            AxisValueLabel().foregroundStyle(DS.Colors.subtext)
                        }
                    }
                    .frame(height: 140)
                }
            }
        }
    }

    // MARK: - Projection card

    private var projectionCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Projection")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                if let proj = projection {
                    if let required = proj.requiredMonthly, required > 0 {
                        projectionRow("arrow.up.circle", "Required monthly",
                                      DS.Format.money(required), color: DS.Colors.warning)
                        Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 4)
                    }

                    projectionRow("chart.line.uptrend.xyaxis", "Avg monthly",
                                  proj.averageMonthly > 0 ? DS.Format.money(proj.averageMonthly) : "—",
                                  color: DS.Colors.accent)

                    if proj.weeklyRate > 0 {
                        Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 4)
                        projectionRow("calendar.badge.clock", "Weekly pace (4w)",
                                      DS.Format.money(proj.weeklyRate), color: DS.Colors.subtext)
                    }

                    if let est = proj.estimatedCompletion {
                        Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 4)
                        projectionRow("flag.checkered", "Est. completion",
                                      est.formatted(.dateTime.month(.abbreviated).year()),
                                      color: DS.Colors.positive)
                    }

                    if let target = liveGoal.targetDate {
                        Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 4)
                        projectionRow("calendar", "Deadline",
                                      target.formatted(.dateTime.month(.abbreviated).day().year()),
                                      color: DS.Colors.subtext)
                    }

                    if liveGoal.originalTargetAmount != liveGoal.targetAmount {
                        Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 4)
                        projectionRow("arrow.left.arrow.right", "Original target",
                                      DS.Format.money(liveGoal.originalTargetAmount),
                                      color: DS.Colors.subtext)
                    }

                    if proj.totalWithdrawn > 0 {
                        Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 4)
                        projectionRow("arrow.down.circle", "Total withdrawn",
                                      DS.Format.money(proj.totalWithdrawn),
                                      color: DS.Colors.danger)
                    }
                } else {
                    HStack {
                        Spacer()
                        ProgressView().tint(DS.Colors.subtext)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }

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

    private func projectionRow(_ icon: String, _ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color)
            Text(label).font(DS.Typography.body).foregroundStyle(DS.Colors.subtext)
            Spacer()
            Text(value).font(DS.Typography.body.weight(.semibold)).foregroundStyle(DS.Colors.text)
        }
    }

    // MARK: - Rules card

    private var rulesForGoal: [GoalAllocationRule] {
        store.goalAllocationRules.filter { $0.goalId == liveGoal.id }
    }

    private var rulesCard: some View {
        let rules = rulesForGoal
        let activeCount = rules.filter(\.isActive).count

        return Button {
            showRulesSheet = true
        } label: {
            DS.Card {
                HStack(spacing: 10) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                        .frame(width: 32, height: 32)
                        .background(DS.Colors.accent.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-save rules")
                            .font(DS.Typography.body.weight(.semibold))
                            .foregroundStyle(DS.Colors.text)
                        Text(rulesSubtitle(total: rules.count, active: activeCount))
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext.opacity(0.6))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func rulesSubtitle(total: Int, active: Int) -> String {
        if total == 0 { return "Suggest contributions when income arrives" }
        if active == total { return "\(total) active" }
        return "\(active) of \(total) active"
    }

    // MARK: - Contributions

    private var contributionSection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("History")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    if contributions.count > 10 {
                        Button(showAllContributions ? "Show less" : "Show all") {
                            showAllContributions.toggle()
                        }
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.accent)
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
                        contributionRow(c)
                        if c.id != items.last?.id {
                            Divider().foregroundStyle(DS.Colors.grid)
                        }
                    }
                }
            }
        }
    }

    private func contributionRow(_ c: GoalContribution) -> some View {
        HStack(spacing: 10) {
            Image(systemName: c.amount >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(rowIconColor(c))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(c.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                        .font(DS.Typography.body.weight(.medium))
                        .foregroundStyle(c.isReversed ? DS.Colors.subtext : DS.Colors.text)

                    if c.source != .manual {
                        Text(sourceLabel(c.source))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Colors.subtext)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DS.Colors.surface2, in: Capsule())
                    }

                    if c.isReversed {
                        Text("Reversed")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Colors.danger)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DS.Colors.danger.opacity(0.12), in: Capsule())
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
                .foregroundStyle(rowAmountColor(c))
                .strikethrough(c.isReversed)
        }
        .contextMenu {
            if !c.isReversed {
                Button(role: .destructive) {
                    Task { await reverse(c) }
                } label: {
                    Label("Reverse", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    private func rowIconColor(_ c: GoalContribution) -> Color {
        if c.isReversed { return DS.Colors.subtext }
        return c.amount >= 0 ? DS.Colors.positive : DS.Colors.danger
    }

    private func rowAmountColor(_ c: GoalContribution) -> Color {
        if c.isReversed { return DS.Colors.subtext }
        return c.amount >= 0 ? DS.Colors.positive : DS.Colors.danger
    }

    private func sourceLabel(_ source: GoalContribution.ContributionSource) -> String {
        switch source {
        case .manual:         return "Manual"
        case .transaction:    return "Transaction"
        case .transfer:       return "Transfer"
        case .allocationRule: return "Auto rule"
        case .aiAction:       return "AI"
        case .roundUp:        return "Round-up"
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
        let ok = await goalManager.addContribution(
            to: liveGoal,
            amount: cents,
            note: contributionNote.isEmpty ? nil : contributionNote
        )
        resetAddFields()
        await loadData()
        if !ok {
            failureMessage = goalManager.errorMessage ?? "Could not add contribution."
        }
    }

    private func withdraw() async {
        let cents = DS.Format.cents(from: withdrawAmountText)
        guard cents > 0 else { return }
        let ok = await goalManager.withdrawContribution(
            from: liveGoal,
            amount: cents,
            note: withdrawNote.isEmpty ? nil : withdrawNote
        )
        resetWithdrawFields()
        await loadData()
        if !ok {
            failureMessage = goalManager.errorMessage ?? "Could not withdraw."
        }
    }

    private func reverse(_ c: GoalContribution) async {
        _ = await goalManager.reverseContribution(c, in: liveGoal)
        await loadData()
    }

    private func resetAddFields() {
        contributionAmountText = ""
        contributionNote = ""
    }

    private func resetWithdrawFields() {
        withdrawAmountText = ""
        withdrawNote = ""
    }
}
