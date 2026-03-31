import SwiftUI

struct SubscriptionsDashboardCard: View {
    @StateObject private var engine = SubscriptionEngine.shared

    var body: some View {
        if !engine.subscriptions.isEmpty {
            NavigationLink(destination: SubscriptionsOverviewView()) {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Header ──
                    HStack(spacing: 10) {
                        Image(systemName: "creditcard.and.123")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                            .frame(width: 36, height: 36)
                            .background(DS.Colors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text("Subscriptions")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.Colors.text)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Colors.subtext.opacity(0.4))
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                    // ── Stats row ──
                    HStack(spacing: 0) {
                        statCell(
                            value: DS.Format.money(engine.monthlyTotal),
                            label: "per month"
                        )

                        Divider()
                            .frame(height: 28)

                        statCell(
                            value: DS.Format.money(engine.yearlyTotal),
                            label: "per year"
                        )

                        Divider()
                            .frame(height: 28)

                        statCell(
                            value: "\(engine.activeCount)",
                            label: "active"
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)

                    // ── Divider ──
                    Rectangle()
                        .fill(DS.Colors.grid.opacity(0.6))
                        .frame(height: 0.5)
                        .padding(.horizontal, 14)

                    // ── Next renewal ──
                    if let next = engine.upcomingRenewals.first {
                        HStack(spacing: 10) {
                            Image(systemName: next.category.icon)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(next.category.tint)
                                .frame(width: 24, height: 24)
                                .background(next.category.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(next.merchantName.capitalized)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DS.Colors.text)
                                    .lineLimit(1)
                                Text("Next renewal")
                                    .font(.system(size: 10))
                                    .foregroundStyle(DS.Colors.subtext)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(DS.Format.money(next.expectedAmount))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(DS.Colors.text)

                                if let days = next.daysUntilRenewal {
                                    let isOverdue = days < 0
                                    let isUrgent = days >= 0 && days <= 3
                                    Text(isOverdue ? "\(abs(days))d overdue" : days == 0 ? "today" : days == 1 ? "tomorrow" : "in \(days)d")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(isOverdue ? DS.Colors.danger : isUrgent ? DS.Colors.warning : DS.Colors.subtext)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        // ── Alert pills ──
                        let snapshot = engine.dashboardSnapshot
                        let pills = buildAlertPills(snapshot)
                        if !pills.isEmpty {
                            Rectangle()
                                .fill(DS.Colors.grid.opacity(0.6))
                                .frame(height: 0.5)
                                .padding(.horizontal, 14)

                            HStack(spacing: 6) {
                                ForEach(pills.prefix(3), id: \.text) { pill in
                                    HStack(spacing: 4) {
                                        Image(systemName: pill.icon)
                                            .font(.system(size: 9))
                                        Text(pill.text)
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundStyle(pill.color)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(pill.color.opacity(0.08), in: Capsule())
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        } else {
                            Spacer().frame(height: 4)
                        }
                    } else {
                        Spacer().frame(height: 14)
                    }
                }
                .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stat Cell

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(DS.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Colors.subtext)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Alert Pills

    private struct AlertPill: Hashable {
        let icon: String
        let text: String
        let color: Color
    }

    private func buildAlertPills(_ snapshot: SubscriptionSnapshot) -> [AlertPill] {
        var pills: [AlertPill] = []
        if snapshot.missedChargeCount > 0 {
            pills.append(AlertPill(icon: "exclamationmark.triangle.fill", text: "\(snapshot.missedChargeCount) missed", color: DS.Colors.warning))
        }
        if snapshot.priceIncreaseCount > 0 {
            pills.append(AlertPill(icon: "arrow.up.circle.fill", text: "\(snapshot.priceIncreaseCount) price up", color: DS.Colors.danger))
        }
        if snapshot.unusedCount > 0 {
            pills.append(AlertPill(icon: "questionmark.circle.fill", text: "Save \(DS.Format.money(snapshot.potentialSavings))/mo", color: Color(hexValue: 0x9B59B6)))
        }
        let badges = engine.insights.filter {
            $0 != .upcomingRenewal && $0 != .priceIncreased && $0 != .maybeUnused && $0 != .missedCharge
        }
        for insight in badges.prefix(max(0, 3 - pills.count)) {
            pills.append(AlertPill(icon: insight.icon, text: insight.displayName, color: insight.color))
        }
        return pills
    }
}
