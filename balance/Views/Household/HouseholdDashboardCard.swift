import SwiftUI

// ============================================================
// MARK: - Household Dashboard Card (v3 — Modern)
// ============================================================

struct HouseholdDashboardCard: View {
    @Binding var store: Store
    @StateObject private var manager = HouseholdManager.shared
    @EnvironmentObject private var authManager: AuthManager
    @State private var showHousehold = false

    private var monthKey: String { Store.monthKey(store.selectedMonth) }
    private var currentUserId: String { authManager.currentUser?.uid ?? "" }

    var body: some View {
        if let h = manager.household {
            let snapshot = manager.dashboardSnapshot(
                monthKey: monthKey,
                currentUserId: currentUserId
            )

            Button {
                Haptics.light()
                showHousehold = true
            } label: {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Top: icon + name + avatars ──
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                            .frame(width: 34, height: 34)
                            .background(DS.Colors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DS.Colors.text)

                            // Status line
                            if snapshot.hasPartner {
                                Text("\(snapshot.memberCount) members")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(DS.Colors.subtext)
                            } else {
                                Text("Invite a partner to start sharing")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(DS.Colors.accent)
                            }
                        }

                        Spacer()

                        // Avatars
                        HStack(spacing: -5) {
                            ForEach(h.members.prefix(3)) { member in
                                Text(String(member.displayName.prefix(1)).uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        member.role == .owner ? DS.Colors.accent : DS.Colors.positive,
                                        in: Circle()
                                    )
                                    .overlay(Circle().stroke(DS.Colors.surface, lineWidth: 1.5))
                            }
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Colors.subtext.opacity(0.4))
                    }
                    .padding(14)

                    // ── Bottom: only show if there's content ──
                    if hasBottomContent(h, snapshot: snapshot) {
                        Rectangle()
                            .fill(DS.Colors.grid.opacity(0.5))
                            .frame(height: 0.5)
                            .padding(.horizontal, 14)

                        VStack(alignment: .leading, spacing: 8) {
                            // Balance
                            if let partner = h.partner, let owner = h.owner {
                                let otherUser = currentUserId == owner.userId ? partner : owner
                                let balance = manager.netBalance(fromUser: currentUserId, toUser: otherUser.userId)

                                HStack {
                                    if balance > 0 {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text("You owe \(otherUser.displayName)")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(DS.Colors.subtext)
                                            Text(DS.Format.money(balance))
                                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                                .foregroundStyle(DS.Colors.danger)
                                        }
                                    } else if balance < 0 {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text("\(otherUser.displayName) owes you")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(DS.Colors.subtext)
                                            Text(DS.Format.money(abs(balance)))
                                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                                .foregroundStyle(DS.Colors.positive)
                                        }
                                    } else {
                                        HStack(spacing: 5) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 13))
                                                .foregroundStyle(DS.Colors.positive)
                                            Text("All settled")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(DS.Colors.positive)
                                        }
                                    }

                                    Spacer()

                                    if snapshot.sharedSpending > 0 {
                                        VStack(alignment: .trailing, spacing: 1) {
                                            Text(DS.Format.money(snapshot.sharedSpending))
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                                .foregroundStyle(DS.Colors.text)
                                            Text("shared")
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundStyle(DS.Colors.subtext)
                                        }
                                    }
                                }
                            }

                            // Budget
                            if let util = snapshot.budgetUtilization, snapshot.sharedBudget > 0 {
                                HStack(spacing: 8) {
                                    Text("Budget")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(DS.Colors.subtext)
                                        .frame(width: 40, alignment: .leading)

                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(DS.Colors.surface2)
                                            Capsule()
                                                .fill(snapshot.isOverBudget ? DS.Colors.danger : DS.Colors.accent)
                                                .frame(width: geo.size.width * min(1.0, CGFloat(util)))
                                        }
                                    }
                                    .frame(height: 4)

                                    Text("\(DS.Format.money(snapshot.sharedSpending))/\(DS.Format.money(snapshot.sharedBudget))")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundStyle(snapshot.isOverBudget ? DS.Colors.danger : DS.Colors.subtext)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                            }

                            // Goal
                            if let goal = snapshot.topGoal {
                                HStack(spacing: 8) {
                                    Image(systemName: goal.icon)
                                        .font(.system(size: 9))
                                        .foregroundStyle(DS.Colors.accent)
                                        .frame(width: 18, height: 18)
                                        .background(DS.Colors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                                    Text(goal.name)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(DS.Colors.text)
                                        .lineLimit(1)

                                    Spacer()

                                    Text("\(goal.progressPercent)%")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundStyle(goal.progress >= 0.75 ? DS.Colors.positive : DS.Colors.accent)

                                    ZStack(alignment: .leading) {
                                        Capsule().fill(DS.Colors.surface2).frame(width: 30, height: 3)
                                        Capsule()
                                            .fill(goal.progress >= 0.75 ? DS.Colors.positive : DS.Colors.accent)
                                            .frame(width: 30 * min(1.0, CGFloat(goal.progress)), height: 3)
                                    }

                                    if snapshot.activeSharedGoalCount > 1 {
                                        Text("+\(snapshot.activeSharedGoalCount - 1)")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(DS.Colors.subtext)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(DS.Colors.surface2, in: Capsule())
                                    }
                                }
                            }

                            // Alerts
                            let alerts = buildAlerts(snapshot)
                            if !alerts.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(alerts.prefix(2), id: \.text) { alert in
                                        HStack(spacing: 3) {
                                            Image(systemName: alert.icon)
                                                .font(.system(size: 8))
                                            Text(alert.text)
                                                .font(.system(size: 9, weight: .semibold))
                                                .lineLimit(1)
                                        }
                                        .foregroundStyle(alert.color)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(alert.color.opacity(0.08), in: Capsule())
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
                .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showHousehold) {
                NavigationStack {
                    HouseholdOverviewView(store: $store)
                }
            }
        }
    }

    // MARK: - Bottom Content Check

    private func hasBottomContent(_ h: Household, snapshot: HouseholdSnapshot) -> Bool {
        let hasPartner = h.partner != nil && h.owner != nil
        let hasBudget = snapshot.budgetUtilization != nil && snapshot.sharedBudget > 0
        let hasGoal = snapshot.topGoal != nil
        let hasAlerts = !buildAlerts(snapshot).isEmpty
        return hasPartner || hasBudget || hasGoal || hasAlerts
    }

    // MARK: - Alerts

    private struct AlertItem: Hashable {
        let icon: String
        let text: String
        let color: Color
    }

    private func buildAlerts(_ snapshot: HouseholdSnapshot) -> [AlertItem] {
        var alerts: [AlertItem] = []

        if snapshot.isOverBudget {
            alerts.append(AlertItem(icon: "exclamationmark.triangle.fill", text: "Over budget", color: DS.Colors.danger))
        }
        if snapshot.youOwe > 0 {
            alerts.append(AlertItem(icon: "arrow.uturn.right.circle.fill", text: "You owe \(DS.Format.money(snapshot.youOwe))", color: DS.Colors.warning))
        } else if snapshot.owedToYou > 0 {
            alerts.append(AlertItem(icon: "arrow.uturn.left.circle.fill", text: "\(DS.Format.money(snapshot.owedToYou)) owed to you", color: DS.Colors.positive))
        }
        if snapshot.unsettledCount > 3 {
            alerts.append(AlertItem(icon: "clock.fill", text: "\(snapshot.unsettledCount) to settle", color: DS.Colors.warning))
        }

        return alerts
    }
}
