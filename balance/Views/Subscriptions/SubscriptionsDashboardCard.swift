import SwiftUI

// ============================================================
// MARK: - Subscriptions Dashboard Card (v3 — Modern)
// ============================================================

struct SubscriptionsDashboardCard: View {
    @StateObject private var engine = SubscriptionEngine.shared

    var body: some View {
        if !engine.subscriptions.isEmpty {
            NavigationLink(destination: SubscriptionsOverviewView()) {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Top section: icon + title + cost ──
                    HStack(spacing: 12) {
                        // Icon box
                        Image(systemName: "creditcard.and.123")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                            .frame(width: 34, height: 34)
                            .background(DS.Colors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Subscriptions")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DS.Colors.text)

                            HStack(spacing: 4) {
                                Text(DS.Format.money(engine.monthlyTotal))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(DS.Colors.text)
                                Text("/mo")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                        }

                        Spacer()

                        // Active count + chevron
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 4) {
                                Text("\(engine.activeCount)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(DS.Colors.positive)
                                Text("active")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(DS.Colors.subtext)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(DS.Colors.subtext.opacity(0.4))
                            }

                            Text(DS.Format.money(engine.yearlyTotal) + "/yr")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(DS.Colors.subtext.opacity(0.6))
                        }
                    }
                    .padding(14)

                    // ── Divider ──
                    Rectangle()
                        .fill(DS.Colors.grid.opacity(0.5))
                        .frame(height: 0.5)
                        .padding(.horizontal, 14)

                    // ── Bottom section: next renewal + alerts ──
                    VStack(alignment: .leading, spacing: 8) {
                        // Next renewal
                        if let next = engine.upcomingRenewals.first {
                            HStack(spacing: 8) {
                                Image(systemName: next.category.icon)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(next.category.tint)
                                    .frame(width: 20, height: 20)
                                    .background(next.category.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                                Text(next.merchantName.capitalized)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DS.Colors.text)
                                    .lineLimit(1)

                                Text(DS.Format.money(next.expectedAmount))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(DS.Colors.text)

                                Spacer()

                                if let days = next.daysUntilRenewal {
                                    Text(days < 0 ? "\(abs(days))d overdue" : days == 0 ? "today" : days == 1 ? "tomorrow" : "in \(days)d")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(days < 0 ? DS.Colors.danger : days <= 3 ? DS.Colors.warning : DS.Colors.subtext)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(
                                            (days < 0 ? DS.Colors.danger : days <= 3 ? DS.Colors.warning : DS.Colors.subtext).opacity(0.1),
                                            in: Capsule()
                                        )
                                }
                            }
                        }

                        // Alert pills
                        let snapshot = engine.dashboardSnapshot
                        let pills = buildAlertPills(snapshot)
                        if !pills.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(pills.prefix(3), id: \.text) { pill in
                                    HStack(spacing: 3) {
                                        Image(systemName: pill.icon)
                                            .font(.system(size: 8))
                                        Text(pill.text)
                                            .font(.system(size: 9, weight: .semibold))
                                    }
                                    .foregroundStyle(pill.color)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(pill.color.opacity(0.08), in: Capsule())
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                
            }
            .buttonStyle(.plain)
        }
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
