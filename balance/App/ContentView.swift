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
    @AppStorage("ai.onboarding.completed") private var hasCompletedAIOnboarding = false
    @StateObject private var syncCoordinator = SyncCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase

    // Debounced smart-rule evaluation to prevent repeated scheduling/firing
    @State private var notifEvalWorkItem: DispatchWorkItem? = nil
    @State private var didSyncNotifications: Bool = false

    @AppStorage("notifications.enabled")
    private var notificationsEnabled: Bool = false

    // AI
    @State private var showAIChat = false

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

        // Train AI systems from existing data
        AICategorySuggester.shared.learnFromHistory(store: store)
        AIUserPreferences.shared.learnFromTransactions(store: store)

        // Defense-in-depth: drop orphan split expenses left by prior bypass-delete bugs.
        HouseholdManager.shared.sweepOrphanSplitExpenses(
            knownTransactionIds: Set(store.transactions.map(\.id))
        )

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
                        } else if !hasCompletedAIOnboarding &&
                                  !onboardingManager.hasCompletedOnboarding {
                            // Phase 10: AI-native onboarding (replaces old welcome/tutorial)
                            AIOnboardingView(
                                store: $store,
                                userId: authManager.currentUser?.uid ?? "",
                                onComplete: {
                                    onboardingManager.completeOnboarding()
                                }
                            )
                            .transition(.opacity)
                        } else if !onboardingManager.hasCompletedOnboarding && !onboardingManager.showOnboarding {
                            // Fallback: old Welcome screen (shouldn't reach here normally)
                            WelcomeView(onboardingManager: onboardingManager)
                                .transition(.opacity)
                        } else if onboardingManager.showOnboarding {
                            // Tutorial (replay from settings)
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
                    .animation(.easeInOut(duration: 0.4), value: hasCompletedAIOnboarding)
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

                    // Refresh AI insights + rescue mode + proactive items
                    AIInsightEngine.shared.refresh(store: newStore)
                    AIBudgetRescue.shared.evaluate(store: newStore)
                    AIProactiveEngine.shared.refresh(store: newStore)
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
            .onChange(of: store) { oldStore, newStore in
                // Save locally IMMEDIATELY (not debounced) so budget/data never gets lost
                if let userId = authManager.currentUser?.uid {
                    if !newStore.save(userId: userId) {
                        showSaveFailedAlert = true
                    }
                }

                // Skip the cloud push entirely when the only thing that
                // changed is `selectedMonth`. `selectedMonth` is UI
                // navigation state — it's persisted locally so the app
                // remembers the last viewed month, but pushing it would
                // (a) waste a full saveStore round-trip on every swipe
                // and (b) race against any periodic sync, turning a
                // harmless month-change into a "Sync failed" toast.
                var oldNormalized = oldStore
                oldNormalized.selectedMonth = newStore.selectedMonth
                if oldNormalized == newStore {
                    return
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
            .sheet(isPresented: $showAIChat) {
                AIChatView(store: $store)
            }

                // Floating AI button (bottom-trailing)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            Haptics.medium()
                            showAIChat = true
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(DS.Colors.accent, in: Circle())
                                .shadow(color: DS.Colors.accent.opacity(0.4), radius: 8, y: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 90) // above tab bar
                    }
                }
                .ignoresSafeArea(.keyboard)
        }
    }
}




















