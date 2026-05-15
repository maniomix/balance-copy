import SwiftUI

/// Today page — matches reference screenshot 2: hero amount left, U-shape
/// PACE gauge right, bottom row with last-transaction + pace context.
/// "Pace" = today's spend vs the daily fair share of the monthly budget.
struct TodayPage: View {
    let state: BudgetActivityAttributes.ContentState

    private var dailyTarget: Int {
        let cal = Calendar.current
        let daysInMonth = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        return state.totalCents > 0 ? state.totalCents / daysInMonth : 0
    }

    private var pace: Double {
        guard dailyTarget > 0 else { return 0 }
        return Double(state.todaySpentCents) / Double(dailyTarget)
    }

    private var paceColor: Color {
        if pace >= 1.5 { return .red }
        if pace >= 1.0 { return .orange }
        return barColor(for: state)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                HeroBlock(
                    amount: formatAmount(state.todaySpentCents, symbol: state.currencySymbol),
                    label: "TODAY",
                    tint: .white,
                    amountSize: 30
                )
                Spacer()
                if dailyTarget > 0 {
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
                if let last = state.lastTransactionTitle {
                    IconStat(
                        icon: state.lastTransactionIcon ?? "tag.fill",
                        text: last,
                        tint: barColor(for: state)
                    )
                } else {
                    IconStat(
                        icon: "clock",
                        text: "No transactions yet today",
                        tint: .white.opacity(0.4)
                    )
                }
                Spacer(minLength: 8)
                if dailyTarget > 0 {
                    Text("of \(formatAmount(dailyTarget, symbol: state.currencySymbol)) pace")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        }
    }
}
