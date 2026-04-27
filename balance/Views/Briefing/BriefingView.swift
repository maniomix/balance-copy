import SwiftUI

// ============================================================
// MARK: - Monthly Briefing View
// ============================================================
// Iterates briefing.sections and renders each via the matching
// section card. Adding a new section kind = add a switch arm.
//
// Design rules:
//   • One accent (DS.Colors.accent) per card; identity carried
//     by SF Symbol + neutral text — no hex colors.
//   • No inline action pills; whole-card tap opens chat seeded
//     with that section's context (handled by parent).
//   • Synthesis text first; only briefing-unique numbers shown,
//     not redashed dashboard KPIs.
//   • .low confidence shows a subtle "Limited data" pill.
// ============================================================

struct BriefingView: View {
    let briefing: MonthlyBriefing
    var onSectionTap: ((BriefingSection) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard

                ForEach(briefing.sections) { section in
                    sectionCard(section)
                }

                generatedFooter

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .navigationTitle("Monthly Briefing")
    }

    // MARK: - Header

    private var headerCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(DS.Colors.accent)
                    Text(briefing.monthDisplayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                }
                Text("Your personalized financial summary")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
            }
        }
    }

    // MARK: - Section dispatch

    @ViewBuilder
    private func sectionCard(_ section: BriefingSection) -> some View {
        let card: AnyView = {
            switch section.kind {
            case .overview(let p):      return AnyView(overviewCard(p, confidence: section.confidence))
            case .spending(let p):      return AnyView(spendingCard(p))
            case .forecast(let p):      return AnyView(forecastCard(p))
            case .subscriptions(let p): return AnyView(subscriptionsCard(p))
            case .review(let p):        return AnyView(reviewCard(p))
            case .goals(let p):         return AnyView(goalsCard(p))
            case .household(let p):     return AnyView(householdCard(p))
            }
        }()

        Button { onSectionTap?(section) } label: { card }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(for: section))
            .accessibilityHint("Double tap to ask Centmond AI about this.")
    }

    private func accessibilityLabel(for section: BriefingSection) -> String {
        let prefix: String
        switch section.kind {
        case .overview(let p):      prefix = "Overview. \(p.headline). \(p.subheadline)"
        case .spending(let p):      prefix = "Spending. \(p.concentrationWarning ?? "Top categories shown.")"
        case .forecast(let p):      prefix = "Forecast. \(p.riskSummary ?? "Risk \(riskWord(p.riskLevel)).")"
        case .subscriptions(let p): prefix = "Subscriptions. \(p.headline)"
        case .review(let p):        prefix = "Review queue. \(p.headline)"
        case .goals(let p):         prefix = "Goals. \(p.headline)"
        case .household(let p):     prefix = "Household. \(p.headline)"
        }
        return section.confidence == .low ? "\(prefix). Limited data." : prefix
    }

    private func riskWord(_ level: ForecastPayload.RiskLevel) -> String {
        switch level {
        case .safe:     return "safe"
        case .caution:  return "caution"
        case .highRisk: return "high"
        }
    }

    // MARK: - Overview

    private func overviewCard(_ p: OverviewPayload, confidence: BriefingSection.Confidence) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(p.headline)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)

                Text(p.subheadline)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.subtext)

                if confidence == .low {
                    confidencePill
                }
            }
        }
    }

    // MARK: - Spending

    private func spendingCard(_ p: SpendingPayload) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "chart.pie.fill", title: "Spending")

                ForEach(Array(p.topCategories.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.category)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Colors.text)
                        Spacer()
                        Text(DS.Format.money(row.amount))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Colors.text)
                        Text(DS.Format.percent(row.percent))
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Colors.subtext)
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                if let warning = p.concentrationWarning {
                    alertPill(text: warning)
                }
                if let alert = p.smallExpenseAlert {
                    alertPill(text: alert)
                }
            }
        }
    }

    // MARK: - Forecast

    private func forecastCard(_ p: ForecastPayload) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "chart.line.uptrend.xyaxis", title: "Forecast")

                Text("Safe to spend \(DS.Format.money(p.safeToSpendPerDay))/day · \(DS.Format.money(p.safeToSpendTotal)) total")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.text)

                HStack(spacing: 8) {
                    riskBadge(p.riskLevel)
                    if p.upcomingBillCount > 0 {
                        Text("\(p.upcomingBillCount) upcoming bill\(p.upcomingBillCount == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    if p.overdueBillCount > 0 {
                        Text("\(p.overdueBillCount) overdue")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DS.Colors.danger)
                    }
                }

                if let risk = p.riskSummary {
                    alertPill(text: risk, emphasized: true)
                }
            }
        }
    }

    // MARK: - Subscriptions

    private func subscriptionsCard(_ p: SubscriptionPayload) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "repeat.circle.fill", title: "Subscriptions")

                Text(p.headline)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.text)

                if p.unusedCount > 0 || p.priceIncreaseCount > 0 {
                    Text("\(p.activeCount) active · \(DS.Format.money(p.monthlyTotal))/mo")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
    }

    // MARK: - Review

    private func reviewCard(_ p: ReviewPayload) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "checkmark.circle.fill", title: "Review Queue")

                Text(p.headline)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.text)
            }
        }
    }

    // MARK: - Goals

    private func goalsCard(_ p: GoalPayload) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "target", title: "Goals")

                Text(p.headline)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.text)

                if let name = p.topGoalName, let progress = p.topGoalProgress {
                    HStack {
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Colors.text)
                        Spacer()
                        Text(DS.Format.percent(progress))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                    }
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(DS.Colors.accent)
                }
            }
        }
    }

    // MARK: - Household

    private func householdCard(_ p: HouseholdPayload) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "person.2.fill", title: "Household")

                Text(p.headline)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.text)

                if p.unsettledCount > 0 {
                    alertPill(
                        text: "\(p.unsettledCount) expense\(p.unsettledCount == 1 ? "" : "s") to settle with \(p.partnerName)"
                    )
                }
            }
        }
    }

    // MARK: - Footer

    private var generatedFooter: some View {
        Text("Generated \(briefing.generatedAt.formatted(date: .abbreviated, time: .shortened))")
            .font(.system(size: 11))
            .foregroundStyle(DS.Colors.subtext)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }

    // MARK: - Reusable

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(DS.Colors.subtext)
            Text(title)
                .font(DS.Typography.section)
                .foregroundStyle(DS.Colors.text)
            Spacer()
        }
    }

    private func riskBadge(_ level: ForecastPayload.RiskLevel) -> some View {
        let (text, color): (String, Color) = {
            switch level {
            case .safe:     return ("Safe", DS.Colors.positive)
            case .caution:  return ("Caution", DS.Colors.warning)
            case .highRisk: return ("High Risk", DS.Colors.danger)
            }
        }()

        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func alertPill(text: String, emphasized: Bool = false) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(emphasized ? DS.Colors.danger : DS.Colors.subtext)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(emphasized ? DS.Colors.text : DS.Colors.subtext)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var confidencePill: some View {
        Text("Limited data")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DS.Colors.subtext)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DS.Colors.subtext.opacity(0.12), in: Capsule())
    }
}
