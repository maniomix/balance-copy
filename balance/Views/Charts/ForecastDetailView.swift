import SwiftUI
import Charts

// MARK: - Forecast Detail View

struct ForecastDetailView: View {

    @StateObject private var engine = ForecastEngine.shared

    var body: some View {
        ScrollView {
            if let f = engine.forecast {
                VStack(spacing: 14) {
                    safeToSpendSection(f)
                    projectionSection(f)
                    timelineChart(f)
                    upcomingBillsSection(f)
                    spendingInsightsSection(f)
                    dataSourceSection(f)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(DS.Colors.subtext)
                    Text("Generating forecast...")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
        }
        .background(DS.Colors.bg.ignoresSafeArea())
        .navigationTitle("Forecast")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Safe to Spend

    private func safeToSpendSection(_ f: ForecastResult) -> some View {
        DS.Card {
            VStack(spacing: 14) {
                // Risk indicator
                HStack(spacing: 8) {
                    Image(systemName: f.riskLevel.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(f.riskLevel.color)

                    Text(f.riskLevel.label)
                        .font(DS.Typography.section)
                        .foregroundStyle(f.riskLevel.color)

                    Spacer()
                }

                // Main amount
                Text(DS.Format.money(f.safeToSpend.totalAmount))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(f.riskLevel.color)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("safe to spend this month")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().foregroundStyle(DS.Colors.grid)

                // Breakdown
                HStack(spacing: 0) {
                    safeToSpendStat("Per day", DS.Format.money(f.safeToSpend.perDay), DS.Colors.text)
                    Spacer()
                    safeToSpendStat("Bills reserved", DS.Format.money(f.safeToSpend.reservedForBills), DS.Colors.warning)
                    Spacer()
                    safeToSpendStat("Goals reserved", DS.Format.money(f.safeToSpend.reservedForGoals), DS.Colors.accent)
                }

                // How we calculated this
                Divider().foregroundStyle(DS.Colors.grid)

                VStack(alignment: .leading, spacing: 6) {
                    Text("How it's calculated")
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(DS.Colors.subtext)

                    calcRow("Budget remaining", f.currentRemaining, add: true)
                    calcRow("Upcoming bills", f.safeToSpend.reservedForBills, add: false)
                    calcRow("Goal contributions", f.safeToSpend.reservedForGoals, add: false)
                    Divider().foregroundStyle(DS.Colors.grid)
                    calcRow("Safe to spend", f.safeToSpend.totalAmount, add: true, bold: true)
                }

                // Budget missing warning
                if f.budgetIsMissing {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                        Text("No budget set — using income history as estimate. Set a monthly budget for more accurate guidance.")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(DS.Colors.warning)
                    .padding(10)
                    .background(DS.Colors.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                // Overcommitted warning
                if f.safeToSpend.isOvercommitted {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text("Bills and goal contributions exceed your remaining budget by \(DS.Format.money(f.safeToSpend.overcommitAmount)). Consider adjusting your goals or budget.")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(DS.Colors.danger)
                    .padding(10)
                    .background(DS.Colors.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                // Data confidence
                HStack(spacing: 4) {
                    Image(systemName: f.dataConfidence.icon)
                        .font(.system(size: 10))
                    Text(f.dataConfidence.label)
                        .font(.system(size: 10, weight: .medium))
                    Text("· \(f.monthsOfData) month\(f.monthsOfData == 1 ? "" : "s") of data")
                        .font(.system(size: 10))
                }
                .foregroundStyle(DS.Colors.subtext.opacity(0.7))
            }
        }
    }

    private func safeToSpendStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(DS.Colors.subtext)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private func calcRow(_ label: String, _ amount: Int, add: Bool, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? DS.Typography.body.weight(.semibold) : DS.Typography.body)
                .foregroundStyle(bold ? DS.Colors.text : DS.Colors.subtext)
            Spacer()
            Text("\(add ? "" : "- ")\(DS.Format.money(amount))")
                .font(bold ? DS.Typography.number : DS.Typography.body)
                .foregroundStyle(bold ? DS.Colors.text : (add ? DS.Colors.text : DS.Colors.subtext))
        }
    }

    // MARK: - Projections

    private func projectionSection(_ f: ForecastResult) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Budget Outlook")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                HStack(spacing: 0) {
                    projectionCard("End of month", f.projectedMonthEnd)
                    Spacer()
                    projectionCard("30 days", f.projected30Day)
                    Spacer()
                    projectionCard("60 days", f.projected60Day)
                    Spacer()
                    projectionCard("90 days", f.projected90Day)
                }

                Divider().foregroundStyle(DS.Colors.grid)

                // Averages
                VStack(spacing: 0) {
                    forecastRow("Avg. monthly income", DS.Format.money(f.avgMonthlyIncome), icon: "arrow.down.circle", color: DS.Colors.positive)
                    Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 6)
                    forecastRow("Avg. monthly expense", DS.Format.money(f.avgMonthlyExpense), icon: "arrow.up.circle", color: DS.Colors.danger)
                    Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 6)
                    forecastRow("Monthly recurring", DS.Format.money(f.monthlyRecurringExpense), icon: "repeat", color: DS.Colors.warning)
                    if f.monthlyGoalContributions > 0 {
                        Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 6)
                        forecastRow("Goal contributions", DS.Format.money(f.monthlyGoalContributions), icon: "target", color: DS.Colors.accent)
                    }
                }
            }
        }
    }

    private func projectionCard(_ label: String, _ amount: Int) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(DS.Colors.subtext)

            Text(DS.Format.money(amount))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(amount >= 0 ? DS.Colors.text : DS.Colors.danger)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            amount < 0 ? DS.Colors.danger.opacity(0.06) : DS.Colors.surface2,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(amount < 0 ? DS.Colors.danger.opacity(0.2) : DS.Colors.grid, lineWidth: 0.5)
        )
    }

    private func forecastRow(_ label: String, _ value: String, icon: String, color: Color) -> some View {
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

    // MARK: - Timeline Chart

    private func timelineChart(_ f: ForecastResult) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("30-Day Outlook")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                if !f.timeline.isEmpty {
                    Chart {
                        ForEach(f.timeline) { point in
                            LineMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("Budget Remaining", Double(point.budgetRemaining) / 100.0)
                            )
                            .foregroundStyle(
                                point.budgetRemaining >= 0 ? DS.Colors.accent : DS.Colors.danger
                            )
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("Budget Remaining", Double(point.budgetRemaining) / 100.0)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        (point.budgetRemaining >= 0 ? DS.Colors.accent : DS.Colors.danger).opacity(0.15),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)
                        }

                        // Zero line
                        RuleMark(y: .value("Zero", 0))
                            .foregroundStyle(DS.Colors.grid)
                            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(DS.Format.money(Int(v * 100)))
                                        .font(.system(size: 9))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                            }
                            AxisGridLine()
                                .foregroundStyle(DS.Colors.grid.opacity(0.3))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { value in
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                .font(.system(size: 9))
                                .foregroundStyle(DS.Colors.subtext)
                            AxisGridLine()
                                .foregroundStyle(DS.Colors.grid.opacity(0.3))
                        }
                    }
                    .frame(height: 180)
                }

                // Legend
                HStack(spacing: 12) {
                    legendItem("Budget remaining", DS.Colors.accent)
                    legendItem("Over budget", DS.Colors.danger)
                }
            }
        }
    }

    private func legendItem(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(DS.Colors.subtext)
        }
    }

    // MARK: - Upcoming Bills

    private func upcomingBillsSection(_ f: ForecastResult) -> some View {
        Group {
            if !f.upcomingBills.isEmpty {
                DS.Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Upcoming Bills")
                                .font(DS.Typography.section)
                                .foregroundStyle(DS.Colors.text)
                            Spacer()
                            Text("\(f.upcomingBills.count)")
                                .font(DS.Typography.caption.weight(.semibold))
                                .foregroundStyle(DS.Colors.subtext)
                        }

                        ForEach(Array(f.upcomingBills.prefix(10))) { bill in
                            HStack(spacing: 10) {
                                Image(systemName: bill.category.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(DS.Colors.accent)
                                    .frame(width: 28, height: 28)
                                    .background(DS.Colors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bill.name)
                                        .font(DS.Typography.body.weight(.medium))
                                        .foregroundStyle(DS.Colors.text)
                                        .lineLimit(1)
                                    Text(bill.dueDate, format: .dateTime.month(.abbreviated).day())
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                }

                                Spacer()

                                Text(DS.Format.money(bill.amount))
                                    .font(DS.Typography.number)
                                    .foregroundStyle(DS.Colors.text)
                            }

                            if bill.id != f.upcomingBills.prefix(10).last?.id {
                                Divider().foregroundStyle(DS.Colors.grid)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Spending Insights

    private func spendingInsightsSection(_ f: ForecastResult) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Spending Pace")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                // Current pace comparison
                if f.budget > 0 {
                    let expectedSpend = Int(Double(f.budget) * f.monthProgressRatio)
                    let diff = f.spentThisMonth - expectedSpend
                    let isOverPace = diff > 0

                    HStack(spacing: 10) {
                        Image(systemName: isOverPace ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 14))
                            .foregroundStyle(isOverPace ? DS.Colors.danger : DS.Colors.positive)
                            .frame(width: 32, height: 32)
                            .background(
                                (isOverPace ? DS.Colors.danger : DS.Colors.positive).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isOverPace
                                ? "\(DS.Format.money(abs(diff))) ahead of pace"
                                : "\(DS.Format.money(abs(diff))) under pace"
                            )
                                .font(DS.Typography.body.weight(.medium))
                                .foregroundStyle(DS.Colors.text)

                            Text("Expected: \(DS.Format.money(expectedSpend)) by day \(f.dayOfMonth)")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }
                }

                Divider().foregroundStyle(DS.Colors.grid)

                // Daily average
                forecastRow(
                    "Daily spending rate",
                    DS.Format.money(f.avgDailyExpense),
                    icon: "gauge.with.dots.needle.50percent",
                    color: DS.Colors.subtext
                )

                // Top categories
                if !f.topCategories.isEmpty {
                    Divider().foregroundStyle(DS.Colors.grid)

                    Text("Top Categories")
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(DS.Colors.subtext)

                    ForEach(f.topCategories) { cat in
                        HStack {
                            Text(cat.name)
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.text)
                            Spacer()
                            Text(DS.Format.money(cat.amount))
                                .font(DS.Typography.body.weight(.medium))
                                .foregroundStyle(DS.Colors.text)
                            Text("(\(Int(cat.percentage * 100))%)")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data Source

    private func dataSourceSection(_ f: ForecastResult) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("About this forecast")
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(DS.Colors.subtext)

                Text("Based on \(f.monthsOfData) month\(f.monthsOfData == 1 ? "" : "s") of transaction history, \(f.upcomingBills.count) upcoming recurring payments, and your current budget settings. All projections show budget remaining — not account balances. Assumes your spending pattern continues at the current pace.")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.subtext.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("Last updated")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Colors.subtext)
                    Spacer()
                    Text(f.generatedAt, format: .dateTime.hour().minute())
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
    }
}
