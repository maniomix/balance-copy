import SwiftUI

// ============================================================
// MARK: - Subscriptions Dashboard Card (Phase 7 — single accent)
// ============================================================
//
// Reads from `SubscriptionEngine.shared` (post-Phase-2 snapshot).
// Whole card taps into `SubscriptionsOverviewView` per the
// "Insight Banner No Buttons" rule — no inline action pills.
//
// Color discipline (per "One Accent Per Card"): subscription
// identity = `DS.Colors.accent` (blue). Stats and the renewal
// row use text/subtext only. The single semantic exception is
// overdue/urgent days-until — those keep `danger`/`warning`
// because they're a true risk signal, not chrome.
//
// Replaces the Phase-pre-rebuild rainbow of warning/danger/
// purple alert pills with a subtle "N alerts" summary line.
//
// ============================================================

struct SubscriptionsDashboardCard: View {
    @Binding var store: Store
    @StateObject private var engine = SubscriptionEngine.shared

    var body: some View {
        if !engine.subscriptions.isEmpty,
           engine.activeCount > 0 || engine.monthlyTotal > 0 || engine.yearlyTotal > 0 {
            NavigationLink(destination: SubscriptionsOverviewView(store: $store)) {
                cardBody
            }
            .buttonStyle(.plain)
            // Phase 10 — speak the card as one summary so VoiceOver users
            // don't have to walk through every nested stat to know what
            // they're tapping.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(a11yLabel)
            .accessibilityHint("Opens subscriptions overview")
        }
    }

    /// Single-string summary for VoiceOver: count, monthly cost, alert state.
    private var a11yLabel: String {
        var parts: [String] = ["Subscriptions"]
        parts.append("\(engine.activeCount) active")
        parts.append("\(DS.Format.currencySymbol())\(DS.Format.currency(engine.monthlyTotal)) per month")
        if let summary = alertsSummary { parts.append(summary) }
        return parts.joined(separator: ", ")
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            statsRow
            divider
            if let next = engine.upcomingRenewals.first {
                renewalRow(next)
            }
            if let summary = alertsSummary {
                divider
                summaryRow(summary)
            }
            // Trailing breathing room when nothing follows the stats.
            if engine.upcomingRenewals.first == nil && alertsSummary == nil {
                Spacer().frame(height: 14)
            }
        }
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
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
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: DS.Format.money(engine.monthlyTotal), label: "per month")
            verticalSeparator
            statCell(value: DS.Format.money(engine.yearlyTotal), label: "per year")
            verticalSeparator
            statCell(value: "\(engine.activeCount)", label: "active")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

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

    private var verticalSeparator: some View {
        Rectangle()
            .fill(DS.Colors.grid.opacity(0.5))
            .frame(width: 1, height: 28)
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.Colors.grid.opacity(0.6))
            .frame(height: 0.5)
            .padding(.horizontal, 14)
    }

    // MARK: - Next renewal

    /// Phase 7 — category-tint icon dropped in favor of a neutral subtext
    /// indicator so the card has only one identity color (blue header).
    /// Days-until keeps warning/danger when overdue/urgent — that's a
    /// true risk signal, not chrome.
    private func renewalRow(_ next: DetectedSubscription) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Colors.subtext)
                .frame(width: 24, height: 24)
                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

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
                    Text(isOverdue ? "\(abs(days))d overdue"
                         : days == 0 ? "today"
                         : days == 1 ? "tomorrow"
                         : "in \(days)d")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isOverdue ? DS.Colors.danger
                                         : isUrgent ? DS.Colors.warning
                                         : DS.Colors.subtext)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Alerts summary

    /// Single subtext line replacing the old rainbow pill row.
    /// Counts active alert classes (missed / price hike / unused) but
    /// surfaces them as one neutral count — the user taps in for detail.
    private var alertsSummary: String? {
        let snap = engine.dashboardSnapshot
        let count = snap.missedChargeCount + snap.priceIncreaseCount + snap.unusedCount
        guard count > 0 else { return nil }
        if count == 1 { return "1 alert needs attention" }
        return "\(count) alerts need attention"
    }

    private func summaryRow(_ summary: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Colors.subtext)
            Text(summary)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Colors.subtext)
            Spacer()
            Text("View")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
