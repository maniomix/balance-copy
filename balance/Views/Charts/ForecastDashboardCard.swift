import SwiftUI

// MARK: - Safe to Spend Card (Redesigned)

/// Clean, minimal card showing safe-to-spend with a subtle progress ring.
struct SafeToSpendCard: View {

    @StateObject private var engine = ForecastEngine.shared

    var body: some View {
        if let f = engine.forecast {
            NavigationLink(destination: ForecastDetailView()) {
                DS.Card {
                    HStack(spacing: 16) {
                        // Left: ring gauge
                        ZStack {
                            Circle()
                                .stroke(DS.Colors.surface2, lineWidth: 4)
                                .frame(width: 52, height: 52)

                            Circle()
                                .trim(from: 0, to: safeRatio(f))
                                .stroke(f.riskLevel.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 52, height: 52)
                                .rotationEffect(.degrees(-90))

                            Image(systemName: f.riskLevel.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(f.riskLevel.color)
                        }

                        // Middle: amount + label
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Safe to Spend")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DS.Colors.subtext)

                            Text(DS.Format.money(f.safeToSpend.totalAmount))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(f.riskLevel.color)

                            HStack(spacing: 10) {
                                Label(DS.Format.money(f.safeToSpend.perDay) + "/day", systemImage: "calendar")
                                Label("\(f.daysRemainingInMonth)d left", systemImage: "clock")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)
                        }

                        Spacer()

                        // Right: risk badge + confidence + chevron
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(f.riskLevel.label)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(f.riskLevel.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(f.riskLevel.color.opacity(0.1), in: Capsule())

                            if f.budgetIsMissing {
                                HStack(spacing: 2) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 8))
                                    Text("Est.")
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .foregroundStyle(DS.Colors.subtext.opacity(0.6))
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.Colors.subtext.opacity(0.3))
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func safeRatio(_ f: ForecastResult) -> CGFloat {
        guard f.budget > 0 else { return 0 }
        return CGFloat(min(1.0, max(0, Double(f.safeToSpend.totalAmount) / Double(f.budget))))
    }
}

// MARK: - Forecast Dashboard Card (Redesigned)

/// Clean card: mini sparkline with 3 projection pills underneath.
struct ForecastDashboardCard: View {

    @StateObject private var engine = ForecastEngine.shared

    var body: some View {
        if let f = engine.forecast {
            NavigationLink(destination: ForecastDetailView()) {
                DS.Card {
                    VStack(alignment: .leading, spacing: 14) {
                        // Header row
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label("Forecast", systemImage: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DS.Colors.accent)
                                Text("Projected end of month")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DS.Colors.subtext)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.Colors.subtext.opacity(0.4))
                        }

                        // Headline value
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(DS.Format.money(f.projectedMonthEnd))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(f.projectedMonthEnd >= 0 ? DS.Colors.text : DS.Colors.danger)

                            trendBadge(values: f.timeline.map { $0.budgetRemaining })
                        }

                        // Mini sparkline
                        if !f.timeline.isEmpty {
                            miniChart(points: f.timeline)
                                .frame(height: 44)
                        }

                        // Projection row — clean, no heavy pill chrome
                        HStack(spacing: 0) {
                            projStat("End of month", f.projectedMonthEnd, emphasized: true)
                            divider
                            projStat("In 30 days", f.projected30Day)
                            divider
                            projStat("In 60 days", f.projected60Day)
                        }

                        // Next bill footer (moved out of header)
                        if let bill = f.upcomingBills.first {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar.badge.exclamationmark")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Next: \(bill.name) · \(DS.Format.money(bill.amount))")
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(DS.Colors.warning)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.Colors.surface2)
            .frame(width: 1, height: 28)
    }

    private func projStat(_ label: String, _ amount: Int, emphasized: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Colors.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(DS.Format.money(amount))
                .font(.system(size: emphasized ? 14 : 13,
                              weight: emphasized ? .bold : .semibold,
                              design: .rounded))
                .foregroundStyle(amount >= 0
                                 ? (emphasized ? DS.Colors.text : DS.Colors.text.opacity(0.85))
                                 : DS.Colors.danger)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func trendBadge(values: [Int]) -> some View {
        let first = values.first ?? 0
        let last = values.last ?? 0
        let delta = last - first
        let up = delta >= 0
        let color: Color = up ? DS.Colors.positive : DS.Colors.danger
        return HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
            Text(DS.Format.money(abs(delta)))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func miniChart(points: [ForecastPoint]) -> some View {
        GeometryReader { geo in
            let values = points.map { $0.budgetRemaining }
            let minVal = values.min() ?? 0
            let maxVal = values.max() ?? 1
            let range = max(1, maxVal - minVal)

            ZStack {
                // Gradient fill
                Path { path in
                    for (i, point) in points.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(max(1, points.count - 1))
                        let y = geo.size.height * (1.0 - CGFloat(point.budgetRemaining - minVal) / CGFloat(range))
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [lineColor(values).opacity(0.2), lineColor(values).opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )

                // Line
                Path { path in
                    for (i, point) in points.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(max(1, points.count - 1))
                        let y = geo.size.height * (1.0 - CGFloat(point.budgetRemaining - minVal) / CGFloat(range))
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(lineColor(values), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func lineColor(_ values: [Int]) -> Color {
        (values.last ?? 0) >= 0 ? DS.Colors.accent : DS.Colors.danger
    }
}
