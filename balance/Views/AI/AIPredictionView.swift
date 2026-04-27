import SwiftUI
import Charts

// ============================================================
// MARK: - AI Prediction View (Phase 5c — iOS-native port)
// ============================================================
//
// iOS-native prediction dashboard built against `AIPredictionEngine`
// (Phase 5b). Renders the core visualisations:
//   - Time-range picker (1M / 2M / 3M / 6M / 1Y)
//   - Forecast strip (projected spending vs budget, days left)
//   - Spending-trajectory chart (actual + projected, confidence band)
//   - Category projections with budget comparison
//   - Top merchants
//   - Weekly comparison card
//
// Intentionally simpler than the macOS 4,884-line view:
//   - No hover interactions (tap-to-inspect can come later)
//   - No trigger hover highlight coordinator (macOS-specific perf pattern)
//   - No streaming LLM combat plan in-view (Phase 5c follow-up)
//   - No hourly heatmap / deep-analysis wrap layout (Phase 5c follow-up)
// Everything uses iOS `Charts` + iOS `DS.Colors` tokens.
// ============================================================

struct AIPredictionView: View {
    @Binding var store: Store
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountManager: AccountManager

    @State private var timeRange: PredictionTimeRange = .thisMonth
    @State private var data: PredictionData?
    @State private var isLoading: Bool = true
    @State private var aiResult: AIPredictionResult?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    timeRangePicker
                    if isLoading && data == nil {
                        loadingPlaceholder
                    } else if let data {
                        forecastStrip(data: data)
                        trajectoryCard(data: data)
                        weeklyComparisonCard(data: data)
                        categoryProjectionsCard(data: data)
                        topMerchantsCard(data: data)
                        if let pressure = data.subscriptionPressure {
                            subscriptionPressureCard(pressure: pressure)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .navigationTitle("Predictions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { recompute() }
            .onChange(of: timeRange) { _, _ in recompute() }
        }
    }

    // MARK: - Time Range Picker

    private var timeRangePicker: some View {
        HStack(spacing: 6) {
            ForEach(PredictionTimeRange.allCases) { range in
                Button {
                    timeRange = range
                } label: {
                    Text(range.shortLabel)
                        .font(DS.Typography.callout)
                        .foregroundStyle(range == timeRange ? .white : DS.Colors.text)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(range == timeRange ? DS.Colors.accent : DS.Colors.surface)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Forecast Strip

    private func forecastStrip(data: PredictionData) -> some View {
        let f = data.forecast
        let over = f.totalBudget > 0 && f.projectedSpending > f.totalBudget
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(over ? DS.Colors.danger : DS.Colors.accent)
                Text("Projected spending")
                    .font(DS.Typography.section)
                Spacer()
                Text(timeRange.rawValue)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(currency(f.projectedSpending))
                    .font(DS.Typography.heroAmount)
                    .foregroundStyle(over ? DS.Colors.danger : DS.Colors.text)
                if f.totalBudget > 0 {
                    Text("/ \(currency(f.totalBudget))")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
            HStack(spacing: 18) {
                stat(label: "Spent", value: currency(f.spentSoFar), tint: DS.Colors.text)
                stat(label: "Income", value: currency(f.totalIncome), tint: DS.Colors.positive)
                stat(label: f.daysLeft == 0 ? "Complete" : "Days left", value: f.daysLeft == 0 ? "—" : "\(f.daysLeft)", tint: DS.Colors.subtext)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Colors.surface)
        )
    }

    // MARK: - Trajectory Chart

    @ViewBuilder
    private func trajectoryCard(data: PredictionData) -> some View {
        cardHeader(icon: "waveform.path.ecg", title: "Spending trajectory")

        Chart {
            // Confidence band as a filled area between lower/upper projection.
            ForEach(data.confidenceBand) { point in
                AreaMark(
                    x: .value("Day", point.dayIndex),
                    yStart: .value("Lower", point.lower),
                    yEnd: .value("Upper", point.upper)
                )
                .foregroundStyle(DS.Colors.accent.opacity(0.12))
            }

            // Cumulative line (solid for actual, dashed for projected).
            ForEach(data.spendingTrajectory) { point in
                LineMark(
                    x: .value("Day", point.dayIndex),
                    y: .value("Total", point.cumulative)
                )
                .foregroundStyle(point.isProjected ? DS.Colors.accent.opacity(0.7) : DS.Colors.accent)
                .lineStyle(StrokeStyle(
                    lineWidth: 2.5,
                    dash: point.isProjected ? [5, 3] : []
                ))
            }

            // Budget threshold rule.
            if data.forecast.totalBudget > 0 {
                RuleMark(y: .value("Budget", data.forecast.totalBudget))
                    .foregroundStyle(DS.Colors.warning.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Budget \(currency(data.forecast.totalBudget))")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.warning)
                    }
            }
        }
        .frame(height: 220)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine().foregroundStyle(DS.Colors.grid)
                AxisTick().foregroundStyle(DS.Colors.grid)
                AxisValueLabel().foregroundStyle(DS.Colors.subtext)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(DS.Colors.grid)
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(compactCurrency(raw))
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Colors.surface)
        )
    }

    // MARK: - Weekly Comparison

    private func weeklyComparisonCard(data: PredictionData) -> some View {
        let w = data.weeklyComparison
        let delta = w.percentChange
        let arrow: String
        let tint: Color
        if delta > 0.05 {
            arrow = "arrow.up.right"; tint = DS.Colors.danger
        } else if delta < -0.05 {
            arrow = "arrow.down.right"; tint = DS.Colors.positive
        } else {
            arrow = "arrow.right"; tint = DS.Colors.subtext
        }
        return VStack(alignment: .leading, spacing: 10) {
            cardHeader(icon: "calendar", title: "Week over week")
            HStack(spacing: 14) {
                weekBlock(label: "This week", value: w.thisWeek)
                weekBlock(label: "Last week", value: w.lastWeek)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: arrow)
                    Text(String(format: "%.0f%%", abs(delta) * 100))
                }
                .font(DS.Typography.callout)
                .foregroundStyle(tint)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.12))
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Colors.surface)
        )
    }

    private func weekBlock(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.subtext)
            Text(currency(value))
                .font(DS.Typography.number)
                .foregroundStyle(DS.Colors.text)
        }
    }

    // MARK: - Category Projections

    @ViewBuilder
    private func categoryProjectionsCard(data: PredictionData) -> some View {
        if !data.categoryProjections.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(icon: "chart.bar.fill", title: "Category projections")
                ForEach(data.categoryProjections.prefix(6)) { cat in
                    categoryRow(cat: cat)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Colors.surface)
            )
        }
    }

    private func categoryRow(cat: CategoryProjection) -> some View {
        let tint: Color = cat.isOverBudget ? DS.Colors.danger : (cat.percentOfBudget >= 0.8 ? DS.Colors.warning : DS.Colors.positive)
        let clampedProgress = min(max(cat.percentOfBudget, 0), 1.5) / 1.5
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: cat.icon.isEmpty ? "tag.fill" : cat.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                Text(cat.name)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Colors.text)
                Spacer()
                Text(currency(cat.projected))
                    .font(DS.Typography.number)
                    .foregroundStyle(tint)
                if cat.budget > 0 {
                    Text("/ \(currency(cat.budget))")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DS.Colors.text.opacity(0.06))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint)
                        .frame(width: geo.size.width * clampedProgress)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Top Merchants

    @ViewBuilder
    private func topMerchantsCard(data: PredictionData) -> some View {
        if !data.topMerchants.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(icon: "storefront", title: "Top merchants")
                ForEach(data.topMerchants.prefix(5)) { m in
                    HStack {
                        Text(m.name)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.text)
                            .lineLimit(1)
                        Spacer()
                        Text("×\(m.count)")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                            .frame(minWidth: 28, alignment: .trailing)
                        Text(currency(m.total))
                            .font(DS.Typography.number)
                            .foregroundStyle(DS.Colors.text)
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                    if m.id != data.topMerchants.prefix(5).last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Colors.surface)
            )
        }
    }

    // MARK: - AISubscription Pressure

    private func subscriptionPressureCard(pressure: SubscriptionPressure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader(icon: "arrow.triangle.2.circlepath", title: "AISubscriptions")
            HStack(spacing: 18) {
                stat(label: "Monthly", value: currency(pressure.monthlyTotal), tint: DS.Colors.accent)
                stat(label: "Active", value: "\(pressure.count)", tint: DS.Colors.text)
                if pressure.unusedCount > 0 {
                    stat(label: "Stale", value: "\(pressure.unusedCount)", tint: DS.Colors.warning)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Colors.surface)
        )
    }

    // MARK: - Loading / Empty

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.Colors.surface)
                .frame(height: 140)
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.Colors.surface)
                .frame(height: 240)
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.Colors.surface)
                .frame(height: 180)
        }
        .redacted(reason: .placeholder)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 36))
                .foregroundStyle(DS.Colors.subtext)
            Text("Not enough data yet")
                .font(DS.Typography.section)
            Text("Add a few transactions to see predictions.")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func cardHeader(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Colors.accent)
            Text(title)
                .font(DS.Typography.section)
                .foregroundStyle(DS.Colors.text)
            Spacer()
        }
    }

    private func stat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.subtext)
            Text(value)
                .font(DS.Typography.number)
                .foregroundStyle(tint)
        }
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = value >= 1000 ? 0 : 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "$%.0f", value)
    }

    private func compactCurrency(_ value: Double) -> String {
        switch abs(value) {
        case 1_000_000...: return String(format: "$%.1fM", value / 1_000_000)
        case 1_000...:     return String(format: "$%.0fk", value / 1_000)
        default:           return String(format: "$%.0f", value)
        }
    }

    // MARK: - Compute

    private func recompute() {
        isLoading = true
        let currentStore = store
        let accounts = accountManager.accounts
        let range = timeRange
        Task.detached(priority: .userInitiated) {
            let computed = AIPredictionEngine.compute(store: currentStore, accounts: accounts, range: range)
            let fallback = AIPredictionResult.fallback(from: computed)
            await MainActor.run {
                self.data = computed
                self.aiResult = fallback
                self.isLoading = false
            }
        }
    }
}
