import SwiftUI

// ============================================================
// MARK: - Monthly Briefing View
// ============================================================
// Scrollable presentation of the MonthlyBriefing model.
// Each section rendered as a DS.Card with contextual styling.
// ============================================================

struct BriefingView: View {
    let briefing: MonthlyBriefing

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Header
                headerCard

                // Overview
                overviewCard

                // Spending breakdown
                if let spending = briefing.spending {
                    spendingCard(spending)
                }

                // Forecast
                if let forecast = briefing.forecast {
                    forecastCard(forecast)
                }

                // Subscriptions
                if let subs = briefing.subscriptions {
                    subscriptionCard(subs)
                }

                // Review queue
                if let review = briefing.review {
                    reviewCard(review)
                }

                // Goals
                if let goals = briefing.goals {
                    goalCard(goals)
                }

                // Household
                if let household = briefing.household {
                    householdCard(household)
                }

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
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(DS.Colors.accent)

                    Text(briefing.monthDisplayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(DS.Colors.text)

                    Spacer()
                }

                Text("Your personalized financial summary")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Overview

    private var overviewCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(briefing.overview.headline)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)

                Text(briefing.overview.subheadline)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.subtext)

                Divider().foregroundStyle(DS.Colors.grid)

                HStack(spacing: 0) {
                    kpiItem(label: "Budget", value: DS.Format.money(briefing.overview.budgetTotal))
                    kpiItem(label: "Spent", value: DS.Format.money(briefing.overview.totalSpent))
                    kpiItem(label: "Income", value: DS.Format.money(briefing.overview.totalIncome))
                    kpiItem(label: "Remaining", value: DS.Format.money(briefing.overview.remaining))
                }
            }
        }
    }

    // MARK: - Spending

    private func spendingCard(_ spending: SpendingSection) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "chart.pie.fill", title: "Spending", color: 0x4559F5)

                ForEach(Array(spending.topCategories.enumerated()), id: \.offset) { _, cat in
                    HStack {
                        Text(cat.category)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Colors.text)

                        Spacer()

                        Text(DS.Format.money(cat.amount))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Colors.text)

                        Text(DS.Format.percent(cat.percent))
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Colors.subtext)
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                if let warning = spending.concentrationWarning {
                    alertPill(text: warning, color: .orange)
                }
                if let alert = spending.smallExpenseAlert {
                    alertPill(text: alert, color: DS.Colors.subtext)
                }
            }
        }
    }

    // MARK: - Forecast

    private func forecastCard(_ forecast: ForecastSection) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "chart.line.uptrend.xyaxis", title: "Forecast", color: 0x2ED573)

                HStack(spacing: 0) {
                    kpiItem(label: "Safe/Day", value: DS.Format.money(forecast.safeToSpendPerDay))
                    kpiItem(label: "Safe Total", value: DS.Format.money(forecast.safeToSpendTotal))
                    kpiItem(label: "EOM Budget", value: DS.Format.money(forecast.projectedMonthEnd))
                }

                HStack(spacing: 8) {
                    riskBadge(forecast.riskLevel)

                    if forecast.upcomingBillCount > 0 {
                        Text("\(forecast.upcomingBillCount) upcoming bill\(forecast.upcomingBillCount == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Colors.subtext)
                    }

                    if forecast.overdueBillCount > 0 {
                        Text("\(forecast.overdueBillCount) overdue")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                    }
                }

                if let risk = forecast.riskSummary {
                    alertPill(text: risk, color: .red)
                }
            }
        }
    }

    // MARK: - Subscriptions

    private func subscriptionCard(_ subs: SubscriptionSection) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "repeat.circle.fill", title: "Subscriptions", color: 0xFF9F0A)

                Text(subs.headline)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.text)

                HStack(spacing: 0) {
                    kpiItem(label: "Active", value: "\(subs.activeCount)")
                    kpiItem(label: "Monthly", value: DS.Format.money(subs.monthlyTotal))
                    if subs.potentialSavings > 0 {
                        kpiItem(label: "Savings", value: DS.Format.money(subs.potentialSavings))
                    }
                }
            }
        }
    }

    // MARK: - Review

    private func reviewCard(_ review: ReviewSection) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "checkmark.circle.fill", title: "Review Queue", color: 0xFF3B30)

                Text(review.headline)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.text)

                HStack(spacing: 0) {
                    kpiItem(label: "Pending", value: "\(review.pendingCount)")
                    kpiItem(label: "High Priority", value: "\(review.highPriorityCount)")
                    kpiItem(label: "Duplicates", value: "\(review.duplicateCount)")
                }
            }
        }
    }

    // MARK: - Goals

    private func goalCard(_ goals: GoalSection) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "target", title: "Goals", color: 0x3498DB)

                Text(goals.headline)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.text)

                if let name = goals.topGoalName, let progress = goals.topGoalProgress {
                    HStack {
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Colors.text)

                        Spacer()

                        Text(DS.Format.percent(progress))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                    }

                    ProgressView(value: progress)
                        .tint(DS.Colors.accent)
                }
            }
        }
    }

    // MARK: - Household

    private func householdCard(_ household: HouseholdSection) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "person.2.fill", title: "Household", color: 0xE91E63)

                Text(household.headline)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.text)

                HStack(spacing: 0) {
                    kpiItem(label: "Shared", value: DS.Format.money(household.sharedSpending))
                    if household.sharedBudget > 0 {
                        kpiItem(label: "Budget", value: DS.Format.money(household.sharedBudget))
                    }
                    kpiItem(label: "Balance", value: DS.Format.money(abs(household.netBalance)))
                }

                if household.unsettledCount > 0 {
                    alertPill(
                        text: "\(household.unsettledCount) expense\(household.unsettledCount == 1 ? "" : "s") to settle with \(household.partnerName)",
                        color: .orange
                    )
                }
            }
        }
    }

    // MARK: - Reusable Components

    private func sectionHeader(icon: String, title: String, color: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color(hexValue: UInt32(color)))

            Text(title)
                .font(DS.Typography.section)
                .foregroundStyle(DS.Colors.text)
        }
    }

    private func kpiItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(DS.Colors.subtext)
        }
        .frame(maxWidth: .infinity)
    }

    private func riskBadge(_ level: String) -> some View {
        let color: Color = switch level {
        case "safe": .green
        case "caution": .orange
        default: .red
        }

        return Text(level.capitalized)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func alertPill(text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(DS.Colors.subtext)
        }
        .padding(.top, 2)
    }
}
