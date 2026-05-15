import SwiftUI

// Compact-leading, compact-trailing, and minimal Dynamic Island views.
// All three are tiny — they live to the left/right of the sensor cutout
// or collapsed entirely. Keep visual language consistent across them so
// the user reads the same signal in any size.

struct CompactLeading: View {
    let state: BudgetActivityAttributes.ContentState
    var body: some View {
        ZStack {
            Circle()
                .stroke(barColor(for: state).opacity(0.25), lineWidth: 2.4)
            Circle()
                .trim(from: 0, to: max(0.04, state.percentSpent))
                .stroke(barColor(for: state),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if state.isOverBudget {
                Circle()
                    .fill(.red)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(width: 18, height: 18)
        .padding(.trailing, 1)
    }
}

struct CompactTrailing: View {
    let state: BudgetActivityAttributes.ContentState
    var body: some View {
        Group {
            if state.totalCents == 0 {
                Text("—")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text(formatAmountShort(
                    state.isOverBudget ? (state.spentCents - state.totalCents) : state.remainingCents,
                    symbol: state.currencySymbol
                ))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(barColor(for: state))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.leading, 1)
    }
}

struct MinimalView: View {
    let state: BudgetActivityAttributes.ContentState
    var body: some View {
        ZStack {
            Circle()
                .stroke(barColor(for: state).opacity(0.25), lineWidth: 2.2)
            Circle()
                .trim(from: 0, to: max(0.04, state.percentSpent))
                .stroke(barColor(for: state),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if state.isOverBudget {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(2)
    }
}
