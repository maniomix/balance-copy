import SwiftUI
import Charts

// MARK: - Dashboard

struct DashboardView: View {
    @Binding var store: Store
    let goToBudget: () -> Void
    var goToTransactions: (() -> Void)? = nil
    @State private var showAdd = false
    @State private var trendSelectedDay: Int? = nil
    @State private var showTrendAnalytics: Bool = false
    @State private var trendPage: TrendChartPage = .pace
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var supabaseManager: SupabaseManager

    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return fmt.string(from: store.selectedMonth)
    }

    private var todayDay: String {
        let cal = Calendar.current
        let day = cal.component(.day, from: Date())
        return "\(day)"
    }

    private func dateString(forDay day: Int) -> String {
        var cal = Calendar.current
        cal.locale = .current
        var comps = cal.dateComponents([.year, .month], from: store.selectedMonth)
        comps.day = day
        let d = cal.date(from: comps) ?? store.selectedMonth

        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return fmt.string(from: d)
    }

    @State private var showDeleteMonthConfirm = false
    @State private var showTrashAlert = false
    @State private var trashAlertText = ""
    @State private var showSaveFailedAlert = false
    @State private var showPaywall = false
    @State private var isRefreshing = false

    // Copilot engine state
    @State private var healthScore: HealthScoreEngine.HealthScore?
    @State private var actionCards: [ActionCard] = []

    // AI
    @State private var showAIChat = false
    @State private var showProactiveFeed = false
    @State private var showMonthlyBriefing = false
    @StateObject private var insightEngine = AIInsightEngine.shared
    @StateObject private var budgetRescue = AIBudgetRescue.shared
    @StateObject private var proactiveEngine = AIProactiveEngine.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    // SECTION: Month Header
                    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    header

                    if store.budgetTotal <= 0 {
                        SetupCard(goToBudget: goToBudget)
                    } else {

                        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        // SECTION: Overview
                        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        VStack(spacing: 12) {
                            DS.SectionHeader(title: "Overview", icon: "chart.bar.fill")

                            kpis
                            trendCard
                        }

                        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        // SECTION: Actions & Health
                        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        VStack(spacing: 12) {
                            ActionCardsView(
                                cards: actionCards,
                                monthKey: {
                                    let cal = Calendar.current
                                    let y = cal.component(.year, from: store.selectedMonth)
                                    let m = cal.component(.month, from: store.selectedMonth)
                                    return String(format: "%04d-%02d", y, m)
                                }()
                            )

                            if let score = healthScore {
                                HealthScoreCard(score: score)
                            }

                            SafeToSpendCard()
                        }

                        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        // SECTION: Activity
                        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        VStack(spacing: 12) {
                            DS.SectionHeader(title: "Activity", icon: "clock.fill")

                            UpcomingBillsDashboardCard()
                            categoryCard
                        }

                        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        // SECTION: Insights & Projections
                        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        VStack(spacing: 12) {
                            DS.SectionHeader(title: "Insights", icon: "lightbulb.fill")

                            ForecastDashboardCard()
                            NetWorthDashboardCard(store: $store)
                            PlanningInsightsDashboardCard()
                        }

                        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        // SECTION: Goals & Review
                        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        VStack(spacing: 12) {
                            DS.SectionHeader(title: "Goals", icon: "target")

                            GoalsDashboardCard(store: $store)
                            ReviewDashboardCard(store: $store)
                        }

                        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        // SECTION: More
                        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        VStack(spacing: 12) {
                            DS.SectionHeader(title: "More", icon: "ellipsis.circle.fill")

                            SubscriptionsDashboardCard(store: $store)
                            HouseholdDashboardCard(store: $store)

                            // Payment breakdown — horizontal scroll
                            paymentBreakdownCard
                        }

                        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        // SECTION: AI Advisor
                        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        VStack(spacing: 12) {
                            DS.SectionHeader(title: "AI Advisor", icon: "sparkles")

                            // Budget Rescue Mode
                            if let plan = budgetRescue.plan, plan.isActive {
                                DS.Card {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(plan.budgetUsedPercent >= 100 ? DS.Colors.danger : DS.Colors.warning)
                                            Text("Budget Rescue")
                                                .font(DS.Typography.callout)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(DS.Colors.text)
                                            Spacer()
                                            Text("\(plan.budgetUsedPercent)% used")
                                                .font(DS.Typography.caption)
                                                .foregroundStyle(plan.budgetUsedPercent >= 100 ? DS.Colors.danger : DS.Colors.warning)
                                        }

                                        ForEach(plan.tips, id: \.self) { tip in
                                            Text("• \(tip)")
                                                .font(DS.Typography.caption)
                                                .foregroundStyle(DS.Colors.subtext)
                                        }

                                        if !plan.reductionTargets.isEmpty {
                                            Divider().foregroundStyle(DS.Colors.grid)
                                            ForEach(plan.reductionTargets) { target in
                                                HStack {
                                                    Text(target.category)
                                                        .font(DS.Typography.caption)
                                                        .foregroundStyle(DS.Colors.text)
                                                    Spacer()
                                                    Text("Save \(String(format: "$%.0f", Double(target.savingsIfReduced) / 100.0))")
                                                        .font(DS.Typography.caption)
                                                        .foregroundStyle(DS.Colors.positive)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Proactive AI items (Phase 6) ──
                            AIProactiveBanner(store: $store,
                                              onOpenFeed: { showProactiveFeed = true },
                                              onOpenChat: { showAIChat = true })

                            // Morning briefing (legacy — kept as fallback if proactive briefing is dismissed)
                            if proactiveEngine.morningBriefing == nil,
                               let briefing = insightEngine.morningBriefing {
                                AIInsightBanner(insight: briefing)
                            }

                            // AI insight row
                            if !insightEngine.insights.isEmpty {
                                AIInsightRow(insights: insightEngine.insights) { action in
                                    showAIChat = true
                                }
                            }

                            // Monthly briefing entry
                            monthlyBriefingEntryCard

                        }

                        advisorInsightsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .background(DS.Colors.bg)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Sync Status (center)
                ToolbarItem(placement: .principal) {
                    SyncStatusView(store: $store)
                }

                // Month actions menu (leading)
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(role: .destructive) {
                            let hasTx = !Analytics.monthTransactions(store: store).isEmpty
                            let hasBudget = store.budgetTotal > 0
                            let hasCaps = store.totalCategoryBudgets() > 0
                            let hasAnything = hasTx || hasBudget || hasCaps

                            if hasAnything {
                                showDeleteMonthConfirm = true
                            } else {
                                trashAlertText = "This month has already been cleared. There is nothing left to delete."
                                showTrashAlert = true
                            }
                        } label: {
                            Label("Clear This Month", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    .accessibilityLabel("Month actions")
                }

                // Add button (trailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.medium()
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(DS.Colors.text)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add transaction")
                }
            }
        }
        .onAppear {
            AnalyticsManager.shared.track(.dashboardViewed)
            // Generate engines in parallel on appear
            Task {
                async let f: () = ForecastEngine.shared.generate(store: store)
                async let s: () = SubscriptionEngine.shared.analyze(store: store)
                async let r: () = ReviewEngine.shared.analyze(store: store)
                async let a: () = AccountManager.shared.fetchAccounts()
                async let g: () = GoalManager.shared.fetchGoals()
                async let x: () = CurrencyConverter.shared.fetchRatesIfNeeded()
                _ = await (f, s, r, a, g, x)
                await WidgetDataWriter.update(store: store)

                // Compute copilot features after engines are ready
                computeCopilotData()

                // Refresh AI insights + rescue mode + proactive items
                insightEngine.refresh(store: store)
                budgetRescue.evaluate(store: store)
                proactiveEngine.clearStaleDismissals()
                proactiveEngine.refresh(store: store)
            }
        }
        .onChange(of: store.selectedMonth) { _, _ in
            // Recompute everything when user switches months
            Task {
                async let f: () = ForecastEngine.shared.generate(store: store)
                async let s: () = SubscriptionEngine.shared.analyze(store: store)
                _ = await (f, s)
                computeCopilotData()
                insightEngine.refresh(store: store)
                budgetRescue.evaluate(store: store)
            }
        }
        .alert("Delete This Month", isPresented: $showDeleteMonthConfirm) {
            Button("Delete", role: .destructive) {
                let result = TransactionService.performClearMonth(store.selectedMonth, store: &store)

                switch result {
                case .localSaveFailed:
                    showSaveFailedAlert = true
                case .noChange:
                    trashAlertText = "No data found for this month"
                    showTrashAlert = true
                case .savedLocally:
                    Haptics.success()
                    trashAlertText = "This month's data has been successfully deleted"
                    showTrashAlert = true
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all transactions for this month. This action cannot be undone.")
        }
        .alert("Trash", isPresented: $showTrashAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(trashAlertText)
        }
        .alert("Save Failed", isPresented: $showSaveFailedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Month data could not be saved. Please try again.")
        }
        .sheet(isPresented: $showAdd) {
            AddTransactionSheet(store: $store, initialMonth: store.selectedMonth)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPaywall) {
        }
        .sheet(isPresented: $showAIChat) {
            AIChatView(store: $store)
        }
        .sheet(isPresented: $showProactiveFeed) {
            AIProactiveView(store: $store)
        }
        .sheet(isPresented: $showMonthlyBriefing) {
            NavigationStack {
                MonthlyBriefingScreen(store: $store)
            }
        }
    }

    // MARK: - Monthly Briefing entry card

    private var monthlyBriefingEntryCard: some View {
        Button { showMonthlyBriefing = true } label: {
            DS.Card {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(DS.Colors.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Monthly Briefing")
                            .font(DS.Typography.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(DS.Colors.text)
                        Text("Your \(monthTitle) overview at a glance")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Monthly Briefing for \(monthTitle).")
        .accessibilityHint("Double tap to open your personalized financial summary.")
    }

    // MARK: - Header

    private var header: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(todayDay)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.text)

                            Text(monthTitle)
                                .font(DS.Typography.title)
                                .foregroundStyle(DS.Colors.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Text("Data for month")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }

                    Spacer(minLength: 12)

                    MonthPicker(selectedMonth: $store.selectedMonth)
                }

                if store.budgetTotal <= 0 {
                    DS.StatusLine(
                        title: "Start from zero",
                        detail: "Set your monthly budget first. Analysis will start immediately.",
                        level: .watch
                    )
                } else {
                    if let capPressure = Analytics.categoryCapPressure(store: store) {
                        DS.StatusLine(title: capPressure.title, detail: capPressure.detail, level: capPressure.level)
                    } else {
                        let pressure = Analytics.budgetPressure(store: store)
                        DS.StatusLine(title: pressure.title, detail: pressure.detail, level: pressure.level)
                    }
                }
            }
        }
    }

    // MARK: - KPI Square (Simplified — no heavy borders)
    private struct KPISquare: View {
        let title: String
        let value: String
        var accentColor: Color? = nil

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                Text(value)
                    .font(DS.Typography.number)
                    .foregroundStyle(accentColor ?? DS.Colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        accentColor != nil
                            ? (accentColor ?? DS.Colors.text).opacity(colorScheme == .dark ? 0.35 : 0.25)
                            : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)),
                        lineWidth: accentColor != nil ? 1.5 : 1
                    )
            )
        }
    }

    @State private var showBudgetBubble = false
    @State private var showTxCountBubble = false

    private var kpis: some View {
        let summary = Analytics.monthSummary(store: store)
        let isOverBudget = summary.remaining < 0
        let tx = Analytics.monthTransactions(store: store)
        let totalIncome = tx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let budget = store.budgetTotal
        let spentRatio = budget > 0 ? min(1.0, Double(summary.totalSpent) / Double(budget)) : 0

        return VStack(spacing: 8) {
            // 3 KPI squares
            HStack(spacing: 10) {
                KPISquare(
                    title: "Income",
                    value: DS.Format.money(totalIncome),
                    accentColor: totalIncome > 0 ? DS.Colors.positive : nil
                )
                KPISquare(
                    title: "Spent",
                    value: DS.Format.money(summary.totalSpent),
                    accentColor: isOverBudget ? DS.Colors.danger : nil
                )
                KPISquare(
                    title: isOverBudget ? "Over" : "Remaining",
                    value: DS.Format.money(abs(summary.remaining)),
                    accentColor: isOverBudget ? DS.Colors.danger : summary.remaining > 0 ? DS.Colors.positive : nil
                )
            }

            // Compact pill row
            HStack(spacing: 6) {
                // Budget % pill
                if budget > 0 {
                    ZStack(alignment: .top) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showBudgetBubble.toggle()
                                if showBudgetBubble { showTxCountBubble = false }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(DS.Colors.surface2).frame(height: 4)
                                        Capsule()
                                            .fill(
                                                spentRatio > 0.9 ? DS.Colors.danger :
                                                spentRatio > 0.7 ? DS.Colors.warning :
                                                DS.Colors.accent
                                            )
                                            .frame(width: geo.size.width * spentRatio, height: 4)
                                    }
                                }
                                .frame(width: 28, height: 4)

                                Text("\(Int(spentRatio * 100))%")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(
                                        spentRatio > 0.9 ? DS.Colors.danger :
                                        spentRatio > 0.7 ? DS.Colors.warning :
                                        DS.Colors.subtext
                                    )
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(DS.Colors.surface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Daily avg
                HStack(spacing: 3) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.system(size: 9, weight: .semibold))
                    Text(DS.Format.money(summary.dailyAvg) + "/d")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .foregroundStyle(DS.Colors.subtext)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(DS.Colors.surface, in: Capsule())

                Spacer()

                // Transaction count pill (current month only)
                if !subscriptionManager.isPro {
                    let currentCount = Analytics.monthTransactions(store: store).count
                    let freeLimit = 50
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showTxCountBubble.toggle()
                            if showTxCountBubble { showBudgetBubble = false }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: currentCount > 40 ? "exclamationmark.triangle.fill" : "number")
                                .font(.system(size: 9))
                                .foregroundStyle(currentCount > 40 ? DS.Colors.warning : DS.Colors.subtext)
                            Text("\(currentCount)/\(freeLimit)")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(DS.Colors.subtext)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(DS.Colors.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Budget detail bubble (expands on tap)
            if showBudgetBubble && budget > 0 {
                budgetDetailBubble(summary: summary, budget: budget, spentRatio: spentRatio)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.95, anchor: .top).combined(with: .opacity)
                    ))
            }

            // Free plan bubble (expands on tap)
            if showTxCountBubble && !subscriptionManager.isPro {
                freePlanBubble
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.95, anchor: .top).combined(with: .opacity)
                    ))
            }
        }
    }

    // MARK: - Budget Detail Bubble
    private func budgetDetailBubble(summary: Analytics.MonthSummary, budget: Int, spentRatio: Double) -> some View {
        let barColor: Color = spentRatio > 0.9 ? DS.Colors.danger : spentRatio > 0.7 ? DS.Colors.warning : DS.Colors.accent
        let remaining = budget - summary.totalSpent
        let isOver = remaining < 0

        return VStack(spacing: 12) {
            // Header
            HStack {
                Text("Budget Overview")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                Spacer()
                Text(DS.Format.money(budget))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.Colors.subtext)
            }

            // Progress bar
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(DS.Colors.surface2)
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: [barColor.opacity(0.7), barColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: w * min(1.0, spentRatio), height: 10)

                    // Threshold markers
                    Rectangle()
                        .fill(DS.Colors.warning.opacity(0.6))
                        .frame(width: 1.5, height: 14)
                        .offset(x: w * 0.7 - 0.75)
                    Rectangle()
                        .fill(DS.Colors.danger.opacity(0.6))
                        .frame(width: 1.5, height: 14)
                        .offset(x: w * 0.9 - 0.75)
                }
            }
            .frame(height: 10)

            // Scale labels
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Text("0%")
                        .position(x: 10, y: 6)
                        .foregroundStyle(DS.Colors.subtext)
                    Text("50%")
                        .position(x: w * 0.5, y: 6)
                        .foregroundStyle(DS.Colors.subtext)
                    Text("70%")
                        .position(x: w * 0.7, y: 6)
                        .foregroundStyle(DS.Colors.warning)
                    Text("100%")
                        .position(x: w - 16, y: 6)
                        .foregroundStyle(DS.Colors.subtext)
                }
                .font(.system(size: 8, weight: .medium, design: .rounded))
            }
            .frame(height: 12)

            // Percentage used
            Text("\(Int(spentRatio * 100))% used")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(barColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(barColor.opacity(0.1), in: Capsule())
                .frame(maxWidth: .infinity)

            // Spent / Remaining row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                    Text(DS.Format.money(summary.totalSpent))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(DS.Colors.text)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(isOver ? "Over" : "Left")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                    Text(DS.Format.money(abs(remaining)))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(isOver ? DS.Colors.danger : DS.Colors.positive)
                }
            }
        }
        .padding(14)
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Free Plan Bubble
    private var freePlanBubble: some View {
        let currentCount = Analytics.monthTransactions(store: store).count
        let freeLimit = 50
        let usage = Double(currentCount) / Double(freeLimit)
        let barColor: Color = usage > 0.8 ? DS.Colors.warning : DS.Colors.accent

        return VStack(spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.accent)
                    Text("Free Plan")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                }
                Spacer()
                Text("\(currentCount) of \(freeLimit) transactions")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)
            }

            // Usage bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Colors.surface2)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * min(1.0, usage), height: 8)
                }
            }
            .frame(height: 8)

            if currentCount > 40 {
                Text("You're running low — unlimited transactions Available for Pro Users")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.Colors.warning)
            }
        }
        .padding(12)
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Trend Chart

    private var trendCard: some View {
        let model = DashboardTrendModel(store: store, selectedMonth: store.selectedMonth)
        let points = model.dailyPoints
        let pace = model.idealPace
        let prev = model.prevMonthCumulative

        return DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    trendPageSelector(hasPace: !pace.isEmpty, hasPrev: !prev.isEmpty)
                    Spacer(minLength: 8)
                    Button {
                        Haptics.light()
                        showTrendAnalytics = true
                    } label: {
                        Text("advanced")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.subtext)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(DS.Colors.surface2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open full analytics")
                }
                .padding(.bottom, 8)

                if points.isEmpty {
                    Text("Not enough data")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                        .padding(.vertical, 6)
                } else {
                    Group {
                        switch trendPage {
                        case .pace:      paceChart(points: points, pace: pace)
                        case .lastMonth: lastMonthChart(points: points, prev: prev)
                        case .daily:     dailyChart(points: points)
                        }
                    }
                    .frame(height: 200)
                    .accessibilityLabel(trendChartA11yLabel(headline: model.headline))
                    .transition(.opacity)
                    .id(trendPage)

                    trendLegendForPage(hasPace: !pace.isEmpty, hasPrev: !prev.isEmpty)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: store.selectedMonth)
        }
        .sheet(isPresented: $showTrendAnalytics) {
            AdvancedChartsView(
                store: $store,
                initialRange: .month,
                initialAnchor: "chart.trend"
            )
        }
    }

    // MARK: - Trend pages

    enum TrendChartPage: String, CaseIterable, Hashable {
        case pace, lastMonth, daily
        var title: String {
            switch self {
            case .pace: return "Pace"
            case .lastMonth: return "vs Last Month"
            case .daily: return "Daily"
            }
        }
    }

    @ViewBuilder
    private func trendPageSelector(hasPace: Bool, hasPrev: Bool) -> some View {
        let pages: [TrendChartPage] = TrendChartPage.allCases.filter { p in
            switch p {
            case .pace: return hasPace
            case .lastMonth: return hasPrev
            case .daily: return true
            }
        }
        if pages.count > 1 {
            HStack(spacing: 6) {
                ForEach(pages, id: \.self) { page in
                    Button {
                        guard trendPage != page else { return }
                        trendSelectedDay = nil
                        withAnimation(.easeInOut(duration: 0.25)) {
                            trendPage = page
                        }
                        Haptics.selection()
                    } label: {
                        Text(page.title)
                            .font(.system(size: 11, weight: trendPage == page ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(trendPage == page ? Color(uiColor: .systemBackground) : DS.Colors.subtext)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                trendPage == page
                                ? AnyShapeStyle(Color(uiColor: .label))
                                : AnyShapeStyle(DS.Colors.surface2),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear {
                if !pages.contains(trendPage) { trendPage = pages.first ?? .daily }
            }
        }
    }

    @ViewBuilder
    private func trendLegendForPage(hasPace: Bool, hasPrev: Bool) -> some View {
        HStack(spacing: 10) {
            Spacer()
            switch trendPage {
            case .pace:
                if hasPace {
                    legendHint(label: "pace", opacity: 0.5, dash: [4, 3])
                        .accessibilityLabel("Ideal budget pace reference line")
                }
            case .lastMonth:
                if hasPrev {
                    legendHint(label: "last mo", opacity: 0.4, dash: [2, 3])
                        .accessibilityLabel("Previous month cumulative spending")
                }
            case .daily:
                EmptyView()
            }
        }
    }

    // MARK: - Per-page charts

    private func paceChart(points: [DashboardTrendModel.DayPoint],
                           pace: [DashboardTrendModel.PacePoint]) -> some View {
        Chart {
            ForEach(pace) { p in
                LineMark(
                    x: .value("Day", p.day),
                    y: .value("Target", p.target),
                    series: .value("Series", "Pace")
                )
                .foregroundStyle(DS.Colors.subtext.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3]))
            }
            ForEach(points) { p in
                AreaMark(
                    x: .value("Day", p.day),
                    yStart: .value("Baseline", 0),
                    yEnd: .value("Cumulative", p.cumulative)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [DS.Colors.accent.opacity(0.28), DS.Colors.accent.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
            ForEach(points) { p in
                LineMark(
                    x: .value("Day", p.day),
                    y: .value("Cumulative", p.cumulative),
                    series: .value("Series", "Spent")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(DS.Colors.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .modifier(TrendChartAxes())
        .chartOverlay { proxy in trendChartOverlay(proxy: proxy, mode: .pace) }
    }

    private func lastMonthChart(points: [DashboardTrendModel.DayPoint],
                                prev: [DashboardTrendModel.DayPoint]) -> some View {
        Chart {
            ForEach(prev) { p in
                LineMark(
                    x: .value("Day", p.day),
                    y: .value("PrevCumulative", p.cumulative),
                    series: .value("Series", "Previous")
                )
                .foregroundStyle(DS.Colors.subtext.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [2, 3]))
                .interpolationMethod(.catmullRom)
            }
            ForEach(points) { p in
                LineMark(
                    x: .value("Day", p.day),
                    y: .value("Cumulative", p.cumulative),
                    series: .value("Series", "Spent")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(DS.Colors.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .modifier(TrendChartAxes())
        .chartOverlay { proxy in trendChartOverlay(proxy: proxy, mode: .lastMonth) }
    }

    private func dailyChart(points: [DashboardTrendModel.DayPoint]) -> some View {
        Chart {
            ForEach(points) { p in
                BarMark(
                    x: .value("Day", p.day),
                    y: .value("Spent", p.spent)
                )
                .cornerRadius(3)
                .foregroundStyle(
                    p.isAnomaly
                    ? DS.Colors.danger.opacity(0.85)
                    : DS.Colors.accent.opacity(p.spent > 0 ? 0.85 : 0.25)
                )
            }
        }
        .modifier(TrendChartAxes())
        .chartOverlay { proxy in trendChartOverlay(proxy: proxy, mode: .daily) }
    }

    private func trendChartA11yLabel(headline h: DashboardTrendModel.Headline) -> String {
        var parts: [String] = []
        parts.append("Daily cumulative spending chart")
        parts.append("Spent \(h.spent.currencyFormatted(showDecimal: false))")
        if h.budget > 0 {
            parts.append("of \(h.budget.currencyFormatted(showDecimal: false)) budget")
        }
        return parts.joined(separator: ", ")
    }

    private func legendHint(label: String, opacity: Double, dash: [CGFloat]) -> some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(DS.Colors.subtext.opacity(opacity))
                .frame(width: 12, height: 1.5)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
                .textCase(.uppercase)
                .kerning(0.4)
        }
    }

    enum TrendOverlayMode { case pace, lastMonth, daily }

    @ViewBuilder
    private func trendChartOverlay(proxy: ChartProxy, mode: TrendOverlayMode) -> some View {
        GeometryReader { geo in
            if let plotAnchor = proxy.plotFrame {
                let frame = geo[plotAnchor]

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(trendDragGesture(proxy: proxy, frame: frame))

                    if let selDay = trendSelectedDay {
                        trendTooltipView(
                            proxy: proxy,
                            frame: frame,
                            geo: geo,
                            selectedDay: selDay,
                            mode: mode
                        )
                    }
                }
            }
        }
    }

    private func trendDragGesture(proxy: ChartProxy, frame: CGRect) -> some Gesture {
        // minimumDistance: 2 keeps tiny jitters from stealing the gesture,
        // and also makes a plain horizontal "swipe" by accident on the card
        // less likely to register a scrub — but still feels instant on press.
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let loc = value.location
                guard frame.contains(loc) else { return }
                let xInPlot = loc.x - frame.minX

                var newDay: Int?
                if let d: Int = proxy.value(atX: xInPlot) {
                    newDay = d
                } else if let d: Double = proxy.value(atX: xInPlot) {
                    newDay = Int(d.rounded())
                }

                if let newDay, newDay != trendSelectedDay {
                    trendSelectedDay = newDay
                    Haptics.selection()
                }
            }
            .onEnded { _ in
                trendSelectedDay = nil
            }
    }

    // MARK: - Shared axis modifier

    private struct TrendChartAxes: ViewModifier {
        func body(content: Content) -> some View {
            content
                .chartXAxis {
                    AxisMarks(values: .stride(by: 5)) { _ in
                        AxisGridLine().foregroundStyle(DS.Colors.grid.opacity(0.5))
                        AxisValueLabel()
                            .foregroundStyle(DS.Colors.subtext)
                            .font(DS.Typography.caption)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(DS.Colors.grid.opacity(0.5))
                        AxisTick().foregroundStyle(DS.Colors.grid)
                        AxisValueLabel {
                            if let vInt = value.as(Int.self) {
                                Text(DS.Format.money(vInt))
                                    .foregroundStyle(DS.Colors.subtext)
                                    .font(DS.Typography.caption)
                            } else if let v = value.as(Double.self) {
                                Text(DS.Format.money(Int(v.rounded())))
                                    .foregroundStyle(DS.Colors.subtext)
                                    .font(DS.Typography.caption)
                            }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private func trendTooltipView(
        proxy: ChartProxy,
        frame: CGRect,
        geo: GeometryProxy,
        selectedDay: Int,
        mode: TrendOverlayMode
    ) -> some View {
        let model = DashboardTrendModel(store: store, selectedMonth: store.selectedMonth)
        let points = model.dailyPoints
        let pace = model.idealPace
        let prev = model.prevMonthCumulative

        let nearest = points.min { a, b in
            abs(a.day - selectedDay) < abs(b.day - selectedDay)
        }

        if let p = nearest,
           let xPos = proxy.position(forX: p.day) {

            let yValue: Int = {
                switch mode {
                case .pace, .lastMonth: return p.cumulative
                case .daily: return p.spent
                }
            }()
            let yPos = proxy.position(forY: yValue) ?? 0
            let x = frame.minX + xPos
            let y = frame.minY + yPos

            Path { path in
                path.move(to: CGPoint(x: x, y: frame.minY))
                path.addLine(to: CGPoint(x: x, y: frame.maxY))
            }
            .stroke(DS.Colors.text.opacity(0.35), lineWidth: 1)

            Circle()
                .fill(DS.Colors.accent.opacity(0.25))
                .frame(width: 18, height: 18)
                .position(x: x, y: y)

            Circle()
                .fill(DS.Colors.accent)
                .frame(width: 7, height: 7)
                .position(x: x, y: y)

            cumulativeTooltipCard(
                point: p,
                mode: mode,
                paceTarget: pace.first(where: { $0.day == p.day })?.target,
                prevCumulative: prev.first(where: { $0.day == p.day })?.cumulative,
                x: x, y: y, geo: geo, frame: frame
            )
        }
    }

    @ViewBuilder
    private func cumulativeTooltipCard(
        point: DashboardTrendModel.DayPoint,
        mode: TrendOverlayMode,
        paceTarget: Int?,
        prevCumulative: Int?,
        x: CGFloat, y: CGFloat,
        geo: GeometryProxy, frame: CGRect
    ) -> some View {
        let tooltipW: CGFloat = 180
        let pad: CGFloat = 10
        let tx = min(max(x + 14, pad + tooltipW / 2), geo.size.width - pad - tooltipW / 2)
        let ty = max(frame.minY + 12, y - 58)

        VStack(alignment: .leading, spacing: 5) {
            Text(dateString(forDay: point.day))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
                .textCase(.uppercase)
                .kerning(0.4)

            switch mode {
            case .pace:
                tooltipRow(label: "Cumulative", value: point.cumulative, big: true)
                tooltipRow(label: "Day's spend", value: point.spent, big: false)
                if let paceTarget {
                    let delta = point.cumulative - paceTarget
                    HStack(spacing: 4) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(delta >= 0
                             ? "over pace by \(delta.currencyFormatted(showDecimal: false))"
                             : "under pace by \(abs(delta).currencyFormatted(showDecimal: false))")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(delta > 0 ? DS.Colors.danger : DS.Colors.positive)
                }

            case .lastMonth:
                tooltipRow(label: "This month", value: point.cumulative, big: true)
                if let prevCumulative {
                    tooltipRow(label: "Last month", value: prevCumulative, big: false)
                    let delta = point.cumulative - prevCumulative
                    HStack(spacing: 4) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(delta >= 0
                             ? "+\(delta.currencyFormatted(showDecimal: false)) vs last"
                             : "\(delta.currencyFormatted(showDecimal: false)) vs last")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(delta > 0 ? DS.Colors.danger : DS.Colors.positive)
                }

            case .daily:
                tooltipRow(label: "Day's spend", value: point.spent, big: true)
                tooltipRow(label: "Cumulative", value: point.cumulative, big: false)
                if point.isAnomaly {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("unusually high")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(DS.Colors.danger)
                }
            }
        }
        .padding(10)
        .frame(width: tooltipW, alignment: .leading)
        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .position(x: tx, y: ty)
    }

    private func tooltipRow(label: String, value: Int, big: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: big ? 11 : 10, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
            Spacer()
            Text(value.currencyFormatted(showDecimal: false))
                .font(.system(size: big ? 13 : 11, weight: big ? .bold : .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
        }
    }

    // MARK: - Category Card

    private var categoryCard: some View {
        let breakdown = Analytics.categoryBreakdown(store: store)
        let monthTx = Analytics.monthTransactions(store: store)

        // Build a spent map so we can show category caps even if a category isn't in top breakdown.
        var spentByCategory: [Category: Int] = [:]
        for t in monthTx { spentByCategory[t.category, default: 0] += t.amount }

        // Rows to show under the chart:
        let topCats: [Category] = breakdown.prefix(6).map { $0.category }
        let cappedCats: [Category] = store.allCategories.filter { store.categoryBudget(for: $0) > 0 }
        let orderedCats: [Category] = Array(NSOrderedSet(array: topCats + cappedCats))
            .compactMap { $0 as? Category }

        return DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                    Text("Category Breakdown")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    Button { goToBudget() } label: {
                        HStack(spacing: 2) {
                            Text("Budget")
                                .font(DS.Typography.caption)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(DS.Colors.subtext)
                    }
                }

                if breakdown.isEmpty {
                    Text("No transactions yet")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                        .padding(.vertical, 6)
                } else {
                    Chart(breakdown) { row in
                        BarMark(
                            x: .value("Amount", row.total),
                            y: .value("Category", row.category.title)
                        )
                        .cornerRadius(6)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DS.Colors.accent, DS.Colors.accent.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(DS.Colors.grid)
                            AxisValueLabel().foregroundStyle(DS.Colors.subtext)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisValueLabel().foregroundStyle(DS.Colors.subtext)
                        }
                    }
                    .frame(height: CGFloat(breakdown.count) * 32 + 50)

                    Divider().foregroundStyle(DS.Colors.grid)

                    // Category caps — horizontal scroll for space efficiency
                    if !orderedCats.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(orderedCats, id: \.self) { c in
                                    let spent = spentByCategory[c] ?? 0
                                    let cap = store.categoryBudget(for: c)

                                    if cap > 0 {
                                        CategoryCapChip(category: c, spent: spent, cap: cap)
                                    } else if spent > 0 {
                                        CategorySpentChip(category: c, spent: spent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Category Chips (compact horizontal items)

    private struct CategoryCapChip: View {
        let category: Category
        let spent: Int
        let cap: Int

        private var ratio: Double { cap > 0 ? min(1.0, Double(spent) / Double(cap)) : 0 }
        private var isOver: Bool { spent > cap }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: category.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(category.tint)
                    Text(category.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                        .lineLimit(1)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.Colors.surface2).frame(height: 4)
                        Capsule()
                            .fill(isOver ? DS.Colors.danger : DS.Colors.accent)
                            .frame(width: geo.size.width * ratio, height: 4)
                    }
                }
                .frame(height: 4)

                Text("\(DS.Format.money(spent)) / \(DS.Format.money(cap))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(isOver ? DS.Colors.danger : DS.Colors.subtext)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(width: 140)
            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private struct CategorySpentChip: View {
        let category: Category
        let spent: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: category.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(category.tint)
                    Text(category.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                        .lineLimit(1)
                }

                Text(DS.Format.money(spent))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
            }
            .padding(10)
            .frame(width: 120)
            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Payment Breakdown (Horizontal Scroll)

    private var paymentBreakdownCard: some View {
        let breakdown = Analytics.paymentBreakdown(store: store)
        let total = breakdown.reduce(0) { $0 + $1.total }

        return DS.Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Payment Breakdown")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    Text("Cash vs Card")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                }

                if breakdown.isEmpty {
                    Text("No payment data")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                        .padding(.vertical, 6)
                } else if breakdown.count == 1, let only = breakdown.first {
                    // Single method — render full-width summary, no scroll
                    PaymentMethodRow(item: only)

                    Divider().foregroundStyle(DS.Colors.grid)

                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hexValue: 0xFFD93D))
                        Text(only.method == .cash
                             ? "All spending is in cash this month"
                             : only.method == .card
                                ? "All spending is on card this month"
                                : "Only one payment method used this month")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hexValue: 0xFFD93D).opacity(0.1))
                    )
                } else {
                    // Horizontal scroll for payment methods
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(breakdown) { item in
                                PaymentMethodChip(item: item)
                            }
                        }
                    }

                    Divider().foregroundStyle(DS.Colors.grid)

                    // Insights
                    if let cashItem = breakdown.first(where: { $0.method == .cash }),
                       let cardItem = breakdown.first(where: { $0.method == .card }) {

                        let cashPercent = Int(cashItem.percentage * 100)
                        let cardPercent = Int(cardItem.percentage * 100)

                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hexValue: 0xFFD93D))

                            if cashPercent > 70 {
                                Text("You use cash a lot")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                            } else if cardPercent > 70 {
                                Text("You prefer card payments")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                            } else {
                                Text("Balanced payment methods")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hexValue: 0xFFD93D).opacity(0.1))
                        )
                    }
                }
            }
        }
    }

    // MARK: - Payment Method Row (single-method full-width)

    private struct PaymentMethodRow: View {
        let item: Analytics.PaymentBreakdown

        @Environment(\.colorScheme) private var colorScheme

        private var methodColor: Color {
            switch item.method {
            case .card:   return DS.Colors.accent
            case .cash:   return DS.Colors.positive
            default:      return DS.Colors.warning
            }
        }

        var body: some View {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(methodColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: item.method.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(methodColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.method.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.text)
                    Text("\(Int(item.percentage * 100))% of spending")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                }

                Spacer()

                Text(DS.Format.money(item.total))
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(DS.Colors.text)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(methodColor.opacity(colorScheme == .dark ? 0.2 : 0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - Payment Method Chip

    private struct PaymentMethodChip: View {
        let item: Analytics.PaymentBreakdown

        @Environment(\.colorScheme) private var colorScheme

        private var methodColor: Color {
            switch item.method {
            case .card:   return DS.Colors.accent
            case .cash:   return DS.Colors.positive
            default:      return DS.Colors.warning
            }
        }

        var body: some View {
            VStack(spacing: 8) {
                // Icon box
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(methodColor.opacity(0.15))
                        .frame(width: 52, height: 52)
                    VStack(spacing: 2) {
                        Image(systemName: item.method.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(methodColor)
                        Text("\(Int(item.percentage * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(methodColor)
                    }
                }

                Text(item.method.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)

                Text(DS.Format.money(item.total))
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(DS.Colors.text)
            }
            .padding(14)
            .frame(width: 140)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(methodColor.opacity(colorScheme == .dark ? 0.2 : 0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - Advisor Insights

    private var advisorInsightsCard: some View {
        let insights = Analytics.generateInsights(store: store).prefix(5)
        return DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                        Text("Advisor Insights")
                            .font(DS.Typography.section)
                            .foregroundStyle(DS.Colors.text)
                    }
                    Spacer()
                    Text("We're here to help, not judge")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                }

                if insights.isEmpty {
                    Text("Add your expenses to get started")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(insights)) { insight in
                            InsightRow(insight: insight)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Copilot Data

    private func computeCopilotData() {
        let cal = Calendar.current
        let y = cal.component(.year, from: store.selectedMonth)
        let m = cal.component(.month, from: store.selectedMonth)
        let monthKey = String(format: "%04d-%02d", y, m)

        let forecast = ForecastEngine.shared.forecast
        let reviewSnap = ReviewEngine.shared.dashboardSnapshot
        let subSnap = SubscriptionEngine.shared.dashboardSnapshot
        let uid = authManager.currentUser?.uid ?? ""
        let householdSnap: HouseholdSnapshot? = uid.isEmpty ? nil : HouseholdManager.shared.dashboardSnapshot(
            monthKey: monthKey, currentUserId: uid
        )

        healthScore = HealthScoreEngine.compute(
            store: store,
            forecast: forecast,
            reviewSnapshot: reviewSnap,
            subscriptionSnapshot: subSnap,
            householdSnapshot: householdSnap,
            goalManager: GoalManager.shared
        )

        actionCards = ActionCardEngine.generate(
            store: store,
            forecast: forecast,
            reviewSnapshot: reviewSnap,
            subscriptionSnapshot: subSnap,
            householdSnapshot: householdSnap,
            goalManager: GoalManager.shared
        )
    }
}

// MARK: - Setup Card

private struct SetupCard: View {
    let goToBudget: () -> Void

    var body: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Set Your Budget")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                Text("Start by setting a monthly budget")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.subtext)

                Button {
                    goToBudget()
                } label: {
                    HStack {
                        Image(systemName: "target")
                        Text("Go to Budget")
                    }
                }
                .buttonStyle(DS.PrimaryButton())
            }
        }
    }
}
