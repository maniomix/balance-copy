import SwiftUI

// ============================================================
// MARK: - Health Score Dashboard Card
// ============================================================
// Animated ring showing financial health score with label.
// ============================================================

struct HealthScoreCard: View {
    let score: HealthScoreEngine.HealthScore
    @State private var animatedProgress: Double = 0

    var body: some View {
        DS.Card {
            HStack(spacing: 16) {
                // Animated ring
                ZStack {
                    Circle()
                        .stroke(DS.Colors.grid, lineWidth: 6)
                        .frame(width: 64, height: 64)

                    Circle()
                        .trim(from: 0, to: animatedProgress)
                        .stroke(
                            Color(hexValue: UInt32(score.color)),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))

                    Text("\(score.total)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Financial Health")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext)

                    Text(score.label)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hexValue: UInt32(score.color)))

                    // Component breakdown (compact)
                    HStack(spacing: 8) {
                        miniStat(icon: "dollarsign.circle", value: score.budgetScore)
                        miniStat(icon: "chart.line.uptrend.xyaxis", value: score.forecastScore)
                        miniStat(icon: "target", value: score.goalScore)
                        miniStat(icon: "repeat.circle", value: score.subscriptionScore)
                    }
                }

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedProgress = Double(score.total) / 100.0
            }
        }
    }

    private func miniStat(icon: String, value: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(DS.Colors.subtext)

            Text("\(value)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
        }
    }
}
