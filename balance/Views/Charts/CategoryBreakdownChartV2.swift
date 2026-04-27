import SwiftUI
import Charts

// MARK: - Category Breakdown V2

struct CategoryBreakdownChartV2: View {
    let store: Store
    let range: ChartRange

    @State private var selectedID: String?
    @State private var drillDown: CategoryBucket?

    private var snapshot: ChartsAnalytics.Snapshot {
        ChartsAnalytics.shared.snapshot(store: store, range: range, now: store.selectedMonth)
    }

    private var categories: [CategoryBucket] {
        snapshot.categories.prefix(8).map { $0 }
    }

    private var total: Int { categories.reduce(0) { $0 + $1.amount } }

    private var selected: CategoryBucket? {
        if let id = selectedID { return categories.first { $0.id == id } }
        return nil
    }

    var body: some View {
        if categories.isEmpty {
            ChartEmptyState()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                donut
                    .frame(height: 200)
                topMovers
                legend
            }
            .sheet(item: $drillDown) { cat in
                CategoryDrillDownSheet(store: store, range: range, bucket: cat)
            }
        }
    }

    // MARK: Donut

    private var donut: some View {
        ZStack {
            Chart(categories) { item in
                SectorMark(
                    angle: .value("Amount", Double(item.amount)),
                    innerRadius: .ratio(selected?.id == item.id ? 0.52 : 0.58),
                    outerRadius: .ratio(selected?.id == item.id ? 1.0 : 0.92),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(CategoryRegistry.shared.tint(for: item.category))
                .opacity(selectedID == nil || selectedID == item.id ? 1.0 : 0.35)
            }
            .chartLegend(.hidden)
            .chartAngleSelection(value: Binding<Double?>(
                get: { nil },
                set: { newValue in
                    guard let newValue else { return }
                    let pick = pickCategory(forAngle: newValue)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if selectedID == pick?.id {
                            selectedID = nil
                        } else {
                            selectedID = pick?.id
                        }
                    }
                    Haptics.selection()
                }
            ))

            donutCenter
        }
    }

    private var donutCenter: some View {
        let cat = selected
        let amount = cat?.amount ?? total
        let label = cat?.category.title ?? "Total"
        let tint = cat.map { CategoryRegistry.shared.tint(for: $0.category) } ?? DS.Colors.accent
        let pct = total > 0 ? Double(amount) / Double(total) : 0
        let delta = cat?.deltaRatio ?? 0

        return VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
                .kerning(0.4)
                .lineLimit(1)

            Text(amount.currencyFormatted(showDecimal: false))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if cat != nil {
                HStack(spacing: 4) {
                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                    if let prev = cat?.previousAmount, prev > 0 {
                        Text("·")
                            .foregroundStyle(DS.Colors.subtext)
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(Int((delta * 100).rounded()))%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                }
                .foregroundStyle(delta > 0.05 ? DS.Colors.danger : (delta < -0.05 ? DS.Colors.positive : DS.Colors.subtext))
            } else {
                Text("\(categories.count) categories")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: 140)
    }

    private func pickCategory(forAngle value: Double) -> CategoryBucket? {
        // Chart's angle selection returns a cumulative angle value along the sweep
        var cumulative: Double = 0
        let total = Double(total)
        guard total > 0 else { return nil }
        for cat in categories {
            cumulative += Double(cat.amount)
            if value <= cumulative { return cat }
        }
        return categories.last
    }

    // MARK: Top Movers

    @ViewBuilder
    private var topMovers: some View {
        let eligible = categories.filter { $0.previousAmount > 0 }
        let risers = eligible.filter { $0.deltaRatio > 0.05 }.sorted { $0.deltaRatio > $1.deltaRatio }.prefix(2)
        let fallers = eligible.filter { $0.deltaRatio < -0.05 }.sorted { $0.deltaRatio < $1.deltaRatio }.prefix(2)
        let movers = Array(risers) + Array(fallers)

        if !movers.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Top Movers")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)
                    .textCase(.uppercase)
                    .kerning(0.4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(movers) { m in
                            MoverChip(bucket: m) {
                                drillDown = m
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Legend

    private var legend: some View {
        VStack(spacing: 4) {
            ForEach(categories) { item in
                Button {
                    Haptics.light()
                    drillDown = item
                } label: {
                    legendRow(item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func legendRow(_ item: CategoryBucket) -> some View {
        let pct = total > 0 ? Double(item.amount) / Double(total) * 100 : 0
        let highlight = selectedID == nil || selectedID == item.id
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(CategoryRegistry.shared.tint(for: item.category))
                .frame(width: 12, height: 12)

            Text(item.category.title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.text)

            if item.previousAmount > 0 {
                Image(systemName: item.deltaRatio >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(item.deltaRatio > 0.05 ? DS.Colors.danger : (item.deltaRatio < -0.05 ? DS.Colors.positive : DS.Colors.subtext))
            }

            Spacer()

            Text("\(Int(pct))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
                .frame(width: 36, alignment: .trailing)

            Text(item.amount.currencyFormatted(showDecimal: false))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
                .frame(width: 90, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Colors.subtext.opacity(0.6))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            highlight ? AnyShapeStyle(DS.Colors.surface2.opacity(0.5)) : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .opacity(highlight ? 1.0 : 0.45)
    }
}

// MARK: - Mover Chip

private struct MoverChip: View {
    let bucket: CategoryBucket
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(CategoryRegistry.shared.tint(for: bucket.category))
                    .frame(width: 8, height: 8)
                Text(bucket.category.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                HStack(spacing: 2) {
                    Image(systemName: bucket.deltaRatio >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("\(bucket.deltaRatio >= 0 ? "+" : "")\(Int((bucket.deltaRatio * 100).rounded()))%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(bucket.deltaRatio > 0 ? DS.Colors.danger : DS.Colors.positive)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DS.Colors.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Drill-Down Sheet

struct CategoryDrillDownSheet: View {
    let store: Store
    let range: ChartRange
    let bucket: CategoryBucket

    @Environment(\.dismiss) private var dismiss

    private var categoryTransactions: [Transaction] {
        let (start, end) = range.interval()
        return store.transactions
            .filter { $0.category == bucket.category && $0.type == .expense && !$0.isTransfer && $0.date >= start && $0.date < end }
            .sorted { $0.date > $1.date }
    }

    private var perBucketAmounts: [ChartBucket] {
        let snapshot = ChartsAnalytics.shared.snapshot(store: store, range: range, now: store.selectedMonth)
        return snapshot.buckets.map { b in
            let spent = store.transactions
                .filter { $0.category == bucket.category && $0.type == .expense && !$0.isTransfer && $0.date >= b.start && $0.date < b.end }
                .reduce(0) { $0 + $1.amount }
            return ChartBucket(
                id: b.id, label: b.label, start: b.start, end: b.end,
                spent: spent, income: 0, net: -spent, budget: 0,
                transactionCount: 0
            )
        }
    }

    private var topMerchants: [(name: String, amount: Int, count: Int)] {
        var totals: [String: (Int, Int)] = [:]
        for tx in categoryTransactions {
            let key = tx.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? bucket.category.title : tx.note.trimmingCharacters(in: .whitespacesAndNewlines)
            var entry = totals[key] ?? (0, 0)
            entry.0 += tx.amount
            entry.1 += 1
            totals[key] = entry
        }
        return totals
            .map { ($0.key, $0.value.0, $0.value.1) }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    trendCard
                    merchantsCard
                    transactionsCard
                }
                .padding()
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle(bucket.category.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
            }
        }
    }

    private var header: some View {
        let pct = bucket.deltaRatio
        return DS.Card {
            HStack(spacing: 14) {
                Circle()
                    .fill(CategoryRegistry.shared.tint(for: bucket.category).opacity(0.18))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: CategoryRegistry.shared.icon(for: bucket.category))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(CategoryRegistry.shared.tint(for: bucket.category))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(bucket.amount.currencyFormatted(showDecimal: false))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                    Text("\(bucket.count) transactions · \(range.displayName)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.subtext)
                }

                Spacer()

                if bucket.previousAmount > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("vs prev")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.subtext)
                            .textCase(.uppercase)
                        HStack(spacing: 3) {
                            Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(pct >= 0 ? "+" : "")\(Int((pct * 100).rounded()))%")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(pct > 0.05 ? DS.Colors.danger : (pct < -0.05 ? DS.Colors.positive : DS.Colors.subtext))
                    }
                }
            }
        }
    }

    private var trendCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Trend")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                let data = perBucketAmounts
                if data.allSatisfy({ $0.spent == 0 }) {
                    Text("No spending in this period")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(DS.Colors.subtext)
                } else {
                    Chart(data) { b in
                        BarMark(
                            x: .value("Bucket", b.id),
                            y: .value("Spent", Double(b.spent) / 100.0)
                        )
                        .foregroundStyle(CategoryRegistry.shared.tint(for: bucket.category).opacity(0.85))
                        .cornerRadius(3)
                    }
                    .frame(height: 120)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: min(6, data.count))) { val in
                            AxisValueLabel {
                                if let i = val.as(Int.self), i >= 0, i < data.count {
                                    Text(data[i].label)
                                        .font(.system(size: 9, design: .rounded))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine().foregroundStyle(DS.Colors.grid.opacity(0.3))
                            AxisValueLabel()
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var merchantsCard: some View {
        if !topMerchants.isEmpty {
            DS.Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Top Merchants")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)

                    ForEach(Array(topMerchants.enumerated()), id: \.offset) { _, m in
                        HStack {
                            Text(m.name)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(DS.Colors.text)
                                .lineLimit(1)
                            Spacer()
                            Text("\(m.count)×")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(DS.Colors.subtext)
                                .frame(width: 30, alignment: .trailing)
                            Text(m.amount.currencyFormatted(showDecimal: false))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.text)
                                .frame(width: 90, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var transactionsCard: some View {
        let top = Array(categoryTransactions.prefix(5))
        if !top.isEmpty {
            DS.Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Transactions")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)

                    ForEach(top) { tx in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.note.isEmpty ? bucket.category.title : tx.note)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(DS.Colors.text)
                                    .lineLimit(1)
                                Text(dateLabel(tx.date))
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                            Spacer()
                            Text(tx.amount.currencyFormatted(showDecimal: false))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.text)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: date)
    }
}

// Make CategoryBucket Identifiable-by-id for `.sheet(item:)`
extension CategoryBucket {
    // already Identifiable via `id: String` — no-op extension placeholder
}
