import SwiftUI
import Auth

// ============================================================
// MARK: - Household Overview
// ============================================================

struct HouseholdOverviewView: View {
    @Binding var store: Store
    @StateObject private var manager = HouseholdManager.shared
    @EnvironmentObject private var authManager: AuthManager
    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    @State private var showSettingsSheet = false
    @State private var showSplitExpense = false
    @State private var showSettleUp = false
    @State private var showSetBudget = false
    @State private var showPartnerActivity = false
    @State private var selectedTab: HubTab = .overview
    @State private var memberPendingDelete: HouseholdMember?
    @State private var showGroupSheet = false
    @State private var editingGroup: HouseholdGroup?
    @State private var nudgeShareItems: [Any] = []
    @State private var showNudgeShare = false

    /// 4-tab hub layout ported from macOS Household hub.
    enum HubTab: String, CaseIterable, Identifiable {
        case overview, splits, settlements, members
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview:    return "Overview"
            case .splits:      return "Splits"
            case .settlements: return "Settle"
            case .members:     return "Members"
            }
        }
    }

    private var monthKey: String { Store.monthKey(store.selectedMonth) }
    private var currentUserId: String { authManager.currentUser?.uid ?? "" }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let h = manager.household {
                    householdHeader(h)
                    hubTabBar
                    switch selectedTab {
                    case .overview:
                        balanceSummaryCard(h)
                        pairBalancesCard(h)
                        sharedBudgetCard(h)
                    case .splits:
                        recentSplitsCard(h)
                    case .settlements:
                        pairBalancesCard(h, forceShow: true)
                        settlementHistoryCard(h)
                    case .members:
                        membersCard(h)
                        groupsCard(h)
                        sharedGoalsCard(h)
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .background(DS.Colors.bg.ignoresSafeArea())
        .navigationTitle("Household")
        .trackScreen("household")
        .toolbar {
            if manager.isInHousehold {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if manager.currentMember?.role.canAddExpenses == true {
                            Button { showSplitExpense = true } label: {
                                Label("Split Expense", systemImage: "arrow.triangle.branch")
                            }
                            Button { showSettleUp = true } label: {
                                Label("Settle Up", systemImage: "checkmark.circle")
                            }
                        }
                        if manager.currentMember?.role.canEditBudgets == true {
                            Button { showSetBudget = true } label: {
                                Label("Shared Budget", systemImage: "chart.pie.fill")
                            }
                        }
                        if manager.household?.partner != nil {
                            Button { showPartnerActivity = true } label: {
                                Label("Partner Activity", systemImage: "person.2.wave.2")
                            }
                        }
                        Divider()
                        Button { showSettingsSheet = true } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DS.Colors.accent)
                    }
                    .accessibilityLabel("Household actions")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) { CreateHouseholdSheet() }
        .sheet(isPresented: $showJoinSheet) { JoinHouseholdSheet() }
        .sheet(isPresented: $showSettingsSheet) { HouseholdSettingsSheet() }
        .sheet(isPresented: $showSplitExpense) { SplitExpenseView(store: $store) }
        .sheet(isPresented: $showSettleUp) { SettleUpSheet() }
        .sheet(isPresented: $showSetBudget) { SharedBudgetSheet(monthKey: monthKey) }
        .sheet(isPresented: $showPartnerActivity) { PartnerActivitySheet(store: $store) }
        .sheet(isPresented: $showGroupSheet) {
            HouseholdGroupSheet(editingGroup: editingGroup)
                .onDisappear { editingGroup = nil }
        }
        .sheet(isPresented: $showNudgeShare) {
            HouseholdNudgeShareSheet(items: nudgeShareItems)
        }
    }

    // MARK: - Tab Bar

    /// Segmented picker ported from macOS Household hub. Sits below the header.
    private var hubTabBar: some View {
        Picker("Household section", selection: $selectedTab) {
            ForEach(HubTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Household section")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)

            Image(systemName: "person.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(DS.Colors.accent.opacity(0.6))

            Text("Shared Finance")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.text)

            Text("Manage money together with your partner.\nSplit expenses, share budgets, and settle up.")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(spacing: 12) {
                Button {
                    Haptics.medium()
                    showCreateSheet = true
                } label: {
                    Label("Create Household", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DS.PrimaryButton())

                Button {
                    showJoinSheet = true
                } label: {
                    Text("Join with Code")
                        .font(DS.Typography.body.weight(.semibold))
                        .foregroundStyle(DS.Colors.accent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            Spacer()
        }
    }

    // MARK: - Household Header

    private func householdHeader(_ h: Household) -> some View {
        DS.Card {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(h.name)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Colors.text)
                        Text("\(h.memberCount) member\(h.memberCount == 1 ? "" : "s")")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    Spacer()
                    // Member avatars
                    HStack(spacing: -8) {
                        ForEach(h.members.prefix(3)) { member in
                            memberAvatar(member, size: 32)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Balance Summary

    private func balanceSummaryCard(_ h: Household) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Balance")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                if let partner = h.partner, let owner = h.owner {
                    let otherUser = currentUserId == owner.userId ? partner : owner
                    let balance = manager.netBalance(fromUser: currentUserId, toUser: otherUser.userId)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if balance > 0 {
                                Text("You owe \(otherUser.displayName)")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                                Text(DS.Format.money(balance))
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(DS.Colors.danger)
                            } else if balance < 0 {
                                Text("\(otherUser.displayName) owes you")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                                Text(DS.Format.money(abs(balance)))
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(DS.Colors.positive)
                            } else {
                                Text("All settled up!")
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Colors.positive)
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(DS.Colors.positive)
                            }
                        }
                        Spacer()
                        if balance != 0, h.canEdit(userId: currentUserId) {
                            Button {
                                Haptics.medium()
                                showSettleUp = true
                            } label: {
                                Text("Settle")
                                    .font(DS.Typography.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(DS.Colors.accent, in: Capsule())
                            }
                        }
                    }
                } else {
                    Text("Invite a partner to start tracking")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
    }

    // MARK: - Pair Balances ("Who Owes Who")

    /// Multi-member "who owes who" panel. Rendered only for 3+ member households
    /// since the Balance Summary already covers the 2-member case. Uses the
    /// clamp-safe `openPairBalances()` helper ported from macOS.
    @ViewBuilder
    private func pairBalancesCard(_ h: Household, forceShow: Bool = false) -> some View {
        if forceShow || h.members.count >= 3 {
            let pairs = manager.openPairBalances()
            DS.Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Who Owes Who")
                            .font(DS.Typography.section)
                            .foregroundStyle(DS.Colors.text)
                        Spacer()
                        if pairs.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DS.Colors.positive)
                        }
                    }
                    if pairs.isEmpty {
                        Text("All settled across the household.")
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.subtext)
                    } else {
                        ForEach(pairs) { pair in
                            pairRow(pair)
                            if pair.id != pairs.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pair Row + Nudge

    @ViewBuilder
    private func pairRow(_ pair: HouseholdManager.PairBalance) -> some View {
        let isCreditor = pair.creditor.userId == currentUserId
        HStack(spacing: 10) {
            memberAvatar(pair.debtor, size: 28)
            Text(pair.debtor.displayName)
                .font(DS.Typography.body.weight(.medium))
                .foregroundStyle(DS.Colors.text)
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Colors.subtext)
            memberAvatar(pair.creditor, size: 28)
            Text(pair.creditor.displayName)
                .font(DS.Typography.body.weight(.medium))
                .foregroundStyle(DS.Colors.text)
            Spacer()
            Text(DS.Format.money(pair.amount))
                .font(DS.Typography.number)
                .foregroundStyle(DS.Colors.danger)
            if isCreditor {
                Menu {
                    Button {
                        let msg = buildNudgeMessage(pair: pair)
                        UIPasteboard.general.string = msg
                        Haptics.success()
                    } label: {
                        Label("Copy Reminder", systemImage: "doc.on.doc")
                    }
                    Button {
                        nudgeShareItems = [buildNudgeMessage(pair: pair)]
                        showNudgeShare = true
                    } label: {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.Colors.accent)
                        .padding(.leading, 2)
                }
                .accessibilityLabel("Nudge \(pair.debtor.displayName)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pair.debtor.displayName) owes \(pair.creditor.displayName) \(DS.Format.money(pair.amount))")
    }

    /// Templated reminder. Ported from macOS Household nudge-message template.
    private func buildNudgeMessage(pair: HouseholdManager.PairBalance) -> String {
        let amount = DS.Format.money(pair.amount)
        return "Hey \(pair.debtor.displayName) — friendly reminder about the \(amount) from our shared splits. Settle up whenever works for you 👍"
    }

    // MARK: - Shared Budget

    private func sharedBudgetCard(_ h: Household) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Shared Budget")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    Text(monthKey)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                }

                let budget = manager.sharedBudget(for: monthKey)
                let spent = manager.sharedSpending(monthKey: monthKey)
                let total = budget?.totalAmount ?? 0
                let remaining = max(0, total - spent)
                let ratio: Double = total > 0 ? Double(spent) / Double(total) : 0
                let sColor: Color = ratio > 0.9 ? DS.Colors.danger : (ratio > 0.7 ? DS.Colors.warning : DS.Colors.positive)

                if total > 0 {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Budget")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                            Text(DS.Format.money(total))
                                .font(DS.Typography.number)
                                .foregroundStyle(DS.Colors.text)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spent")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                            Text(DS.Format.money(spent))
                                .font(DS.Typography.number)
                                .foregroundStyle(DS.Colors.text)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Left")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                            Text(DS.Format.money(remaining))
                                .font(DS.Typography.number)
                                .foregroundStyle(sColor)
                        }
                    }

                    ProgressView(value: min(1.0, ratio))
                        .tint(sColor)

                    // Per-member spending breakdown
                    let memberBreakdown = manager.memberSpending(monthKey: monthKey)
                    if !memberBreakdown.isEmpty {
                        Divider()
                        ForEach(h.members) { member in
                            let memberSpent = memberBreakdown[member.userId] ?? 0
                            if memberSpent > 0 {
                                HStack {
                                    memberAvatar(member, size: 22)
                                    Text(member.displayName)
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                    Spacer()
                                    Text(DS.Format.money(memberSpent))
                                        .font(DS.Typography.caption.weight(.semibold))
                                        .foregroundStyle(DS.Colors.text)
                                }
                            }
                        }
                    }
                } else {
                    HStack {
                        Text("No shared budget set")
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.subtext)
                        Spacer()
                        if h.canEdit(userId: currentUserId) {
                            Button {
                                Haptics.light()
                                showSetBudget = true
                            } label: {
                                Text("Set Budget")
                                    .font(DS.Typography.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(DS.Colors.accent, in: Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent Splits

    private func recentSplitsCard(_ h: Household) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent Splits")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    let unsettled = manager.unsettledExpenses.count
                    if unsettled > 0 {
                        Text("\(unsettled) unsettled")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.warning)
                    }
                }

                let recent = manager.splitExpenses
                    .sorted { $0.date > $1.date }
                    .prefix(5)

                if recent.isEmpty {
                    Text("No split expenses yet")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(recent)) { expense in
                        splitRow(expense, household: h)
                        if expense.id != recent.last?.id {
                            Divider()
                        }
                    }
                }

                if h.canEdit(userId: currentUserId) {
                    Button {
                        Haptics.light()
                        showSplitExpense = true
                    } label: {
                        Label("Add Split Expense", systemImage: "plus.circle.fill")
                            .font(DS.Typography.body.weight(.medium))
                            .foregroundStyle(DS.Colors.accent)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func splitRow(_ expense: SplitExpense, household: Household) -> some View {
        let payer = household.members.first(where: { $0.userId == expense.paidBy })
        return HStack(spacing: 10) {
            Image(systemName: expense.splitRule.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Colors.accent)
                .frame(width: 28, height: 28)
                .background(DS.Colors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.note.isEmpty ? expense.category.capitalized : expense.note)
                    .font(DS.Typography.body.weight(.medium))
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("Paid by \(payer?.displayName ?? "Unknown")")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                    Text("·")
                        .foregroundStyle(DS.Colors.subtext)
                    Text(expense.splitRule.displayName)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.accent)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(DS.Format.money(expense.amount))
                    .font(DS.Typography.number)
                    .foregroundStyle(DS.Colors.text)
                if expense.isSettled {
                    Text("Settled")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.Colors.positive)
                }
            }
        }
    }

    // MARK: - Settlement History

    private func settlementHistoryCard(_ h: Household) -> some View {
        let recentSettlements = manager.settlements
            .sorted { $0.date > $1.date }
            .prefix(3)

        return Group {
            if !recentSettlements.isEmpty {
                DS.Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Settlement History")
                                .font(DS.Typography.section)
                                .foregroundStyle(DS.Colors.text)
                            Spacer()
                            Text("\(manager.settlements.count) total")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                        }

                        ForEach(Array(recentSettlements)) { settlement in
                            settlementRow(settlement, household: h)
                            if settlement.id != recentSettlements.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func settlementRow(_ s: Settlement, household: Household) -> some View {
        let from = household.members.first(where: { $0.userId == s.fromUserId })
        let to = household.members.first(where: { $0.userId == s.toUserId })
        let isYou = s.fromUserId == currentUserId

        return HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(DS.Colors.positive)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(isYou
                     ? "You paid \(to?.displayName ?? "partner")"
                     : "\(from?.displayName ?? "Partner") paid you")
                    .font(DS.Typography.body.weight(.medium))
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(s.note)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                    Text("·")
                        .foregroundStyle(DS.Colors.subtext)
                    Text(s.date, style: .date)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                }
            }

            Spacer()

            Text(DS.Format.money(s.amount))
                .font(DS.Typography.number)
                .foregroundStyle(DS.Colors.positive)
        }
    }

    // MARK: - Shared Goals

    private func sharedGoalsCard(_ h: Household) -> some View {
        let sharedGoals = manager.sharedGoals.filter { $0.householdId == h.id }

        return DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Shared Goals")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    if !sharedGoals.isEmpty {
                        Text("\(sharedGoals.count) active")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.accent)
                    }
                }

                if sharedGoals.isEmpty {
                    HStack {
                        Text("No shared goals yet")
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.subtext)
                        Spacer()
                    }
                } else {
                    ForEach(sharedGoals) { goal in
                        sharedGoalRow(goal)
                        if goal.id != sharedGoals.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func sharedGoalRow(_ goal: SharedGoal) -> some View {
        let progress = goal.targetAmount > 0
            ? Double(goal.currentAmount) / Double(goal.targetAmount)
            : 0
        let statusColor: Color = progress >= 1.0 ? DS.Colors.positive : DS.Colors.accent

        return HStack(spacing: 10) {
            Image(systemName: goal.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Colors.accent)
                .frame(width: 28, height: 28)
                .background(DS.Colors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.name)
                    .font(DS.Typography.body.weight(.medium))
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(1)
                Text("\(DS.Format.money(goal.currentAmount)) of \(DS.Format.money(goal.targetAmount))")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(min(progress, 1.0) * 100))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor)
                ProgressView(value: min(1.0, progress))
                    .tint(statusColor)
                    .frame(width: 50)
            }
        }
    }

    // MARK: - Members

    private func membersCard(_ h: Household) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Members")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                ForEach(h.members) { member in
                    memberRow(member, household: h)
                }

                // Invite button (owner & partner only)
                if h.canEdit(userId: currentUserId) {
                    Button {
                        Haptics.light()
                        showSettingsSheet = true
                    } label: {
                        Label("Invite Member", systemImage: "person.badge.plus")
                            .font(DS.Typography.body.weight(.medium))
                            .foregroundStyle(DS.Colors.accent)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Groups

    @ViewBuilder
    private func groupsCard(_ h: Household) -> some View {
        let canEdit = h.canEdit(userId: currentUserId)
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Groups")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    if canEdit {
                        Button {
                            Haptics.light()
                            editingGroup = nil
                            showGroupSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(DS.Colors.accent)
                        }
                        .accessibilityLabel("Add group")
                    }
                }

                if h.groups.isEmpty {
                    Text("No groups yet. Use groups to separate members (Parents, Kids, Roommates).")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                } else {
                    ForEach(h.groups) { group in
                        Button {
                            editingGroup = group
                            showGroupSheet = true
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hexValue: UInt32(group.colorHex, radix: 16) ?? 0x3DB9FC))
                                    .frame(width: 14, height: 14)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(group.name)
                                        .font(DS.Typography.body.weight(.medium))
                                        .foregroundStyle(DS.Colors.text)
                                    Text("\(group.memberIds.count) member\(group.memberIds.count == 1 ? "" : "s")")
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                                Spacer()
                                if canEdit {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!canEdit)
                        .accessibilityLabel("\(group.name) group, \(group.memberIds.count) members")
                        .accessibilityHint(canEdit ? "Double-tap to edit" : "")
                        if group.id != h.groups.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Member Row (archive / delete / restore)

    @ViewBuilder
    private func memberRow(_ member: HouseholdMember, household h: Household) -> some View {
        let isSelf = member.userId == currentUserId
        let canManage = h.canEdit(userId: currentUserId)
            && currentMember()?.role.canManageMembers == true
            && !isSelf
            && member.role != .owner
        let hasHistory = manager.hasLedgerHistory(for: member.userId)

        HStack(spacing: 10) {
            memberAvatar(member, size: 36)
                .opacity(member.isActive ? 1.0 : 0.4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(DS.Typography.body.weight(.medium))
                        .foregroundStyle(member.isActive ? DS.Colors.text : DS.Colors.subtext)
                        .strikethrough(!member.isActive, color: DS.Colors.subtext)
                    if isSelf {
                        Text("You")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Colors.accent, in: Capsule())
                    }
                    if !member.isActive {
                        Text("Archived")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Colors.subtext)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Colors.subtext.opacity(0.15), in: Capsule())
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: member.role.icon)
                        .font(.system(size: 9))
                    Text(member.role.displayName)
                        .font(DS.Typography.caption)
                }
                .foregroundStyle(DS.Colors.subtext)
            }

            Spacer()

            if !member.shareTransactions {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.subtext)
            }

            if canManage {
                Menu {
                    if member.isActive {
                        if hasHistory {
                            Button {
                                Haptics.light()
                                manager.archiveMember(userId: member.userId)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        } else {
                            Button(role: .destructive) {
                                memberPendingDelete = member
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    } else {
                        Button {
                            Haptics.light()
                            manager.restoreMember(userId: member.userId)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        Button(role: .destructive) {
                            memberPendingDelete = member
                        } label: {
                            Label("Remove Permanently", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                }
                .accessibilityLabel("Member actions for \(member.displayName)")
            }
        }
        .confirmationDialog(
            "Remove \(memberPendingDelete?.displayName ?? "member")?",
            isPresented: Binding(
                get: { memberPendingDelete?.id == member.id },
                set: { if !$0 { memberPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: memberPendingDelete
        ) { pending in
            Button("Remove", role: .destructive) {
                manager.removeMember(userId: pending.userId)
                memberPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { memberPendingDelete = nil }
        } message: { _ in
            if hasHistory {
                Text("This will delete their ledger history too. Archive keeps the history intact.")
            } else {
                Text("This member has no splits or settlements. They'll be removed cleanly.")
            }
        }
    }

    private func currentMember() -> HouseholdMember? {
        manager.household?.member(for: currentUserId)
    }

    // MARK: - Helpers

    private func memberAvatar(_ member: HouseholdMember, size: CGFloat) -> some View {
        let initial = String(member.displayName.prefix(1)).uppercased()
        return Text(initial)
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(member.role == .owner
                        ? DS.Colors.accent
                        : (member.role == .partner ? DS.Colors.positive : DS.Colors.subtext))
            )
            .clipShape(Circle())
            .overlay(Circle().stroke(DS.Colors.bg, lineWidth: 2))
    }
}

// ============================================================
// MARK: - Create Household Sheet
// ============================================================

struct CreateHouseholdSheet: View {
    @StateObject private var manager = HouseholdManager.shared
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Our Household"
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Household") {
                    TextField("Household Name", text: $name)
                }
                Section("Your Name") {
                    TextField("Display Name", text: $displayName)
                }
            }
            .navigationTitle("Create Household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let email = authManager.currentUser?.email ?? ""
                        manager.createHousehold(
                            name: name.isEmpty ? "Our Household" : name,
                            ownerName: displayName.isEmpty ? "Me" : displayName,
                            ownerEmail: email
                        )
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// ============================================================
// MARK: - Join Household Sheet
// ============================================================

struct JoinHouseholdSheet: View {
    @StateObject private var manager = HouseholdManager.shared
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var displayName = ""
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite Code") {
                    TextField("6-character code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                }
                Section("Your Name") {
                    TextField("Display Name", text: $displayName)
                }
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(DS.Colors.danger)
                    }
                }
            }
            .navigationTitle("Join Household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        let email = authManager.currentUser?.email ?? ""
                        let ok = manager.joinHousehold(
                            code: code,
                            displayName: displayName.isEmpty ? "Partner" : displayName,
                            email: email
                        )
                        if ok {
                            Haptics.success()
                            dismiss()
                        } else {
                            errorMessage = "Invalid code. Please try again."
                            Haptics.error()
                        }
                    }
                    .disabled(code.count < 6)
                }
            }
        }
    }
}

// ============================================================
// MARK: - Household Settings Sheet (with Account Visibility)
// ============================================================

struct HouseholdSettingsSheet: View {
    @StateObject private var manager = HouseholdManager.shared
    @StateObject private var accountManager = AccountManager.shared
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var shareTransactions = true
    @State private var selectedAccountIds: Set<String> = []
    @State private var shareAllAccounts = true
    @State private var showDeleteConfirm = false
    @State private var householdName = ""

    var body: some View {
        NavigationStack {
            Form {
                if let h = manager.household {
                    Section("Household") {
                        TextField("Name", text: $householdName)
                            .onAppear { householdName = h.name }
                    }

                    Section("Invite Code") {
                        HStack {
                            Text(h.inviteCode)
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(DS.Colors.accent)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = h.inviteCode
                                Haptics.success()
                            } label: {
                                Image(systemName: "doc.on.doc.fill")
                                    .foregroundStyle(DS.Colors.accent)
                            }
                            .accessibilityLabel("Copy invite code")
                        }
                        Text("Share this code with your partner to join.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }

                    Section {
                        Toggle("Share My Transactions", isOn: $shareTransactions)
                            .onChange(of: shareTransactions) { _, val in
                                let ids: [String]? = shareAllAccounts ? nil : Array(selectedAccountIds)
                                manager.updatePrivacy(shareTransactions: val, sharedAccountIds: ids)
                            }
                    } header: {
                        Text("Privacy")
                    } footer: {
                        Text("When off, your personal transactions won't be visible to household members. Split expenses are always shared.")
                    }

                    if shareTransactions {
                        Section {
                            Toggle("Share All Accounts", isOn: $shareAllAccounts)
                                .onChange(of: shareAllAccounts) { _, val in
                                    let ids: [String]? = val ? nil : Array(selectedAccountIds)
                                    manager.updatePrivacy(shareTransactions: shareTransactions, sharedAccountIds: ids)
                                }

                            if !shareAllAccounts {
                                let accounts = accountManager.accounts.filter { !$0.isArchived }
                                if accounts.isEmpty {
                                    Text("No accounts found")
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                } else {
                                    ForEach(accounts) { account in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(account.name)
                                                    .font(DS.Typography.body)
                                                    .foregroundStyle(DS.Colors.text)
                                                Text(account.type.displayName)
                                                    .font(DS.Typography.caption)
                                                    .foregroundStyle(DS.Colors.subtext)
                                            }
                                            Spacer()
                                            if selectedAccountIds.contains(account.id.uuidString) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(DS.Colors.accent)
                                            } else {
                                                Image(systemName: "circle")
                                                    .foregroundStyle(DS.Colors.subtext)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            let key = account.id.uuidString
                                            if selectedAccountIds.contains(key) {
                                                selectedAccountIds.remove(key)
                                            } else {
                                                selectedAccountIds.insert(key)
                                            }
                                            manager.updatePrivacy(
                                                shareTransactions: shareTransactions,
                                                sharedAccountIds: Array(selectedAccountIds)
                                            )
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Account Visibility")
                        } footer: {
                            Text("Choose which accounts are visible to your partner. Private accounts stay completely hidden.")
                        }
                    }

                    // Member roles (owner only)
                    if h.createdBy == authManager.currentUser?.uid {
                        let otherMembers = h.members.filter { $0.userId != authManager.currentUser?.uid }
                        if !otherMembers.isEmpty {
                            Section("Member Roles") {
                                ForEach(otherMembers) { member in
                                    HStack {
                                        Text(member.displayName)
                                            .font(DS.Typography.body)
                                        Spacer()
                                        Picker("", selection: Binding(
                                            get: { member.role },
                                            set: { newRole in
                                                manager.updateMemberRole(userId: member.userId, role: newRole)
                                            }
                                        )) {
                                            Text("Partner").tag(HouseholdRole.partner)
                                            Text("Viewer").tag(HouseholdRole.viewer)
                                        }
                                        .pickerStyle(.menu)
                                    }
                                }
                            }
                        }
                    }

                    if h.createdBy == authManager.currentUser?.uid {
                        Section {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete Household", systemImage: "trash")
                            }
                        }
                    } else {
                        Section {
                            Button(role: .destructive) {
                                manager.removeMember(userId: authManager.currentUser?.uid ?? "")
                                dismiss()
                            } label: {
                                Label("Leave Household", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if !householdName.isEmpty {
                            manager.updateHouseholdName(householdName)
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                let member = manager.currentMember
                shareTransactions = member?.shareTransactions ?? true
                if let ids = member?.sharedAccountIds {
                    shareAllAccounts = false
                    selectedAccountIds = Set(ids)
                } else {
                    shareAllAccounts = true
                    selectedAccountIds = []
                }
            }
            .alert("Delete Household?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    manager.deleteHousehold()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all shared data for all members. This cannot be undone.")
            }
        }
    }
}

// ============================================================
// MARK: - Shared Budget Sheet
// ============================================================

struct SharedBudgetSheet: View {
    let monthKey: String
    @StateObject private var manager = HouseholdManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var splitRule: SplitRule = .equal

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Month")
                            .foregroundStyle(DS.Colors.subtext)
                        Spacer()
                        Text(monthKey)
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DS.Colors.text)
                    }
                }

                Section("Budget Amount") {
                    TextField("0", text: $amountText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                }

                Section("Split Method") {
                    Picker("Split", selection: $splitRule) {
                        Text("50/50").tag(SplitRule.equal)
                        Text("Custom %").tag(SplitRule.percentage(60))
                    }
                    .pickerStyle(.segmented)
                }

                if let existing = manager.sharedBudget(for: monthKey) {
                    Section {
                        HStack {
                            Text("Current budget")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                            Spacer()
                            Text(DS.Format.money(existing.totalAmount))
                                .font(DS.Typography.number)
                                .foregroundStyle(DS.Colors.accent)
                        }
                    }
                }
            }
            .navigationTitle("Shared Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cents = DS.Format.cents(from: amountText)
                        guard cents > 0 else { return }
                        manager.setSharedBudget(monthKey: monthKey, amount: cents, splitRule: splitRule)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(DS.Format.cents(from: amountText) <= 0)
                }
            }
            .onAppear {
                if let existing = manager.sharedBudget(for: monthKey) {
                    let value = Double(existing.totalAmount) / 100.0
                    amountText = value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
                    splitRule = existing.splitRule
                }
            }
        }
    }
}

// ============================================================
// MARK: - Partner Activity Sheet
// ============================================================

struct PartnerActivitySheet: View {
    @Binding var store: Store
    @StateObject private var manager = HouseholdManager.shared
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    private var currentUserId: String { authManager.currentUser?.uid ?? "" }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        if let h = manager.household, let partner = otherMember(h) {
                            partnerHeader(partner)

                            if !partner.shareTransactions {
                                privacyNotice(partner)
                            } else {
                                spendingSummaryCard(partner, h)
                                sharedSplitsCard(h)
                                categoryBreakdownCard()
                            }
                        } else {
                            Text("No partner in household")
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.subtext)
                                .padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Partner Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func otherMember(_ h: Household) -> HouseholdMember? {
        h.members.first(where: { $0.userId != currentUserId })
    }

    private func partnerHeader(_ partner: HouseholdMember) -> some View {
        DS.Card {
            HStack(spacing: 12) {
                Text(String(partner.displayName.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(DS.Colors.positive, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(partner.displayName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                    HStack(spacing: 4) {
                        Image(systemName: partner.role.icon)
                            .font(.system(size: 10))
                        Text(partner.role.displayName)
                            .font(DS.Typography.caption)
                        if partner.shareTransactions {
                            Text("· Sharing")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.positive)
                        }
                    }
                    .foregroundStyle(DS.Colors.subtext)
                }
                Spacer()
            }
        }
    }

    private func privacyNotice(_ partner: HouseholdMember) -> some View {
        DS.Card {
            VStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(DS.Colors.subtext)
                Text("\(partner.displayName) has transaction sharing turned off")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.subtext)
                    .multilineTextAlignment(.center)
                Text("You can still see shared split expenses.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func spendingSummaryCard(_ partner: HouseholdMember, _ h: Household) -> some View {
        let mk = Store.monthKey(store.selectedMonth)
        let memberSpend = manager.memberSpending(monthKey: mk)
        let partnerSpent = memberSpend[partner.userId] ?? 0
        let mySpent = memberSpend[currentUserId] ?? 0
        let totalShared = manager.sharedSpending(monthKey: mk)

        return DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("This Month")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(partner.displayName)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                        Text(DS.Format.money(partnerSpent))
                            .font(DS.Typography.number)
                            .foregroundStyle(DS.Colors.text)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                        Text(DS.Format.money(mySpent))
                            .font(DS.Typography.number)
                            .foregroundStyle(DS.Colors.text)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Shared")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                        Text(DS.Format.money(totalShared))
                            .font(DS.Typography.number)
                            .foregroundStyle(DS.Colors.accent)
                    }
                }
            }
        }
    }

    private func sharedSplitsCard(_ h: Household) -> some View {
        let mk = Store.monthKey(store.selectedMonth)
        let monthSplits = manager.splitExpenses
            .filter { Store.monthKey($0.date) == mk }
            .sorted { $0.date > $1.date }

        return DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Shared Expenses")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                if monthSplits.isEmpty {
                    Text("No shared expenses this month")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                        .padding(.vertical, 4)
                } else {
                    ForEach(monthSplits.prefix(10)) { expense in
                        let payer = h.members.first(where: { $0.userId == expense.paidBy })
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(expense.note.isEmpty ? expense.category.capitalized : expense.note)
                                    .font(DS.Typography.body.weight(.medium))
                                    .foregroundStyle(DS.Colors.text)
                                    .lineLimit(1)
                                Text("Paid by \(payer?.displayName ?? "Unknown") · \(expense.date, style: .date)")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                            Spacer()
                            Text(DS.Format.money(expense.amount))
                                .font(DS.Typography.number)
                                .foregroundStyle(DS.Colors.text)
                        }
                        if expense.id != monthSplits.prefix(10).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func categoryBreakdownCard() -> some View {
        let mk = Store.monthKey(store.selectedMonth)
        let breakdown = manager.sharedCategoryBreakdown(monthKey: mk)
        let sorted = breakdown.sorted { $0.value > $1.value }

        return Group {
            if !sorted.isEmpty {
                DS.Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Categories")
                            .font(DS.Typography.section)
                            .foregroundStyle(DS.Colors.text)

                        ForEach(sorted.prefix(5), id: \.key) { category, amount in
                            HStack {
                                Text(category.capitalized)
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Colors.text)
                                Spacer()
                                Text(DS.Format.money(amount))
                                    .font(DS.Typography.number)
                                    .foregroundStyle(DS.Colors.accent)
                            }
                        }
                    }
                }
            }
        }
    }
}

// ============================================================
// MARK: - Settle Up Sheet
// ============================================================

struct SettleUpSheet: View {
    @StateObject private var manager = HouseholdManager.shared
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var selectedCounterpartyId: String = ""
    @State private var amountText: String = ""

    private var currentUserId: String { authManager.currentUser?.uid ?? "" }

    /// Counterparties (non-self active members). Excludes archived members so
    /// settlements can't target ghost users.
    private func counterparties(_ h: Household) -> [HouseholdMember] {
        let base = h.activeMembers.isEmpty ? h.members : h.activeMembers
        return base.filter { $0.userId != currentUserId }
    }

    private func balance(with counterpartyId: String) -> Int {
        manager.netBalance(fromUser: currentUserId, toUser: counterpartyId)
    }

    var body: some View {
        NavigationStack {
            if let h = manager.household {
                let parties = counterparties(h)
                if parties.isEmpty {
                    emptyBody
                } else {
                    form(household: h, parties: parties)
                }
            } else {
                emptyBody
            }
        }
    }

    private var emptyBody: some View {
        VStack {
            Text("No one to settle up with")
                .foregroundStyle(DS.Colors.subtext)
        }
        .navigationTitle("Settle Up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func form(household h: Household, parties: [HouseholdMember]) -> some View {
        let activeId = selectedCounterpartyId.isEmpty
            ? (parties.first?.userId ?? "")
            : selectedCounterpartyId
        let net = balance(with: activeId)
        let defaultAmount = abs(net)
        let parsedAmount = Int((Double(amountText) ?? 0) * 100)
        let effectiveAmount = amountText.isEmpty ? defaultAmount : parsedAmount

        VStack(spacing: 20) {
            Spacer().frame(height: 12)

            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(DS.Colors.accent)

            if parties.count > 1 {
                Picker("Settle with", selection: Binding(
                    get: { activeId },
                    set: {
                        selectedCounterpartyId = $0
                        amountText = ""
                    }
                )) {
                    ForEach(parties) { m in
                        Text(m.displayName).tag(m.userId)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
            }

            balanceLabel(net: net, counterparty: parties.first(where: { $0.userId == activeId }))

            HStack(spacing: 8) {
                Text("Amount")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                TextField(DS.Format.money(defaultAmount), text: $amountText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 24)

            TextField("Note (optional)", text: $note)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 24)

            if net != 0, effectiveAmount > 0 {
                Button {
                    if net > 0 {
                        manager.settleUp(
                            fromUser: currentUserId,
                            toUser: activeId,
                            amount: effectiveAmount,
                            note: note
                        )
                    } else {
                        manager.settleUp(
                            fromUser: activeId,
                            toUser: currentUserId,
                            amount: effectiveAmount,
                            note: note
                        )
                    }
                    Haptics.success()
                    dismiss()
                } label: {
                    Text(effectiveAmount < defaultAmount ? "Record Partial Payment" : "Mark as Settled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DS.PrimaryButton())
                .padding(.horizontal, 24)
            }

            Spacer()
        }
        .navigationTitle("Settle Up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func balanceLabel(net: Int, counterparty: HouseholdMember?) -> some View {
        let name = counterparty?.displayName ?? "them"
        if net > 0 {
            Text("You owe \(name)")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
            Text(DS.Format.money(net))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.danger)
        } else if net < 0 {
            Text("\(name) owes you")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
            Text(DS.Format.money(abs(net)))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.positive)
        } else {
            Text("All settled with \(name)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.positive)
        }
    }
}

// ============================================================
// MARK: - Nudge Share Sheet (UIActivityViewController wrapper)
// ============================================================

struct HouseholdNudgeShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// ============================================================
// MARK: - Household Group Sheet
// ============================================================

struct HouseholdGroupSheet: View {
    @StateObject private var manager = HouseholdManager.shared
    @Environment(\.dismiss) private var dismiss

    let editingGroup: HouseholdGroup?

    @State private var name: String = ""
    @State private var selectedColor: String = "3DB9FC"
    @State private var selectedMemberIds: Set<UUID> = []

    /// Curated swatches ported from macOS group color palette.
    private let palette: [String] = [
        "3DB9FC", "7C5CFF", "FF7AB6", "FF8A00",
        "28C76F", "FFB020", "EA5455", "8B5CF6"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Parents, Kids, Roommates…", text: $name)
                        .autocorrectionDisabled()
                }
                Section("Color") {
                    HStack(spacing: 10) {
                        ForEach(palette, id: \.self) { hex in
                            let color = Color(hexValue: UInt32(hex, radix: 16) ?? 0x3DB9FC)
                            Button {
                                selectedColor = hex
                                Haptics.light()
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == hex ? Color.white : Color.clear,
                                                    lineWidth: 2)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == hex ? color : Color.clear,
                                                    lineWidth: 4)
                                            .scaleEffect(1.25)
                                            .opacity(0.35)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Color \(hex)")
                        }
                    }
                }
                Section("Members") {
                    ForEach(manager.household?.members ?? []) { m in
                        Button {
                            if selectedMemberIds.contains(m.id) {
                                selectedMemberIds.remove(m.id)
                            } else {
                                selectedMemberIds.insert(m.id)
                            }
                        } label: {
                            HStack {
                                Text(m.displayName)
                                    .foregroundStyle(DS.Colors.text)
                                Spacer()
                                if selectedMemberIds.contains(m.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(DS.Colors.accent)
                                }
                            }
                        }
                    }
                }
                if editingGroup != nil {
                    Section {
                        Button("Delete Group", role: .destructive) {
                            if let g = editingGroup {
                                manager.removeGroup(id: g.id)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editingGroup == nil ? "New Group" : "Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let ids = Array(selectedMemberIds)
                        if let g = editingGroup {
                            manager.updateGroup(
                                id: g.id,
                                name: trimmed,
                                colorHex: selectedColor,
                                memberIds: ids
                            )
                        } else {
                            manager.addGroup(
                                name: trimmed,
                                colorHex: selectedColor,
                                memberIds: ids
                            )
                        }
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let g = editingGroup {
                    name = g.name
                    selectedColor = g.colorHex
                    selectedMemberIds = Set(g.memberIds)
                }
            }
        }
    }
}
