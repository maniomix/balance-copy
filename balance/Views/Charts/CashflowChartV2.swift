import SwiftUI
import Charts

// MARK: - Cashflow Chart V2

struct CashflowChartV2: View {
    let store: Store
    let range: ChartRange

    @State private var showCumulative: Bool = false
    @State private var showNetLine: Bool = true
    @State private var selectedBucket: ChartBucket?

    private var snapshot: ChartsAnalytics.Snapshot {
        ChartsAnalytics.shared.snapshot(store: store, range: range, now: store.selectedMonth)
    }

    private var buckets: [ChartBucket] { snapshot.buckets }

    private var cumulative: [(id: Int, value: Double)] {
        var running = 0
        return buckets.map { b in
            running += b.net
            return (b.id, Double(running) / 100.0)
        }
    }

    private var totalIncome: Int { buckets.reduce(0) { $0 + $1.income } }
    private var totalExpense: Int { buckets.reduce(0) { $0 + $1.spent } }
    private var totalNet: Int { totalIncome - totalExpense }

    var body: some View {
        if buckets.isEmpty || buckets.allSatisfy({ $0.income == 0 && $0.spent == 0 }) {
            ChartEmptyState()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                summaryRow
                toggleBar
                chart
                    .frame(height: 220)
                legendRow
                if let sel = selectedBucket {
                    selectionCard(sel)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    // MARK: Summary

    private var summaryRow: some View {
        HStack(spacing: 10) {
            summaryPill(label: "Income", amount: totalIncome, tint: DS.Colors.positive, icon: "arrow.down.circle.fill")
            summaryPill(label: "Expense", amount: totalExpense, tint: DS.Colors.danger, icon: "arrow.up.circle.fill")
            summaryPill(label: "Net", amount: totalNet, tint: totalNet >= 0 ? DS.Colors.positive : DS.Colors.danger, icon: totalNet >= 0 ? "plus.circle.fill" : "minus.circle.fill")
        }
    }

    private func summaryPill(label: String, amount: Int, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)
                    .textCase(.uppercase)
                    .kerning(0.3)
            }
            Text(amount.currencyFormatted(showDecimal: false))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Toggles

    private var toggleBar: some View {
        HStack(spacing: 8) {
            CashflowTogglePill(label: "Net line", icon: "chart.line.uptrend.xyaxis", active: showNetLine) {
                withAnimation(.easeInOut(duration: 0.2)) { showNetLine.toggle() }
                Haptics.selection()
            }
            CashflowTogglePill(label: "Cumulative", icon: "arrow.up.right.circle", active: showCumulative) {
                withAnimation(.easeInOut(duration: 0.2)) { showCumulative.toggle() }
                Haptics.selection()
            }
            Spacer()
        }
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            ForEach(buckets) { b in
                BarMark(
                    x: .value("Bucket", b.id),
                    y: .value("Income", Double(b.income) / 100.0),
                    width: .ratio(0.4)
                )
                .foregroundStyle(DS.Colors.positive.opacity(0.85))
                .cornerRadius(3)
                .position(by: .value("Type", "Income"))

                BarMark(
                    x: .value("Bucket", b.id),
                    y: .value("Expense", Double(b.spent) / 100.0),
                    width: .ratio(0.4)
                )
                .foregroundStyle(DS.Colors.danger.opacity(0.8))
                .cornerRadius(3)
                .position(by: .value("Type", "Expense"))
            }

            if showNetLine {
                ForEach(buckets) { b in
                    LineMark(
                        x: .value("Bucket", b.id),
                        y: .value("Net", Double(b.net) / 100.0),
                        series: .value("Series", "Net")
                    )
                    .foregroundStyle(DS.Colors.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Bucket", b.id),
                        y: .value("Net", Double(b.net) / 100.0)
                    )
                    .foregroundStyle(DS.Colors.accent)
                    .symbolSize(25)
                }
            }

            if showCumulative {
                ForEach(cumulative, id: \.id) { c in
                    LineMark(
                        x: .value("Bucket", c.id),
                        y: .value("Cumulative", c.value),
                        series: .value("Series", "Cumulative")
                    )
                    .foregroundStyle(DS.Colors.accent.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [5, 3]))
                    .interpolationMethod(.catmullRom)
                }
            }

            if let sel = selectedBucket {
                RuleMark(x: .value("Selected", sel.id))
                    .foregroundStyle(DS.Colors.text.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXAxis {
            AxisMarks(values: axisValues()) { val in
                AxisGridLine().foregroundStyle(DS.Colors.grid.opacity(0.3))
                AxisValueLabel {
                    if let i = val.as(Int.self), i >= 0, i < buckets.count {
                        Text(buckets[i].label)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(DS.Colors.grid.opacity(0.3))
                AxisValueLabel()
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let plotFrame = geo[proxy.plotAreaFrame]
                                let x = value.location.x - plotFrame.origin.x
                                guard let idx: Int = proxy.value(atX: x) else { return }
                                let clamped = max(0, min(buckets.count - 1, idx))
                                let b = buckets[clamped]
                                if b.id != selectedBucket?.id {
                                    Haptics.selection()
                                }
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedBucket = b
                                }
                            }
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedBucket = nil }
                    }
            }
        }
    }

    // MARK: Legend & Selection

    private var legendRow: some View {
        HStack(spacing: 14) {
            legendDot(color: DS.Colors.positive.opacity(0.85), label: "Income")
            legendDot(color: DS.Colors.danger.opacity(0.8), label: "Expense")
            if showNetLine { legendDot(color: DS.Colors.accent, label: "Net") }
            if showCumulative { legendDot(color: DS.Colors.accent.opacity(0.5), label: "Cumulative") }
            Spacer()
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
        }
    }

    private func selectionCard(_ b: ChartBucket) -> some View {
        let savingsRate = b.income > 0 ? Double(b.net) / Double(b.income) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(b.label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)
                    .textCase(.uppercase)
                    .kerning(0.4)
                Spacer()
                if b.income > 0 {
                    Text("save \(Int((savingsRate * 100).rounded()))%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(savingsRate >= 0 ? DS.Colors.positive : DS.Colors.danger)
                }
            }
            HStack(spacing: 12) {
                selectionCell(label: "Income", value: b.income, tint: DS.Colors.positive)
                selectionCell(label: "Expense", value: b.spent, tint: DS.Colors.danger)
                selectionCell(label: "Net", value: b.net, tint: b.net >= 0 ? DS.Colors.positive : DS.Colors.danger, signed: true)
            }
        }
        .padding(10)
        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func selectionCell(label: String, value: Int, tint: Color, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
            HStack(spacing: 2) {
                if signed && value != 0 {
                    Text(value >= 0 ? "+" : "−")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                }
                Text(abs(value).currencyFormatted(showDecimal: false))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Helpers

    private func axisValues() -> [Int] {
        let count = buckets.count
        guard count > 0 else { return [] }
        if count <= 7 { return Array(0..<count) }
        let step = max(1, count / 6)
        return stride(from: 0, to: count, by: step).map { $0 }
    }
}

// MARK: - Toggle Pill

private struct CashflowTogglePill: View {
    let label: String
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(active ? Color(uiColor: .systemBackground) : DS.Colors.subtext)
            .background(
                active ? AnyShapeStyle(Color(uiColor: .label)) : AnyShapeStyle(DS.Colors.surface2),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}
