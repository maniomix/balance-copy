import SwiftUI

// One view drives three surfaces:
// 1. Lock-screen banner (bottom of locked iPhone)
// 2. Notification-center banner
// 3. StandBy mode (iPhone sideways on charger) — iOS reuses this view
//    automatically; the vertical stack scales naturally.

struct LockScreenBudgetView: View {
    let state: BudgetActivityAttributes.ContentState
    let attributes: BudgetActivityAttributes

    var body: some View {
        if state.totalCents == 0 {
            LockScreenEmptyState()
                .padding(16)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                header
                hero
                weekChart
                topCategoryRow
            }
            .padding(16)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(barColor(for: state))
                Text(attributes.monthLabel.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text("\(state.daysLeft)d left")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
    }

    // MARK: - Hero (amount + ring + sub-line)

    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(formatAmount(
                    state.isOverBudget ? (state.spentCents - state.totalCents) : state.remainingCents,
                    symbol: state.currencySymbol
                ))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(barColor(for: state))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(state.isOverBudget ? "OVER BUDGET" : "REMAINING")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.55))
                Text("\(formatAmount(state.spentCents, symbol: state.currencySymbol)) of \(formatAmount(state.totalCents, symbol: state.currencySymbol))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            RingGauge(percent: state.percentSpent, tint: barColor(for: state), size: 64, lineWidth: 6)
        }
    }

    // MARK: - Week visualization

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text("LAST 7 DAYS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(formatAmount(state.weekSpentCents, symbol: state.currencySymbol))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            }
            DailyBars(
                buckets: state.weekDailyBuckets ?? Array(repeating: 0, count: 7),
                tint: barColor(for: state),
                height: 30
            )
        }
    }

    // MARK: - Top category row

    @ViewBuilder
    private var topCategoryRow: some View {
        if state.topCategoryCents > 0 {
            HStack(spacing: 10) {
                CategoryDonut(
                    share: state.topCategoryShareOfMonth ?? 0,
                    icon: state.topCategoryIcon ?? "trophy.fill",
                    tint: barColor(for: state),
                    size: 30,
                    lineWidth: 3
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.topCategoryTitle ?? "—")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Text("Top category this month")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Text(formatAmount(state.topCategoryCents, symbol: state.currencySymbol))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            }
        }
    }
}

struct LockScreenEmptyState: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: "chart.pie")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("No budget set")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Open Centmond and set a monthly budget to track here.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
