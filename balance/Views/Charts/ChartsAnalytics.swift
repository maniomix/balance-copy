import SwiftUI

// MARK: - Chart Range

enum ChartRange: Hashable, CaseIterable {
    case week
    case month
    case last3Months
    case last6Months
    case yearToDate
    case last12Months

    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .last3Months: return "3M"
        case .last6Months: return "6M"
        case .yearToDate: return "YTD"
        case .last12Months: return "12M"
        }
    }

    var granularity: ChartGranularity {
        switch self {
        case .week, .month: return .daily
        case .last3Months, .last6Months: return .weekly
        case .yearToDate, .last12Months: return .monthly
        }
    }

    /// Start/end dates relative to `now`. End is exclusive.
    func interval(now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        var cal = calendar
        cal.firstWeekday = calendar.firstWeekday
        let end: Date
        let start: Date

        switch self {
        case .week:
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            start = weekStart
            end = cal.date(byAdding: .day, value: 7, to: weekStart) ?? now
        case .month:
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            start = monthStart
            end = cal.date(byAdding: .month, value: 1, to: monthStart) ?? now
        case .last3Months:
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            start = cal.date(byAdding: .month, value: -2, to: monthStart) ?? now
            end = cal.date(byAdding: .month, value: 1, to: monthStart) ?? now
        case .last6Months:
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            start = cal.date(byAdding: .month, value: -5, to: monthStart) ?? now
            end = cal.date(byAdding: .month, value: 1, to: monthStart) ?? now
        case .yearToDate:
            start = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
            end = cal.date(byAdding: .day, value: 1, to: now) ?? now
        case .last12Months:
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            start = cal.date(byAdding: .month, value: -11, to: monthStart) ?? now
            end = cal.date(byAdding: .month, value: 1, to: monthStart) ?? now
        }
        return (start, end)
    }

    /// Previous comparable interval of the same length, ending at the current start.
    func previousInterval(now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        let current = interval(now: now, calendar: calendar)
        let length = calendar.dateComponents([.day], from: current.start, to: current.end).day ?? 30
        let prevEnd = current.start
        let prevStart = calendar.date(byAdding: .day, value: -length, to: prevEnd) ?? prevEnd
        return (prevStart, prevEnd)
    }
}

enum ChartGranularity {
    case daily
    case weekly
    case monthly
}

// MARK: - Bucket Types

struct ChartBucket: Identifiable, Hashable {
    let id: Int
    let label: String
    let start: Date
    let end: Date
    let spent: Int
    let income: Int
    let net: Int
    let budget: Int
    let transactionCount: Int
}

struct CategoryBucket: Identifiable, Hashable {
    let id: String
    let category: Category
    let amount: Int
    let count: Int
    let previousAmount: Int
    let deltaRatio: Double
}

struct MerchantBucket: Identifiable, Hashable {
    let id: String
    let merchant: String
    let amount: Int
    let count: Int
    let lastDate: Date
}

// MARK: - KPI Snapshot

struct ChartsKPI {
    let totalSpent: Int
    let totalIncome: Int
    let netSavings: Int
    let averagePerBucket: Int
    let previousTotalSpent: Int
    let spentDeltaRatio: Double
    let biggestCategory: Category?
    let biggestCategoryAmount: Int
    let transactionCount: Int
    let anomalyCount: Int
}

// MARK: - Charts Analytics Service

final class ChartsAnalytics {
    static let shared = ChartsAnalytics()

    private struct CacheKey: Hashable {
        let range: ChartRange
        let storeHash: Int
        let nowBucket: Int
    }

    private struct CachedSnapshot {
        let buckets: [ChartBucket]
        let previousBuckets: [ChartBucket]
        let categories: [CategoryBucket]
        let merchants: [MerchantBucket]
        let kpi: ChartsKPI
    }

    private var cache: [CacheKey: CachedSnapshot] = [:]

    func snapshot(store: Store, range: ChartRange, now: Date = Date()) -> Snapshot {
        let nowBucket = Int(now.timeIntervalSinceReferenceDate / 3600) // hourly cache key
        // Was `store.transactions.hashValue ^ store.budgetsByMonth.hashValue` —
        // `transactions.hashValue` walks every element, so the cache check
        // itself was O(n) on every chart render. `transactionsSignature` is
        // an O(n) walk too, but does only `>` comparisons over Dates and is
        // shared with the engines (Subscription/Forecast/Proactive), so the
        // cost is paid once per render across all gated callers.
        var hasher = Hasher()
        hasher.combine(store.transactionsSignature)
        hasher.combine(store.budgetsByMonth)
        let storeHash = hasher.finalize()
        let key = CacheKey(range: range, storeHash: storeHash, nowBucket: nowBucket)
        if let cached = cache[key] {
            return Snapshot(range: range, buckets: cached.buckets, previousBuckets: cached.previousBuckets, categories: cached.categories, merchants: cached.merchants, kpi: cached.kpi)
        }
        let cached = build(store: store, range: range, now: now)
        cache[key] = cached
        return Snapshot(range: range, buckets: cached.buckets, previousBuckets: cached.previousBuckets, categories: cached.categories, merchants: cached.merchants, kpi: cached.kpi)
    }

    func invalidate() { cache.removeAll() }

    struct Snapshot {
        let range: ChartRange
        let buckets: [ChartBucket]
        let previousBuckets: [ChartBucket]
        let categories: [CategoryBucket]
        let merchants: [MerchantBucket]
        let kpi: ChartsKPI
    }

    // MARK: Build

    private func build(store: Store, range: ChartRange, now: Date = Date()) -> CachedSnapshot {
        let cal = Calendar.current
        let (start, end) = range.interval(now: now)
        let (prevStart, prevEnd) = range.previousInterval(now: now)

        let txInRange = store.transactions.filter { $0.date >= start && $0.date < end }
        let txInPrev  = store.transactions.filter { $0.date >= prevStart && $0.date < prevEnd }

        let buckets = buildBuckets(store: store, range: range, start: start, end: end, transactions: txInRange, calendar: cal)
        let previousBuckets = buildBuckets(store: store, range: range, start: prevStart, end: prevEnd, transactions: txInPrev, calendar: cal)
        let categories = buildCategories(current: txInRange, previous: txInPrev)
        let merchants = buildMerchants(transactions: txInRange)
        let kpi = buildKPI(buckets: buckets, current: txInRange, previous: txInPrev, categories: categories)

        return CachedSnapshot(buckets: buckets, previousBuckets: previousBuckets, categories: categories, merchants: merchants, kpi: kpi)
    }

    private func buildBuckets(store: Store, range: ChartRange, start: Date, end: Date, transactions: [Transaction], calendar: Calendar) -> [ChartBucket] {
        var cursor = start
        var result: [ChartBucket] = []
        var index = 0

        while cursor < end {
            let bucketEnd: Date
            let label: String
            switch range.granularity {
            case .daily:
                bucketEnd = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end
                label = shortDayLabel(cursor, calendar: calendar)
            case .weekly:
                bucketEnd = calendar.date(byAdding: .day, value: 7, to: cursor) ?? end
                label = shortWeekLabel(cursor, calendar: calendar)
            case .monthly:
                bucketEnd = calendar.date(byAdding: .month, value: 1, to: cursor) ?? end
                label = shortMonthLabel(cursor, calendar: calendar)
            }

            let clampedEnd = min(bucketEnd, end)
            let slice = transactions.filter { $0.date >= cursor && $0.date < clampedEnd }
            let spent = slice.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
            let income = slice.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            let budget = budgetFor(range: range, bucketStart: cursor, store: store, calendar: calendar)

            result.append(ChartBucket(
                id: index,
                label: label,
                start: cursor,
                end: clampedEnd,
                spent: spent,
                income: income,
                net: income - spent,
                budget: budget,
                transactionCount: slice.count
            ))
            cursor = bucketEnd
            index += 1
        }
        return result
    }

    private func budgetFor(range: ChartRange, bucketStart: Date, store: Store, calendar: Calendar) -> Int {
        switch range.granularity {
        case .monthly:
            return store.budget(for: bucketStart)
        case .weekly:
            return store.budget(for: bucketStart) * 7 / 30
        case .daily:
            let monthRange = calendar.range(of: .day, in: .month, for: bucketStart) ?? 1..<31
            let days = max(1, monthRange.count)
            return store.budget(for: bucketStart) / days
        }
    }

    private func buildCategories(current: [Transaction], previous: [Transaction]) -> [CategoryBucket] {
        let expenses = current.filter { $0.type == .expense }
        let prevExpenses = previous.filter { $0.type == .expense }

        var totals: [Category: (amount: Int, count: Int)] = [:]
        for tx in expenses {
            var entry = totals[tx.category] ?? (0, 0)
            entry.amount += tx.amount
            entry.count += 1
            totals[tx.category] = entry
        }

        var prevTotals: [Category: Int] = [:]
        for tx in prevExpenses { prevTotals[tx.category, default: 0] += tx.amount }

        return totals
            .map { (cat, v) -> CategoryBucket in
                let prev = prevTotals[cat] ?? 0
                let delta = prev > 0 ? (Double(v.amount) - Double(prev)) / Double(prev) : 0
                return CategoryBucket(
                    id: cat.storageKey,
                    category: cat,
                    amount: v.amount,
                    count: v.count,
                    previousAmount: prev,
                    deltaRatio: delta
                )
            }
            .sorted { $0.amount > $1.amount }
    }

    private func buildMerchants(transactions: [Transaction]) -> [MerchantBucket] {
        let expenses = transactions.filter { $0.type == .expense }
        var totals: [String: (amount: Int, count: Int, last: Date)] = [:]
        for tx in expenses {
            let key = merchantKey(for: tx)
            guard !key.isEmpty else { continue }
            var entry = totals[key] ?? (0, 0, tx.date)
            entry.amount += tx.amount
            entry.count += 1
            if tx.date > entry.last { entry.last = tx.date }
            totals[key] = entry
        }
        return totals
            .map { (name, v) in
                MerchantBucket(id: name, merchant: name, amount: v.amount, count: v.count, lastDate: v.last)
            }
            .sorted { $0.amount > $1.amount }
    }

    private func buildKPI(buckets: [ChartBucket], current: [Transaction], previous: [Transaction], categories: [CategoryBucket]) -> ChartsKPI {
        let spent = current.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let income = current.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let prevSpent = previous.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }

        let delta = prevSpent > 0 ? (Double(spent) - Double(prevSpent)) / Double(prevSpent) : 0
        let avgPerBucket = buckets.isEmpty ? 0 : spent / max(1, buckets.count)

        let amounts = buckets.map { Double($0.spent) }
        let mean = amounts.isEmpty ? 0 : amounts.reduce(0, +) / Double(amounts.count)
        let variance = amounts.isEmpty ? 0 : amounts.map { pow($0 - mean, 2) }.reduce(0, +) / Double(amounts.count)
        let sigma = sqrt(variance)
        let anomalyThreshold = mean + (sigma * 2)
        let anomalies = amounts.filter { $0 > anomalyThreshold && $0 > 0 }.count

        return ChartsKPI(
            totalSpent: spent,
            totalIncome: income,
            netSavings: income - spent,
            averagePerBucket: avgPerBucket,
            previousTotalSpent: prevSpent,
            spentDeltaRatio: delta,
            biggestCategory: categories.first?.category,
            biggestCategoryAmount: categories.first?.amount ?? 0,
            transactionCount: current.count,
            anomalyCount: anomalies
        )
    }

    // MARK: Helpers

    private func merchantKey(for tx: Transaction) -> String {
        let note = tx.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return note }
        return tx.category.title
    }

    private func shortDayLabel(_ date: Date, calendar: Calendar) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = .current
        fmt.setLocalizedDateFormatFromTemplate("d MMM")
        return fmt.string(from: date)
    }

    private func shortWeekLabel(_ date: Date, calendar: Calendar) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = .current
        fmt.setLocalizedDateFormatFromTemplate("d MMM")
        return "w/\(fmt.string(from: date))"
    }

    private func shortMonthLabel(_ date: Date, calendar: Calendar) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = .current
        fmt.setLocalizedDateFormatFromTemplate("MMM")
        return fmt.string(from: date)
    }
}

// MARK: - Shared Chart States

struct ChartEmptyState: View {
    var message: String = "No data for this period"
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 28))
                .foregroundStyle(DS.Colors.subtext.opacity(0.3))
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
    }
}

struct ChartLoadingState: View {
    var height: CGFloat = 160
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(DS.Colors.surface2)
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0), Color.white.opacity(0.18), Color.white.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 200)
                .mask(RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
            .frame(height: height)
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
    }
}
