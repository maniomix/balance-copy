import SwiftUI

// MARK: - Budget Heatmap V2

struct BudgetHeatmapV2: View {
    let store: Store
    let range: ChartRange

    @State private var selectedCell: HeatmapCell?

    private var snapshot: ChartsAnalytics.Snapshot {
        ChartsAnalytics.shared.snapshot(store: store, range: range, now: store.selectedMonth)
    }

    private var buckets: [ChartBucket] { snapshot.buckets }

    private var categoriesWithBudget: [Category] {
        store.allCategories.filter { c in
            // Include category if it has a cap for ANY bucket in range, OR had spending in range
            let anyBudget = buckets.contains { store.categoryBudget(for: c, month: $0.start) > 0 }
            let anySpend = snapshot.categories.first(where: { $0.category == c })?.amount ?? 0 > 0
            return anyBudget || anySpend
        }
    }

    var body: some View {
        if buckets.isEmpty || categoriesWithBudget.isEmpty {
            ChartEmptyState(message: "Set category budgets to see a heatmap")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                scale
                grid
                if let c = selectedCell {
                    detailCard(c)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    // MARK: Scale

    private var scale: some View {
        HStack(spacing: 6) {
            Text("Under")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
                .textCase(.uppercase)
            scaleSwatch(0.3)
            scaleSwatch(0.6)
            scaleSwatch(0.85)
            scaleSwatch(1.0)
            scaleSwatch(1.2)
            Text("Over")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
                .textCase(.uppercase)
            Spacer()
        }
    }

    private func scaleSwatch(_ ratio: Double) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(heatColor(ratio))
            .frame(width: 18, height: 10)
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                categoryLabels
                VStack(alignment: .leading, spacing: 4) {
                    monthHeaderRow
                    ForEach(categoriesWithBudget, id: \.storageKey) { cat in
                        HStack(spacing: 4) {
                            ForEach(buckets) { b in
                                cell(category: cat, bucket: b)
                            }
                        }
                    }
                }
            }
        }
    }

    private var categoryLabels: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // header row spacer
            Text(" ")
                .font(.system(size: 9))
                .frame(height: 14)
            ForEach(categoriesWithBudget, id: \.storageKey) { cat in
                HStack(spacing: 6) {
                    Circle()
                        .fill(cat.tint)
                        .frame(width: 6, height: 6)
                    Text(cat.title)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                        .lineLimit(1)
                }
                .frame(height: cellHeight, alignment: .leading)
            }
        }
        .frame(width: 100, alignment: .leading)
        .padding(.trailing, 8)
    }

    private var monthHeaderRow: some View {
        HStack(spacing: 4) {
            ForEach(buckets) { b in
                Text(b.label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)
                    .frame(width: cellWidth, height: 14)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    // MARK: Cell

    private func cell(category: Category, bucket: ChartBucket) -> some View {
        let spent = spentFor(category: category, bucket: bucket)
        let cap = capFor(category: category, bucket: bucket)
        let ratio = cap > 0 ? Double(spent) / Double(cap) : 0
        let isSelected = selectedCell?.category == category && selectedCell?.bucket.id == bucket.id

        return Button {
            let c = HeatmapCell(category: category, bucket: bucket, spent: spent, cap: cap, ratio: ratio)
            withAnimation(.easeInOut(duration: 0.2)) {
                if selectedCell == c { selectedCell = nil } else { selectedCell = c }
            }
            Haptics.selection()
        } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(heatColor(ratio, hasBudget: cap > 0, hasSpend: spent > 0))
                .frame(width: cellWidth, height: cellHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isSelected ? DS.Colors.text : Color.clear, lineWidth: 1.2)
                )
        }
        .buttonStyle(.plain)
    }

    private func detailCard(_ c: HeatmapCell) -> some View {
        let remaining = c.cap - c.spent
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(CategoryRegistry.shared.tint(for: c.category)).frame(width: 8, height: 8)
                Text(c.category.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                Text("·")
                    .foregroundStyle(DS.Colors.subtext)
                Text(c.bucket.label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)
                Spacer()
                if c.cap > 0 {
                    Text("\(Int((c.ratio * 100).rounded()))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(ratioTint(c.ratio))
                }
            }

            HStack(spacing: 10) {
                detailCell(label: "Spent", value: c.spent)
                if c.cap > 0 {
                    detailCell(label: "Budget", value: c.cap)
                    detailCell(label: remaining >= 0 ? "Left" : "Over", value: abs(remaining), tint: remaining >= 0 ? DS.Colors.positive : DS.Colors.danger)
                }
            }
        }
        .padding(10)
        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailCell(label: String, value: Int, tint: Color = DS.Colors.text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
            Text(value.currencyFormatted(showDecimal: false))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Data

    private func spentFor(category: Category, bucket: ChartBucket) -> Int {
        store.transactions
            .filter { $0.category == category && $0.type == .expense && !$0.isTransfer && $0.date >= bucket.start && $0.date < bucket.end }
            .reduce(0) { $0 + $1.amount }
    }

    private func capFor(category: Category, bucket: ChartBucket) -> Int {
        let monthlyCap = store.categoryBudget(for: category, month: bucket.start)
        guard monthlyCap > 0 else { return 0 }
        switch range.granularity {
        case .monthly: return monthlyCap
        case .weekly: return monthlyCap * 7 / 30
        case .daily:
            let r = Calendar.current.range(of: .day, in: .month, for: bucket.start) ?? 1..<31
            return monthlyCap / max(1, r.count)
        }
    }

    // MARK: Colors

    private func heatColor(_ ratio: Double, hasBudget: Bool = true, hasSpend: Bool = true) -> Color {
        if !hasBudget && !hasSpend { return DS.Colors.surface2 }
        if !hasBudget { return DS.Colors.subtext.opacity(0.15) }
        if ratio <= 0 { return DS.Colors.surface2 }
        if ratio < 0.5 { return DS.Colors.positive.opacity(0.35 + ratio * 0.4) }
        if ratio < 0.9 { return Color.orange.opacity(0.4 + (ratio - 0.5) * 0.8) }
        if ratio <= 1.0 { return Color.orange.opacity(0.85) }
        return DS.Colors.danger.opacity(min(1.0, 0.7 + (ratio - 1.0) * 0.5))
    }

    private func ratioTint(_ ratio: Double) -> Color {
        if ratio < 0.75 { return DS.Colors.positive }
        if ratio < 1.0 { return Color.orange }
        return DS.Colors.danger
    }

    // MARK: Metrics

    private var cellWidth: CGFloat {
        let count = buckets.count
        if count <= 7 { return 36 }
        if count <= 12 { return 28 }
        return 22
    }

    private let cellHeight: CGFloat = 22
}

// MARK: - Cell Model

struct HeatmapCell: Equatable {
    let category: Category
    let bucket: ChartBucket
    let spent: Int
    let cap: Int
    let ratio: Double
}
