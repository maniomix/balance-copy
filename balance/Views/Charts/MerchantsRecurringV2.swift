import SwiftUI
import Charts

// MARK: - Merchants & Recurring

struct MerchantsRecurringV2: View {
    let store: Store
    let range: ChartRange

    private var snapshot: ChartsAnalytics.Snapshot {
        ChartsAnalytics.shared.snapshot(store: store, range: range, now: store.selectedMonth)
    }

    private var topMerchants: [MerchantBucket] {
        Array(snapshot.merchants.prefix(10))
    }

    private var maxMerchantAmount: Int {
        topMerchants.map { $0.amount }.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            merchantsSection
            recurringSection
        }
    }

    // MARK: Merchants

    @ViewBuilder
    private var merchantsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "storefront.fill", title: "Top Merchants", caption: "\(topMerchants.count) in range")
            if topMerchants.isEmpty {
                ChartEmptyState(message: "No merchants in this period")
            } else {
                VStack(spacing: 6) {
                    ForEach(topMerchants) { merchant in
                        merchantRow(merchant)
                    }
                }
            }
        }
    }

    private func merchantRow(_ merchant: MerchantBucket) -> some View {
        let ratio = Double(merchant.amount) / Double(max(1, maxMerchantAmount))
        let spark = sparkData(for: merchant)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(merchant.merchant)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(1)
                Text("\(merchant.count)× · last \(shortDate(merchant.lastDate))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)
                    .lineLimit(1)
            }
            .frame(width: 110, alignment: .leading)

            // Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(DS.Colors.surface2)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(DS.Colors.accent.opacity(0.7))
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 22)

            // Spark
            if spark.count >= 2 {
                Chart(spark, id: \.bucket) { p in
                    LineMark(
                        x: .value("Bucket", p.bucket),
                        y: .value("Spent", Double(p.amount))
                    )
                    .foregroundStyle(DS.Colors.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartPlotStyle { $0.background(Color.clear) }
                .frame(width: 44, height: 22)
            } else {
                Color.clear.frame(width: 44, height: 22)
            }

            Text(merchant.amount.currencyFormatted(showDecimal: false))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
                .frame(width: 72, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 4)
    }

    private func sparkData(for merchant: MerchantBucket) -> [(bucket: Int, amount: Int)] {
        let buckets = snapshot.buckets
        return buckets.map { b in
            let sum = store.transactions
                .filter {
                    $0.type == .expense &&
                    $0.date >= b.start && $0.date < b.end &&
                    merchantKey(for: $0) == merchant.merchant
                }
                .reduce(0) { $0 + $1.amount }
            return (b.id, sum)
        }
    }

    private func merchantKey(for tx: Transaction) -> String {
        let note = tx.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? tx.category.title : note
    }

    // MARK: Recurring

    @ViewBuilder
    private var recurringSection: some View {
        let active = store.recurringTransactions.filter { $0.isActive }
        if active.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "arrow.triangle.2.circlepath", title: "Recurring in \(range.displayName)", caption: recurringCaption(active: active))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(recurringTiles(active: active)) { tile in
                            recurringTile(tile)
                        }
                    }
                }
            }
        }
    }

    private func recurringCaption(active: [RecurringTransaction]) -> String {
        let tiles = recurringTiles(active: active)
        let monthly = tiles.reduce(0) { $0 + $1.amount }
        return "\(tiles.count) · \(monthly.currencyFormatted(showDecimal: false))"
    }

    private func recurringTiles(active: [RecurringTransaction]) -> [RecurringTile] {
        let (start, end) = range.interval()
        let now = Date()
        return active.compactMap { rec -> RecurringTile? in
            guard let next = rec.nextOccurrence(from: now) else { return nil }
            let lastFired = rec.lastProcessedDate
            let firedInRange = (lastFired.map { $0 >= start && $0 < end }) ?? false
            let upcomingInRange = next >= start && next < end
            guard firedInRange || upcomingInRange else { return nil }
            let status: RecurringTile.Status = firedInRange ? .paid : .upcoming
            return RecurringTile(
                id: rec.id,
                name: rec.name.isEmpty ? rec.category.title : rec.name,
                amount: rec.amount,
                tint: CategoryRegistry.shared.tint(for: rec.category),
                icon: CategoryRegistry.shared.icon(for: rec.category),
                dueDate: firedInRange ? (lastFired ?? next) : next,
                status: status
            )
        }
        .sorted { $0.dueDate < $1.dueDate }
    }

    private func recurringTile(_ tile: RecurringTile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: tile.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tile.tint)
                Text(tile.status == .paid ? "PAID" : "UPCOMING")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(tile.status == .paid ? DS.Colors.positive : DS.Colors.accent)
                    .kerning(0.4)
            }
            Text(tile.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
                .lineLimit(1)
            Text(tile.amount.currencyFormatted(showDecimal: false))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(shortDate(tile.dueDate))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
        }
        .frame(width: 120, alignment: .leading)
        .padding(10)
        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tile.status == .upcoming ? DS.Colors.accent.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: Header

    private func sectionHeader(icon: String, title: String, caption: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Colors.accent)
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
            Spacer()
            Text(caption)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
        }
    }

    // MARK: Helpers

    private func shortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.setLocalizedDateFormatFromTemplate("d MMM")
        return fmt.string(from: date)
    }
}

private struct RecurringTile: Identifiable {
    let id: UUID
    let name: String
    let amount: Int
    let tint: Color
    let icon: String
    let dueDate: Date
    let status: Status

    enum Status { case paid, upcoming }
}
