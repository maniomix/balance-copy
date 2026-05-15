import SwiftUI

/// Top Category page — donut keeps the visual variety vs other pages.
/// Hero is the spend amount; the donut on the right carries the category
/// icon and its share of monthly spend; bottom row repeats the category
/// name + share % as icon stats.
struct TopCategoryPage: View {
    let state: BudgetActivityAttributes.ContentState

    var body: some View {
        if state.topCategoryCents == 0 {
            EmptyStatePage(
                icon: "trophy",
                title: "No spending yet",
                subtitle: "Log a transaction to see your top category."
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    HeroBlock(
                        amount: formatAmount(state.topCategoryCents, symbol: state.currencySymbol),
                        label: "TOP CATEGORY",
                        tint: .white,
                        amountSize: 30
                    )
                    Spacer()
                    CategoryDonut(
                        share: state.topCategoryShareOfMonth ?? 0,
                        icon: state.topCategoryIcon ?? "trophy.fill",
                        tint: barColor(for: state),
                        size: 44,
                        lineWidth: 4
                    )
                }
                HStack {
                    IconStat(
                        icon: state.topCategoryIcon ?? "trophy.fill",
                        text: state.topCategoryTitle ?? "—",
                        tint: barColor(for: state)
                    )
                    Spacer(minLength: 8)
                    if let share = state.topCategoryShareOfMonth {
                        Text("\(Int(share * 100))% of month")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}
