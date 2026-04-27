import SwiftUI
import Charts

// MARK: - Spending Trend V2

struct SpendingTrendChartV2: View {
    let store: Store
    let range: ChartRange

    @State private var selectedBucket: ChartBucket?
    @State private var showMovingAverage: Bool = false
    @State private var showPrevious: Bool = true

    private var snapshot: ChartsAnalytics.Snapshot {
        ChartsAnalytics.shared.snapshot(store: store, range: range, now: store.selectedMonth)
    }

    private var buckets: [ChartBucket] { snapshot.buckets }
    private var previousBuckets: [ChartBucket] { snapshot.previousBuckets }

    private var anomalyThreshold: Double {
        let amounts = buckets.map { Double($0.spent) }
        guard !amounts.isEmpty else { return .infinity }
        let mean = amounts.reduce(0, +) / Double(amounts.count)
        let variance = amounts.map { pow($0 - mean, 2) }.reduce(0, +) / Double(amounts.count)
        return mean + sqrt(variance) * 2
    }

    private var rollingAverage: [(index: Int, value: Double)] {
        let window = 3
        guard buckets.count >= window else { return [] }
        var out: [(Int, Double)] = []
        for i in 0..<buckets.count {
            let lo = max(0, i - window + 1)
            let slice = buckets[lo...i]
            let avg = slice.map { Double($0.spent) }.reduce(0, +) / Double(slice.count)
            out.append((i, avg))
        }
        return out
    }

    var body: some View {
        if buckets.isEmpty || buckets.allSatisfy({ $0.spent == 0 }) {
            ChartEmptyState()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                toggleBar
                chart
                    .frame(height: 220)
                selectionRow
            }
        }
    }

    private var toggleBar: some View {
        HStack(spacing: 8) {
            TogglePill(label: "Previous", icon: "clock.arrow.circlepath", active: showPrevious) {
                withAnimation(.easeInOut(duration: 0.2)) { showPrevious.toggle() }
                Haptics.selection()
            }
            TogglePill(label: "Trend", icon: "waveform.path.ecg", active: showMovingAverage) {
                withAnimation(.easeInOut(duration: 0.2)) { showMovingAverage.toggle() }
                Haptics.selection()
            }
            Spacer()
        }
    }

    private var chart: some View {
        Chart {
            ForEach(buckets) { b in
                AreaMark(
                    x: .value("Bucket", b.id),
                    y: .value("Spent", Double(b.spent) / 100.0)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [DS.Colors.accent.opacity(0.25), DS.Colors.accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Bucket", b.id),
                    y: .value("Spent", Double(b.spent) / 100.0)
                )
                .foregroundStyle(DS.Colors.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.catmullRom)

                if Double(b.spent) > anomalyThreshold && b.spent > 0 {
                    PointMark(
                        x: .value("Bucket", b.id),
                        y: .value("Spent", Double(b.spent) / 100.0)
                    )
                    .foregroundStyle(DS.Colors.danger)
                    .symbolSize(80)
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Colors.danger)
                    }
                }
            }

            if showPrevious {
                ForEach(alignedPrevious()) { p in
                    LineMark(
                        x: .value("Bucket", p.id),
                        y: .value("Previous", Double(p.spent) / 100.0),
                        series: .value("Series", "Previous")
                    )
                    .foregroundStyle(DS.Colors.subtext.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3]))
                    .interpolationMethod(.catmullRom)
                }
            }

            if showMovingAverage {
                ForEach(rollingAverage, id: \.index) { r in
                    LineMark(
                        x: .value("Bucket", r.index),
                        y: .value("Trend", r.value / 100.0),
                        series: .value("Series", "Trend")
                    )
                    .foregroundStyle(DS.Colors.positive.opacity(0.9))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
                    .interpolationMethod(.catmullRom)
                }
            }

            if let sel = selectedBucket {
                RuleMark(x: .value("Selected", sel.id))
                    .foregroundStyle(DS.Colors.text.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                PointMark(
                    x: .value("Selected", sel.id),
                    y: .value("Spent", Double(sel.spent) / 100.0)
                )
                .foregroundStyle(DS.Colors.accent)
                .symbolSize(120)
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
                                selectedBucket = b
                            }
                            .onEnded { _ in
                                // keep selection so user can read value
                            }
                    )
                    .onTapGesture {
                        selectedBucket = nil
                    }
            }
        }
    }

    private var selectionRow: some View {
        let b = selectedBucket ?? buckets.last!
        let avg = snapshot.kpi.averagePerBucket
        let deltaVsAvg = avg > 0 ? (Double(b.spent) - Double(avg)) / Double(avg) : 0
        let pct = Int((deltaVsAvg * 100).rounded())
        let isAnomaly = Double(b.spent) > anomalyThreshold && b.spent > 0

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(b.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)
                    .textCase(.uppercase)
                    .kerning(0.4)
                Text(b.spent.currencyFormatted(showDecimal: false))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
            }

            Spacer()

            if avg > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("vs avg")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.subtext)
                        .textCase(.uppercase)
                    HStack(spacing: 4) {
                        Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(pct >= 0 ? "+" : "")\(pct)%")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(pct > 5 ? DS.Colors.danger : (pct < -5 ? DS.Colors.positive : DS.Colors.subtext))
                }
            }

            if isAnomaly {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.Colors.danger)
            }
        }
        .padding(10)
        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func alignedPrevious() -> [ChartBucket] {
        // re-index previous buckets to the current bucket axis (by position)
        guard !previousBuckets.isEmpty else { return [] }
        let count = min(previousBuckets.count, buckets.count)
        return (0..<count).map { i in
            let p = previousBuckets[i]
            return ChartBucket(
                id: i,
                label: p.label,
                start: p.start,
                end: p.end,
                spent: p.spent,
                income: p.income,
                net: p.net,
                budget: p.budget,
                transactionCount: p.transactionCount
            )
        }
    }

    private func axisValues() -> [Int] {
        let count = buckets.count
        guard count > 0 else { return [] }
        if count <= 7 { return Array(0..<count) }
        let step = max(1, count / 6)
        return stride(from: 0, to: count, by: step).map { $0 }
    }
}

// MARK: - Toggle Pill

private struct TogglePill: View {
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
