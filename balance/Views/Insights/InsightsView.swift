import SwiftUI
import UserNotifications

// MARK: - Insights

struct InsightsView: View {
    @Binding var store: Store
    let goToBudget: () -> Void
    @State private var showAdvancedCharts: Bool = false
    @State private var showPaywall = false
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    @AppStorage("notifications.enabled") private var notificationsEnabled: Bool = false
    @State private var notifDetail: String? = nil

    @State private var shareURL: URL? = nil
    @State private var showReportExport = false
    @State private var showAIChat = false
    @StateObject private var insightEngine = AIInsightEngine.shared

    private struct TrendPoint: Identifiable {
        let id: Int          // day of month
        let euros: Double
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if store.budgetTotal <= 0 {
                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Insights Not Ready")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)

                                Text("Set your budget first")
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Colors.subtext)

                                Button { goToBudget() } label: {
                                    HStack {
                                        Image(systemName: "target")
                                        Text("Set Budget")
                                    }
                                }
                                .buttonStyle(DS.PrimaryButton())
                            }
                        }
                    } else {
                        // AI Financial Advisor
                        if !insightEngine.insights.isEmpty {
                            DS.Card {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(DS.Colors.accent)
                                        Text("AI Insights")
                                            .font(DS.Typography.section)
                                            .foregroundStyle(DS.Colors.text)
                                        Spacer()
                                        Button { showAIChat = true } label: {
                                            Text("Ask AI")
                                                .font(DS.Typography.caption)
                                                .foregroundStyle(DS.Colors.accent)
                                        }
                                    }

                                    ForEach(insightEngine.insights.prefix(5)) { insight in
                                        AIInsightBanner(insight: insight) { action in
                                            showAIChat = true
                                        }
                                    }
                                }
                            }
                        }

                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Analytical Report")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)

                                let proj = Analytics.projectedEndOfMonth(store: store)
                                let title =
                                    proj.level == .risk
                                    ? "This trend will pressure your budget"
                                    : "Approaching the limit"

                                let detail =
                                    proj.level == .risk
                                    ? "End-of-month projection is above budget. Prioritize cutting discretionary costs."
                                    : "To stay in control, trim one discretionary category slightly."

                                DS.StatusLine(
                                    title: title,
                                    detail: detail,
                                    level: proj.level
                                )
                                Text("Based on current spending")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                        }

                        let insights = Analytics.generateInsights(store: store)
                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Insights")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)

                                if insights.isEmpty {
                                    Text("Not enough data")
                                        .font(DS.Typography.body)
                                        .foregroundStyle(DS.Colors.subtext)
                                        .padding(.vertical, 6)
                                } else {
                                    VStack(spacing: 10) {
                                        ForEach(insights) { insight in
                                            InsightRow(insight: insight)
                                        }
                                    }
                                }
                            }
                        }

                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Notifications")
                                        .font(DS.Typography.section)
                                        .foregroundStyle(DS.Colors.text)
                                    Spacer()
                                    Toggle("", isOn: $notificationsEnabled)
                                        .labelsHidden()
                                        .toggleStyle(SwitchToggleStyle(tint: DS.Colors.accent))
                                }

                                Text("Get alerts about your spending")
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Colors.subtext)

                                if let notifDetail {
                                    DS.StatusLine(
                                        title: "Notification status",
                                        detail: notifDetail,
                                        level: notificationsEnabled ? .ok : .watch
                                    )
                                }

                                Button {
                                    Task { await sendTestNotification() }
                                } label: {
                                    HStack {
                                        Image(systemName: "bell.badge")
                                        Text("Send Test")
                                    }
                                }
                                .buttonStyle(DS.PrimaryButton())
                                .disabled(!notificationsEnabled)

                                Text("Make sure notifications work")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                        }



                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Export")
                                        .font(DS.Typography.section)
                                        .foregroundStyle(DS.Colors.text)
                                    Spacer()
                                    Text("Share or save")
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                }

                                Text("Export your data")
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Colors.subtext)

                                HStack(spacing: 10) {
                                    Button {
                                        guard subscriptionManager.isPro else {
                                            return
                                        }
                                        Haptics.medium()
                                        exportMonth(format: .excel)
                                    } label: {
                                        HStack {
                                            Image(systemName: "tablecells")
                                            Text("Export Excel")
                                        }
                                    }
                                    .buttonStyle(DS.PrimaryButton())

                                    Button {
                                        guard subscriptionManager.isPro else {
                                            return
                                        }
                                        Haptics.medium()
                                        exportMonth(format: .csv)
                                    } label: {
                                        HStack {
                                            Image(systemName: "doc.plaintext")
                                            Text("Export CSV")
                                        }
                                    }
                                    .buttonStyle(DS.PrimaryButton())
                                }

                                Button {
                                    guard subscriptionManager.isPro else {
                                        return
                                    }
                                    Haptics.medium()
                                    showReportExport = true
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.richtext")
                                        Text("Export PDF Report")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(DS.PrimaryButton())

                                Text("Choose format")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                        }
                        .overlay(alignment: .center) {
                            if !subscriptionManager.isPro {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(.ultraThinMaterial)

                                    VStack(spacing: 8) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 28))
                                            .foregroundStyle(DS.Colors.subtext)

                                        Text("export reports")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(DS.Colors.text)

                                        Text("pro user access only")
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(DS.Colors.subtext)
                                    }
                                }
                            }
                        }
                        .zIndex(1)


                        // Advanced Charts
                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "chart.xyaxis.line")
                                        .font(.system(size: 18))
                                        .foregroundStyle(DS.Colors.accent)

                                    Text("Charts")
                                        .font(DS.Typography.section)
                                        .foregroundStyle(DS.Colors.text)
                                }

                                Text("View spending trends, category distribution, and monthly comparisons")
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Colors.subtext)

                                Button {
                                    guard subscriptionManager.isPro else {
                                        return
                                    }
                                    Haptics.light()
                                    showAdvancedCharts = true
                                } label: {
                                    HStack {
                                        Image(systemName: "chart.bar.xaxis")
                                        Text("View Advanced Charts")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(DS.PrimaryButton())
                            }
                        }
                        .overlay(alignment: .center) {
                            if !subscriptionManager.isPro {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(.ultraThinMaterial)

                                    VStack(spacing: 8) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 28))
                                            .foregroundStyle(DS.Colors.subtext)

                                        Text("advanced charts")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(DS.Colors.text)

                                        Text("pro user access only")
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(DS.Colors.subtext)
                                    }
                                }
                            }
                        }
                        .zIndex(1)


                        // Professional Analysis Website
                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "globe.badge.chevron.backward")
                                        .font(.system(size: 20))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [DS.Colors.accent, DS.Colors.accent.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )

                                    Text("Professional Analysis")
                                        .font(DS.Typography.section)
                                        .foregroundStyle(DS.Colors.text)

                                    Spacer()

                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .font(.system(size: 16))
                                        .foregroundStyle(DS.Colors.subtext)
                                }

                                Text("Deep dive into your financial data with advanced analytics and professional reports")
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Colors.subtext)
                                    .fixedSize(horizontal: false, vertical: true)

                                // Features
                                VStack(alignment: .leading, spacing: 8) {
                                    FeatureBullet(icon: "chart.bar.doc.horizontal", text: "Comprehensive Reports")
                                    FeatureBullet(icon: "calendar.badge.clock", text: "Historical Trends")
                                    FeatureBullet(icon: "arrow.triangle.branch", text: "Spending Patterns")
                                    FeatureBullet(icon: "lightbulb.max", text: "Smart Recommendations")
                                }
                                .padding(.vertical, 6)

                                Button {
                                    Haptics.light()
                                    if let url = URL(string: "https://centmond.com") {
                                        // ← لینک رو بعداً عوض می‌کنی
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "arrow.up.forward.square")
                                        Text("Open Analysis Dashboard")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(DS.PrimaryButton())
                            }
                        }


                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Quick Actions")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)

                                let actions = Analytics.quickActions(store: store)
                                if actions.isEmpty {
                                    Text("All good!")
                                        .font(DS.Typography.body)
                                        .foregroundStyle(DS.Colors.subtext)
                                        .padding(.vertical, 6)
                                } else {
                                    VStack(spacing: 10) {
                                        ForEach(actions, id: \.self) { a in
                                            HStack(alignment: .top, spacing: 10) {
                                                Image(systemName: "checkmark.seal")
                                                    .foregroundStyle(DS.Colors.text)
                                                Text(a)
                                                    .font(DS.Typography.body)
                                                    .foregroundStyle(DS.Colors.text)
                                                Spacer(minLength: 0)
                                            }
                                            .padding(12)
                                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        }
                                    }
                                }
                            }
                        }

                        // ✅ Recurring Transactions Card
                        // RecurringTransactionsCard(store: $store)  // ← COMMENTED OUT - فعلاً نیاز نیست
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .navigationTitle("Insights")
            .onChange(of: notificationsEnabled) { _, newVal in
                if newVal {
                    Task { try? await Task.sleep(nanoseconds: 100_000_000);
                        await requestNotificationPermissionIfNeeded()
                        // Once permission is granted, schedule recurring reminders and evaluate rules.
                        await Notifications.syncAll(store: store)
                    }
                } else {
                    // Turning off only disables in-app usage; iOS-level permission stays in Settings.
                    notifDetail = "Notifications are turned off in the app."
                    Notifications.cancelAll()
                }
            }
            .onAppear {
                // Allow notifications to show even when the app is open (foreground).
                UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared

                if notificationsEnabled {
                    Task { try? await Task.sleep(nanoseconds: 100_000_000);
                        // Keep schedules fresh when returning to this screen.
                        await Notifications.syncAll(store: store)
                    }
                }

                insightEngine.refresh(store: store)
            }
            .onChange(of: store) { _, _ in
                // Re-evaluate smart rules as data changes (budget/transactions/etc.).
                guard notificationsEnabled else { return }
                Task { await Notifications.evaluateSmartRules(store: store) }
            }

            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showAdvancedCharts) {
                AdvancedChartsView(store: $store)
            }
            .sheet(isPresented: $showReportExport) {
                ReportExportView(store: $store)
            }
            .sheet(isPresented: $showPaywall) {
            }
            .sheet(isPresented: $showAIChat) {
                AIChatView(store: $store)
            }
        }
    }


    private func requestNotificationPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            await MainActor.run {
                notifDetail = "Enabled. You can send a test notification now."
            }
            await Notifications.syncAll(store: store)
        case .denied:
            await MainActor.run {
                notificationsEnabled = false
                notifDetail = "Notifications are blocked in iOS Settings for this app. Enable them in Settings → Notifications."
            }
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                await MainActor.run {
                    if granted {
                        notifDetail = "Permission granted. Tap 'Send test notification'."
                    } else {
                        notificationsEnabled = false
                        notifDetail = "Permission not granted. Toggle stayed off."
                    }
                }
                if granted {
                    await Notifications.syncAll(store: store)
                }
            } catch {
                await MainActor.run {
                    notificationsEnabled = false
                    notifDetail = AppConfig.shared.safeErrorMessage(
                        detail: "Couldn't request permission: \(error.localizedDescription)",
                        fallback: "Couldn't request notification permission."
                    )
                }
            }
        @unknown default:
            await MainActor.run {
                notifDetail = "Unknown notification status."
            }
        }
    }

    private func sendTestNotification() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        guard notificationsEnabled else {
            await MainActor.run { notifDetail = "Turn notifications on first." }
            return
        }

        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else {
            await MainActor.run {
                notificationsEnabled = false
                notifDetail = "Notifications are not authorized. Please enable them in iOS Settings."
            }
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: ["balance.test.notification"])

        let content = UNMutableNotificationContent()
        content.title = "Centmond — Test"
        content.body = "This is a test notification. If you see this, notifications are working."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let req = UNNotificationRequest(identifier: "balance.test.notification", content: content, trigger: trigger)

        do {
            try await center.add(req)
            await MainActor.run {
                notifDetail = "Test notification scheduled (in ~3 seconds)."
            }
        } catch {
            await MainActor.run {
                notifDetail = AppConfig.shared.safeErrorMessage(
                    detail: "Failed to schedule notification: \(error.localizedDescription)",
                    fallback: "Failed to schedule notification."
                )
            }
        }
    }

    private enum ExportFormat {
        case csv
        case excel
        case pdf  // ← جدید

        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .excel: return "xlsx"
            case .pdf: return "pdf"
            }
        }
    }

    private func exportMonth(format: ExportFormat) {
        let summary = Analytics.monthSummary(store: store)
        let tx = Analytics.monthTransactions(store: store)
        let dailyPoints = Analytics.dailySpendPoints(store: store)
        let cats = Analytics.categoryBreakdown(store: store)

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: store.selectedMonth)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let monthKey = String(format: "%04d-%02d", y, m)

        let filename = "Centmond_\(monthKey).\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            let data: Data
            switch format {
            case .csv:
                let csv = Exporter.makeCSV(
                    monthKey: monthKey,
                    currency: "EUR",
                    budgetCents: store.budgetTotal,
                    summary: summary,
                    transactions: tx,
                    categories: cats,
                    daily: dailyPoints
                )
                data = csv.data(using: String.Encoding.utf8) ?? Data()
            case .excel:
                let caps: [Category: Int] = Dictionary(uniqueKeysWithValues: store.allCategories.map { ($0, store.categoryBudget(for: $0)) })
                data = Exporter.makeXLSX(
                    monthKey: monthKey,
                    currency: "EUR",
                    budgetCents: store.budgetTotal,
                    categoryCapsCents: caps,
                    summary: summary,
                    transactions: tx,
                    categories: cats,
                    daily: dailyPoints
                )
            case .pdf:
                // Generate real monthly PDF report
                let cal = Calendar.current
                let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: store.selectedMonth))!
                let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart)!
                data = PDFReportGenerator.generate(
                    type: .monthlySummary,
                    store: store,
                    startDate: monthStart,
                    endDate: monthEnd
                )
            }

            try data.write(to: url, options: .atomic)
            Haptics.exportSuccess()
            AnalyticsManager.shared.track(.exportUsed(format: format.fileExtension))
            self.shareURL = url
        } catch {
            Haptics.error()  // ← هاپتیک خطا
            self.notifDetail = AppConfig.shared.safeErrorMessage(
                detail: "Export failed: \(error.localizedDescription)",
                fallback: "Export failed. Please try again."
            )
        }
    }
}

// MARK: - Helper Views

private struct FeatureBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Colors.accent)
                .frame(width: 16)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(DS.Colors.subtext)
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
