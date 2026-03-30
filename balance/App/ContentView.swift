import SwiftUI
import Combine
import UIKit
import UserNotifications

// MARK: - Root // 22

struct ContentView: View {
    @State private var store: Store = Store()
    @State private var autoSyncTask: Task<Void, Never>? = nil
    @State private var showSaveFailedAlert = false
    @State private var showSyncErrorToast = false
    @State private var syncErrorMessage = ""
    @State private var showCorruptDataAlert = false
    @State private var selectedTab: Tab = .dashboard
    @State private var showLaunchScreen = true
    @AppStorage("app.theme") private var selectedTheme: String = "light"
    @State private var uiRefreshID = UUID()
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var supabaseManager: SupabaseManager
    @EnvironmentObject private var appLockManager: AppLockManager
    @StateObject private var onboardingManager = OnboardingManager.shared
    @StateObject private var syncCoordinator = SyncCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase

    // Debounced smart-rule evaluation to prevent repeated scheduling/firing
    @State private var notifEvalWorkItem: DispatchWorkItem? = nil
    @State private var didSyncNotifications: Bool = false

    @AppStorage("notifications.enabled")
    private var notificationsEnabled: Bool = false

    private let notifEvalDebounceSeconds: TimeInterval = 0.9
    
    // MARK: - Helper Functions
    
    /// Load user data from local storage, then sync from cloud in background.
    /// Local data is loaded synchronously (fast) for instant UI.
    /// Cloud sync follows asynchronously — on success, updates both local and in-memory state.
    private func loadUserData() {
        guard let userId = authManager.currentUser?.uid else {
            SecureLogger.warning("loadUserData: No user ID found")
            return
        }

        // Load ancillary data
        Task { await SubscriptionManager.shared.loadSubscription() }
        HouseholdManager.shared.load(userId: userId)

        // 1. Load from local storage FIRST (fast, never fails)
        store = Store.load(userId: userId)
        store.purgeStaleCustomCategoryBudgetKeys()
        if Store.didLoadCorruptData {
            showCorruptDataAlert = true
        }
        SecureLogger.info("Local data loaded: \(store.transactions.count) transactions")

        // 2. Sync from cloud in background
        Task {
            if var cloudStore = await syncCoordinator.pullFromCloud(localStore: store, userId: userId) {
                cloudStore.purgeStaleCustomCategoryBudgetKeys()
                store = cloudStore
                store.save(userId: userId)
                SecureLogger.info("Launch sync complete")
            }
        }

        // 3. Start periodic sync via coordinator
        syncCoordinator.startPeriodicSync(
            getStore: { [self] in self.store },
            setStore: { [self] newStore in self.store = newStore },
            getUserId: { [self] in self.authManager.currentUser?.uid }
        )
    }

    /// Manual sync triggered by user — does full push + pull reconciliation.
    @MainActor
    private func manualSync() async {
        guard let userId = authManager.currentUser?.uid else {
            SecureLogger.warning("manualSync: No user ID found")
            return
        }

        if let reconciled = await syncCoordinator.fullReconcile(store: store, userId: userId) {
            store = reconciled
            store.save(userId: userId)
            Haptics.success()
        } else {
            Haptics.error()
        }
    }

    /// Save store to local only (UserDefaults).
    private func saveStore() {
        guard let userId = authManager.currentUser?.uid else { return }
        if !store.save(userId: userId) {
            showSaveFailedAlert = true
        }
    }
    

    var body: some View {
            Group {
                if authManager.isAuthenticated {
                    // User is logged in - show main app
                    ZStack {
                        if showLaunchScreen {
                            LaunchScreenView {
                                showLaunchScreen = false
                            }
                            .transition(.opacity)
                        } else if !onboardingManager.hasCompletedOnboarding && !onboardingManager.showOnboarding {
                            // ✅ Welcome screen
                            WelcomeView(onboardingManager: onboardingManager)
                                .transition(.opacity)
                        } else if onboardingManager.showOnboarding {
                            // ✅ Tutorial کارتی
                            SimpleTutorialView(onboardingManager: onboardingManager)
                                .transition(.opacity)
                        } else {
                            mainAppView
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.4), value: showLaunchScreen)
                    .animation(.easeInOut(duration: 0.4), value: onboardingManager.hasCompletedOnboarding)
                    .animation(.easeInOut(duration: 0.4), value: onboardingManager.showOnboarding)
                    .onAppear {
                        // Load data when app appears (app startup)
                        loadUserData()
                        AnalyticsManager.shared.startSession()
                    }
                } else {
                    // User not logged in - show authentication
                    AuthenticationView()
                        .environmentObject(authManager)
                }
            }
            .onChange(of: authManager.currentUser?.uid) { oldValue, newValue in
                // When user changes (login/logout/switch), load their data
                if newValue != nil {
                    // User logged in - load their data
                    loadUserData()
                } else {
                    // User logged out - clear data and stop sync
                    syncCoordinator.stopPeriodicSync()
                    store = Store()
                }
            }
            .overlay {
                // ✅ Interactive Tutorial Overlay
            }
            .preferredColorScheme(selectedTheme == "dark" ? .dark : selectedTheme == "light" ? .light : nil)
        }
        
        private var mainAppView: some View {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    EmailVerificationBanner()
                    
                    TabView(selection: $selectedTab) {
                        DashboardView(store: $store, goToBudget: { selectedTab = .budget }, goToTransactions: { selectedTab = .transactions })
                            .tabItem { Label("Home", systemImage: "gauge.with.dots.needle.50percent") }
                            .tag(Tab.dashboard)

                        TransactionsView(store: $store, goToBudget: { selectedTab = .budget })
                            .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
                            .tag(Tab.transactions)

                        BudgetView(store: $store)
                            .tabItem { Label("Budget", systemImage: "target") }
                            .tag(Tab.budget)

                        InsightsView(store: $store, goToBudget: { selectedTab = .budget })
                            .tabItem { Label("Insights", systemImage: "sparkles") }
                            .tag(Tab.insights)

                        MoreView(store: $store, selectedTab: $selectedTab)
                            .tabItem { Label("More", systemImage: "ellipsis.circle") }
                            .tag(Tab.more)
                    }
                    .environmentObject(supabaseManager)
            .onChange(of: selectedTab) { _, newTab in
                Haptics.selection()
                AnalyticsManager.shared.track(.tabSwitched(tab: "\(newTab)"))
            }
            } // Close VStack
            .onAppear {
                // اجازه بده نوتیف‌ها داخل برنامه هم بنر بشن
                UNUserNotificationCenter.current().delegate =
                    NotificationCenterDelegate.shared

                // اگر قبلاً نوتیف روشن بوده، ruleها فعال باشن
                // (فقط یکبار در هر اجرای برنامه سینک کن تا نوتیف تکراری ساخته نشه)
                if notificationsEnabled && !didSyncNotifications {
                    didSyncNotifications = true
                    Task { try? await Task.sleep(nanoseconds: 100_000_000);
                        await Notifications.syncAll(store: store)
                    }
                }
            }
            .onChange(of: store) { _, newStore in
                // هر تغییری در store (اضافه/ادیت/حذف ترنزکشن)
                // ruleها رو با debounce بررسی کن تا نوتیف تکراری ساخته/فایر نشه
                if notificationsEnabled {
                    notifEvalWorkItem?.cancel()
                    let item = DispatchWorkItem {
                        Task { try? await Task.sleep(nanoseconds: 100_000_000);
                            await Notifications.evaluateSmartRules(store: newStore)
                        }
                    }
                    notifEvalWorkItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + notifEvalDebounceSeconds, execute: item)
                }

                // Regenerate engines in parallel for fast month switching
                Task {
                    async let f: () = ForecastEngine.shared.generate(store: newStore)
                    async let s: () = SubscriptionEngine.shared.analyze(store: newStore)
                    async let r: () = ReviewEngine.shared.analyze(store: newStore)
                    _ = await (f, s, r)
                    // Update widget data after engines finish
                    await WidgetDataWriter.update(store: newStore)
                }
            }
            // Save locally when the app is backgrounded
            .onChange(of: scenePhase) { _, phase in
                if phase == .inactive || phase == .background {
                    saveStore()
                    AnalyticsManager.shared.endSession()
                    Task { await WidgetDataWriter.update(store: store) }
                    appLockManager.lockIfEnabled()
                } else if phase == .active {
                    AnalyticsManager.shared.startSession()
                }
            }
            .overlay {
                if appLockManager.isLocked {
                    LockScreenView()
                        .transition(.opacity)
                }
            }
            // Handle widget deep links
            .onOpenURL { url in
                guard url.scheme == "centmond" else { return }
                switch url.host {
                case "dashboard":       selectedTab = .dashboard
                case "budget":          selectedTab = .budget
                case "subscriptions":   selectedTab = .more
                case "forecast":        selectedTab = .insights
                case "accounts":        selectedTab = .more
                default: break
                }
            }
            // Cascade: nil out accountId on transactions when an account is deleted
            .onReceive(NotificationCenter.default.publisher(for: .accountDidDelete)) { notification in
                if let accountId = notification.userInfo?["accountId"] as? UUID {
                    let result = TransactionService.didDeleteAccount(accountId, store: &store)
                    if case .localSaveFailed = result {
                        SecureLogger.warning("Cascading cleanup after account delete failed to persist")
                    }
                }
            }
            // Cascade: nil out linkedGoalId on transactions when a goal is deleted
            .onReceive(NotificationCenter.default.publisher(for: .goalDidDelete)) { notification in
                if let goalId = notification.userInfo?["goalId"] as? UUID {
                    let result = TransactionService.didDeleteGoal(goalId, store: &store)
                    if case .localSaveFailed = result {
                        SecureLogger.warning("Cascading cleanup after goal delete failed to persist")
                    }
                }
            }
            // SAFETY NET save + cloud sync trigger on ANY store mutation.
            //
            // Persistence ownership:
            // - Transaction mutations (add/edit/delete/undo/bulk/clear/cascade):
            //   PRIMARY save is in TransactionService.persist(). This onChange fires
            //   as a secondary save — harmless (idempotent UserDefaults overwrite).
            // - Non-transaction mutations (budget edits, selectedMonth, categories):
            //   This onChange is the ONLY save. Do NOT remove it.
            .onChange(of: store) { _, newStore in
                // Save locally IMMEDIATELY (not debounced) so budget/data never gets lost
                if let userId = authManager.currentUser?.uid {
                    if !newStore.save(userId: userId) {
                        showSaveFailedAlert = true
                    }
                }

                // Cloud sync is debounced to avoid spamming the server
                autoSyncTask?.cancel()
                autoSyncTask = Task {
                    // Debounce: wait 2 seconds before syncing to cloud
                    try? await Task.sleep(nanoseconds: 2_000_000_000)

                    guard !Task.isCancelled else { return }
                    guard let userId = authManager.currentUser?.uid else {
                        SecureLogger.debug("No user ID — skipping auto-sync")
                        return
                    }

                    // Push to cloud via SyncCoordinator
                    if let cleaned = await syncCoordinator.pushToCloud(store: newStore, userId: userId) {
                        // If deletedTransactionIds were cleared, update local store
                        if cleaned.deletedTransactionIds != newStore.deletedTransactionIds {
                            store = cleaned
                            cleaned.save(userId: userId)
                        }
                    }
                }
            }
            .tint(DS.Colors.accent)
            .id(uiRefreshID)
            .alert("Save Failed", isPresented: $showSaveFailedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your changes could not be saved locally. Please try again or restart the app.")
            }
            .onChange(of: syncCoordinator.status) { _, newStatus in
                if case .error(let message) = newStatus {
                    syncErrorMessage = message
                    showSyncErrorToast = true
                }
            }
            .alert("Sync Error", isPresented: $showSyncErrorToast) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(syncErrorMessage)
            }
            .alert("Data Recovery", isPresented: $showCorruptDataAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Local data could not be loaded. A backup has been saved. Your data will be restored from the cloud if available.")
            }
            .task(id: authManager.isAuthenticated) {
                if authManager.isAuthenticated, let userId = authManager.currentUser?.uid {
                    // Sync when user logs in via SyncCoordinator
                    if let cloudStore = await syncCoordinator.pullFromCloud(localStore: store, userId: userId) {
                        store = cloudStore
                        saveStore()
                    }

                    // Start real-time listener for auto-sync from other devices
                    supabaseManager.startRealtimeSync(userId: userId) {
                        SecureLogger.debug("Real-time sync triggered")
                    }
                } else {
                    // User logged out — stop listeners, periodic sync, and reset store
                    supabaseManager.stopRealtimeSync()
                    syncCoordinator.stopPeriodicSync()
                    store = Store()
                    showLaunchScreen = true
                }
            }
            .task {
                // COMMENTED OUT - recurring transactions باگ داره
                // if authManager.isAuthenticated {
                //     RecurringTransactionManager.processRecurringTransactions(store: &store)
                // }
            }
        }
    }
}




// MARK: - PDF Exporter

struct PDFExporter {
    static func makePDF(
        monthKey: String,
        currency: String,
        summary: Analytics.MonthSummary,
        transactions: [Transaction],
        categories: [Analytics.CategoryRow]
    ) -> Data {
        let pdfMetaData = [
            kCGPDFContextCreator: "Centmond App",
            kCGPDFContextAuthor: "Centmond",
            kCGPDFContextTitle: "Monthly Report - \(monthKey)"
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageWidth = 8.5 * 72.0
        let pageHeight = 11 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { context in
            context.beginPage()
            drawPage(context: context.cgContext, pageRect: pageRect, monthKey: monthKey, currency: currency, summary: summary, transactions: transactions, categories: categories)
        }
        
        return data
    }
    
    private static func drawPage(context: CGContext, pageRect: CGRect, monthKey: String, currency: String, summary: Analytics.MonthSummary, transactions: [Transaction], categories: [Analytics.CategoryRow]) {
        var y: CGFloat = 50
        let margin: CGFloat = 50
        let contentWidth = pageRect.width - (margin * 2)
        
        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 28, weight: .bold), .foregroundColor: UIColor.label]
        "Centmond - Monthly Report".draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
        y += 50
        
        // Month
        let monthAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: UIColor.secondaryLabel]
        monthKey.draw(at: CGPoint(x: margin, y: y), withAttributes: monthAttrs)
        y += 60
        
        // Summary cards
        let cardWidth = (contentWidth - 20) / 2
        let cardHeight: CGFloat = 80
        
        drawCard(context: context, rect: CGRect(x: margin, y: y, width: cardWidth, height: cardHeight), title: "Budget", value: formatMoney(summary.budgetCents, currency: currency), color: UIColor.systemBlue)
        drawCard(context: context, rect: CGRect(x: margin + cardWidth + 20, y: y, width: cardWidth, height: cardHeight), title: "Spent", value: formatMoney(summary.totalSpent, currency: currency), color: UIColor.systemRed)
        y += cardHeight + 15
        
        drawCard(context: context, rect: CGRect(x: margin, y: y, width: cardWidth, height: cardHeight), title: "Remaining", value: formatMoney(summary.remaining, currency: currency), color: summary.remaining >= 0 ? UIColor.systemGreen : UIColor.systemOrange)
        drawCard(context: context, rect: CGRect(x: margin + cardWidth + 20, y: y, width: cardWidth, height: cardHeight), title: "Daily Average", value: formatMoney(summary.dailyAvg, currency: currency), color: UIColor.systemPurple)
        y += cardHeight + 40
        
        // Categories
        let sectionAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 20, weight: .bold), .foregroundColor: UIColor.label]
        "Top Categories".draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
        y += 35
        
        let topCats = Array(categories.prefix(5))
        let maxVal = topCats.map { $0.total }.max() ?? 1
        
        for cat in topCats {
            let catAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: UIColor.label]
            cat.category.title.draw(at: CGPoint(x: margin, y: y + 8), withAttributes: catAttrs)
            
            let percentage = CGFloat(cat.total) / CGFloat(maxVal)
            let barWidth = (contentWidth - 140) * percentage
            let barRect = CGRect(x: margin + 110, y: y + 3, width: barWidth, height: 25)
            context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.3).cgColor)
            context.fill(barRect)
            
            let valAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: UIColor.label]
            formatMoney(cat.total, currency: currency).draw(at: CGPoint(x: barRect.maxX + 8, y: y + 8), withAttributes: valAttrs)
            
            y += 35
        }
        
        // Transactions section
        y += 20
        "Recent Transactions".draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
        y += 35
        
        let recentTx = Array(transactions.prefix(10))
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        
        for tx in recentTx {
            let txAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .regular), .foregroundColor: UIColor.label]
            dateFormatter.string(from: tx.date).draw(at: CGPoint(x: margin, y: y), withAttributes: txAttrs)
            tx.category.title.draw(at: CGPoint(x: margin + 70, y: y), withAttributes: txAttrs)
            
            let note = tx.note.isEmpty ? "—" : String(tx.note.prefix(15)) + (tx.note.count > 15 ? "..." : "")
            note.draw(at: CGPoint(x: margin + 170, y: y), withAttributes: txAttrs)
            
            let amountColor = tx.type == .income ? UIColor.systemGreen : UIColor.label
            let amtAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: amountColor]
            let prefix = tx.type == .expense ? "-" : "+"
            "\(prefix)\(formatMoney(tx.amount, currency: currency))".draw(at: CGPoint(x: margin + 320, y: y), withAttributes: amtAttrs)
            
            y += 28
        }
        
        // Footer
        y = pageRect.height - 50
        let footerAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9, weight: .regular), .foregroundColor: UIColor.secondaryLabel]
        let dateFormatter2 = DateFormatter()
        dateFormatter2.dateStyle = .long
        dateFormatter2.timeStyle = .short
        "Generated on \(dateFormatter2.string(from: Date())) • Centmond App".draw(at: CGPoint(x: margin, y: y), withAttributes: footerAttrs)
    }
    
    private static func drawCard(context: CGContext, rect: CGRect, title: String, value: String, color: UIColor) {
        context.setFillColor(color.withAlphaComponent(0.1).cgColor)
        context.fill(rect)
        context.setStrokeColor(color.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(2)
        context.stroke(rect)
        
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: UIColor.secondaryLabel]
        title.draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 12), withAttributes: titleAttrs)
        
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 20, weight: .bold), .foregroundColor: color]
        value.draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 38), withAttributes: valueAttrs)
    }
    
    private static func formatMoney(_ cents: Int, currency: String) -> String {
        let value = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale.current
        
        switch currency {
        case "EUR": formatter.currencySymbol = "€"
        case "USD": formatter.currencySymbol = "$"
        case "GBP": formatter.currencySymbol = "£"
        case "JPY": formatter.currencySymbol = "¥"
        case "CAD": formatter.currencySymbol = "C$"
        default: break
        }
        
        return formatter.string(from: NSNumber(value: value)) ?? "\(value) \(currency)"
    }
}


// MARK: - Launch Screen Animation

struct LaunchScreenView: View {
    @State private var titleScale: CGFloat = 0.7
    @State private var titleOpacity: Double = 0
    @State private var taglineOffset: CGFloat = 15
    @State private var taglineOpacity: Double = 0
    
    var onComplete: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 16) {
                Text("CENTMOND")
                    .font(.custom("Pacifico-Regular", size: 48))
                    .foregroundStyle(.white)
                    .scaleEffect(titleScale)
                    .opacity(titleOpacity)
                
                Text("SMART PERSONAL FINANCE")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.4))
                    .offset(y: taglineOffset)
                    .opacity(taglineOpacity)
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // Phase 1: Title fade in + scale up
        withAnimation(.easeOut(duration: 0.9)) {
            titleScale = 1.0
            titleOpacity = 1.0
        }
        
        // Phase 2: Tagline slides up
        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            taglineOffset = 0
            taglineOpacity = 1.0
        }
        
        // Phase 3: Hold then fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.4)) {
                titleOpacity = 0
                taglineOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onComplete()
            }
        }
    }
}




















