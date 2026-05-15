import SwiftUI

/// Week page — same layout language as Today: hero left, U-gauge right,
/// bottom row of icon stats. Gauge fills "7 days spent vs weekly fair share
/// of the monthly budget" (budget * 7 / daysInMonth).
struct WeekPage: View {
    let state: BudgetActivityAttributes.ContentState

    private var weeklyTarget: Int {
        let cal = Calendar.current
        let daysInMonth = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        return state.totalCents > 0 ? state.totalCents * 7 / daysInMonth : 0
    }

    private var pace: Double {
        guard weeklyTarget > 0 else { return 0 }
        return Double(state.weekSpentCents) / Double(weeklyTarget)
    }

    private var paceColor: Color {
        if pace >= 1.5 { return .red }
        if pace >= 1.0 { return .orange }
        return barColor(for: state)
    }

    var body: some View {
        if state.weekSpentCents == 0 {
            EmptyStatePage(
                icon: "calendar",
                title: "Quiet week",
                subtitle: "No spending logged in the last 7 days."
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    HeroBlock(
                        amount: formatAmount(state.weekSpentCents, symbol: state.currencySymbol),
                        label: "7 DAYS",
                        tint: .white,
                        amountSize: 30
                    )
                    Spacer()
                    if weeklyTarget > 0 {
                        SemicircleGauge(
                            percent: pace,
                            valueText: "\(Int(min(pace, 9.99) * 100))%",
                            label: "PACE",
                            tint: paceColor,
                            width: 60
                        )
                    }
                }
                HStack {
                    IconStat(
                        icon: "chart.bar.fill",
                        text: "\(formatAmount(state.dailyAverageThisWeekCents, symbol: state.currencySymbol))/day avg",
                        tint: barColor(for: state)
                    )
                    Spacer(minLength: 8)
                    if weeklyTarget > 0 {
                        Text("of \(formatAmount(weeklyTarget, symbol: state.currencySymbol)) pace")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}
