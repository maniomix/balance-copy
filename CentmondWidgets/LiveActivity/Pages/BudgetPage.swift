import SwiftUI

/// Budget page — pixel-tuned to the reference screenshot:
/// huge accent-colored amount, REMAINING label below, full-width thin
/// progress bar, bottom row with creditcard + hourglass icon stats.
struct BudgetPage: View {
    let state: BudgetActivityAttributes.ContentState
    let attributes: BudgetActivityAttributes

    var body: some View {
        if state.totalCents == 0 {
            EmptyStatePage(
                icon: "chart.pie",
                title: "No budget set",
                subtitle: "Set a monthly budget in Centmond to see your remaining amount here."
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(formatAmount(
                        state.isOverBudget ? (state.spentCents - state.totalCents) : state.remainingCents,
                        symbol: state.currencySymbol
                    ))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(barColor(for: state))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .allowsTightening(true)
                    Text(state.isOverBudget ? "OVER BUDGET" : "REMAINING")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.55))
                }
                ProgressBar(percent: state.percentSpent, tint: barColor(for: state))
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(barColor(for: state))
                        Text("\(formatAmount(state.spentCents, symbol: state.currencySymbol)) of \(formatAmount(state.totalCents, symbol: state.currencySymbol))")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("\(state.daysLeft)d left")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}
