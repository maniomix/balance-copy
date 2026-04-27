import SwiftUI
import Charts

// MARK: - Advanced Charts View

struct AdvancedChartsView: View {
    @Binding var store: Store
    var initialRange: ChartRange? = nil
    var initialAnchor: String? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRange: ChartRange = .last3Months
    @State private var chatPrefill: String? = nil
    @State private var showAIChat: Bool = false
    @State private var exportShareURL: URL? = nil
    @State private var isExporting: Bool = false
    @State private var didSeedInitial: Bool = false
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        periodSelector
                        kpiStrip(proxy: proxy)
                        ChartsInsightsRail(
                            store: store,
                            range: selectedRange,
                            onScroll: { anchor in
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    proxy.scrollTo(anchor, anchor: .top)
                                }
                            },
                            onAsk: { prefill in
                                chatPrefill = prefill
                                showAIChat = true
                            }
                        )
                        spendingTrendCard
                            .id("chart.trend")
                        categoryPieCard
                            .id("chart.category")
                        incomeExpenseCard
                            .id("chart.cashflow")
                        monthlyComparisonCard
                            .id("chart.budget")
                        merchantsRecurringCard
                            .id("chart.merchants")

                        Spacer(minLength: 30)
                    }
                    .padding(.vertical)
                    .animation(.easeInOut(duration: 0.25), value: selectedRange)
                }
                .refreshable {
                    await refreshSnapshot()
                }
                .onAppear {
                    guard !didSeedInitial else { return }
                    didSeedInitial = true
                    if let r = initialRange { selectedRange = r }
                    if let anchor = initialAnchor {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(anchor, anchor: .top)
                            }
                        }
                    }
                }
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportPNG()
                    } label: {
                        if isExporting {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DS.Colors.accent)
                        }
                    }
                    .accessibilityLabel("Share charts as image")
                    .disabled(isExporting)
                }
            }
            .sheet(isPresented: $showAIChat) {
                AIChatView(store: $store, initialInput: chatPrefill)
            }
            .sheet(item: $exportShareURL) { url in
                ChartsShareSheet(items: [url])
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Refresh

    @MainActor
    private func refreshSnapshot() async {
        ChartsAnalytics.shared.invalidate()
        try? await Task.sleep(nanoseconds: 300_000_000)
        Haptics.light()
    }

    // MARK: - PNG Export

    @MainActor
    private func exportPNG() {
        guard !isExporting else { return }
        isExporting = true
        let range = selectedRange
        let view = ChartsExportRender(store: store, range: range)
            .frame(width: 390)
            .padding(.vertical, 16)
            .background(DS.Colors.bg)

        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        renderer.proposedSize = ProposedViewSize(width: 390, height: nil)

        if let image = renderer.uiImage, let data = image.pngData() {
            let filename = "Centmond_Charts_\(range.displayName).png"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try? data.write(to: url, options: .atomic)
            Haptics.exportSuccess()
            exportShareURL = url
        } else {
            Haptics.error()
        }
        isExporting = false
    }
    
    // MARK: - KPI Strip

    private func kpiStrip(proxy: ScrollViewProxy) -> some View {
        let range = selectedRange
        let snapshot = ChartsAnalytics.shared.snapshot(store: store, range: range, now: store.selectedMonth)
        return ChartsKPIStrip(kpi: snapshot.kpi, range: range) { pill in
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(pill.scrollAnchor, anchor: .top)
            }
        }
    }

    // MARK: - Period Selector
    
    private var periodSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ChartRange.allCases, id: \.self) { range in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedRange = range
                        }
                        Haptics.selection()
                    } label: {
                        Text(range.displayName)
                            .font(.system(size: 13, weight: selectedRange == range ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(selectedRange == range ? Color(uiColor: .systemBackground) : DS.Colors.subtext)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                selectedRange == range
                                ? AnyShapeStyle(Color(uiColor: .label))
                                : AnyShapeStyle(DS.Colors.surface2),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Spending Trend
    
    private var spendingTrendCard: some View {
        chartCard(icon: "chart.line.uptrend.xyaxis", title: "Spending Trend") {
            SpendingTrendChartV2(store: store, range: selectedRange)
        }
    }
    
    // MARK: - Category Pie
    
    private var categoryPieCard: some View {
        chartCard(icon: "chart.pie.fill", title: "Category Breakdown") {
            CategoryBreakdownChartV2(store: store, range: selectedRange)
        }
    }
    
    // MARK: - Income vs Expense
    
    private var incomeExpenseCard: some View {
        chartCard(icon: "chart.bar.fill", title: "Cashflow") {
            CashflowChartV2(store: store, range: selectedRange)
        }
    }
    
    // MARK: - Monthly Comparison
    
    private var monthlyComparisonCard: some View {
        chartCard(icon: "square.grid.3x3.fill", title: "Budget Performance") {
            BudgetHeatmapV2(store: store, range: selectedRange)
        }
    }

    // MARK: - Merchants & Recurring

    private var merchantsRecurringCard: some View {
        chartCard(icon: "storefront.fill", title: "Merchants & Recurring") {
            MerchantsRecurringV2(store: store, range: selectedRange)
        }
    }
    
    // MARK: - Chart Card Template
    
    private func chartCard<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)

                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)

                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(title)

                content()
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }
}
