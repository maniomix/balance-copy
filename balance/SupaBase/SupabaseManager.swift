import Foundation
import Supabase
import SwiftUI
import Combine

// MARK: - Supabase Manager
// ============================================================
//
// Data access layer for Supabase. Handles CRUD operations
// for transactions, budgets, categories, and recurring items.
//
// Auth state is managed exclusively by AuthManager.
// Sync orchestration is managed by SyncCoordinator.
// This class only provides the raw read/write operations.
//
// ============================================================
@MainActor
class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    /// Implicitly-unwrapped because `setupClient()` guarantees assignment at
    /// init time — if configuration is missing it crashes loudly via
    /// `preconditionFailure` rather than leaving `client` nil for a later
    /// call site to discover with a mystery IUO crash.
    var client: SupabaseClient!

    /// Tracks whether a sync operation is in progress (used internally).
    @Published var isSyncing = false

    /// Auth state — delegates to AuthManager as single source of truth.
    var currentUser: User? { AuthManager.shared.currentUser }

    /// Convenience: current user's UUID as a string, or nil if not authenticated.
    var currentUserId: String? { currentUser?.id.uuidString }

    init() {
        setupClient()
    }

    private func setupClient() {
        let config = AppConfig.shared
        config.validate()

        guard !config.supabaseURL.isEmpty, !config.supabaseAnonKey.isEmpty,
              let supabaseURL = URL(string: config.supabaseURL) else {
            // Crash immediately with a clear diagnostic instead of limping
            // forward with a nil `client` that will crash later via IUO
            // unwrap at some random auth/sync call site. The app is
            // unusable without backend config, so failing at launch is
            // strictly better than failing mid-session.
            SecureLogger.error("Missing Supabase configuration. Check Config.plist.")
            preconditionFailure("Supabase configuration missing or invalid — cannot start app. See Security/SECURITY.md.")
        }

        // Opt into the new Supabase Auth behaviour (PR #822): always
        // emit the locally-stored session as the initial session, even
        // when the cached token is expired. Consumers must then guard on
        // `session.isExpired` themselves — AuthManager does this.
        // Silences the SDK's "Initial session emitted after attempting
        // to refresh…" warning and prevents surprising auth flips on
        // cold-start when the refresh token is stale.
        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: config.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )

        SecureLogger.info("Supabase client initialized [\(config.environment.rawValue)]")
    }
    
    // MARK: - Auth Methods
    
    func signUp(email: String, password: String, displayName: String? = nil) async throws {
        SecureLogger.info("Starting sign up")
        do {
            let metadata: [String: AnyJSON] = displayName.map { ["display_name": .string($0)] } ?? [:]
            _ = try await client.auth.signUp(email: email, password: password, data: metadata)
            // Profile row is created by the `handle_new_user` Postgres trigger.
            SecureLogger.info("Auth sign up successful")
        } catch {
            SecureLogger.error("Sign up failed", error)
            throw error
        }
    }
    
    func signIn(email: String, password: String) async throws {
        SecureLogger.info("Signing in")
        try await client.auth.signIn(email: email, password: password)
        SecureLogger.info("Sign in successful")
    }

    func signOut() throws {
        SecureLogger.info("Signing out")
        Task {
            try await client.auth.signOut()
        }
    }

    func resetPassword(email: String) async throws {
        SecureLogger.info("Password reset requested")
        try await client.auth.resetPasswordForEmail(email)
        SecureLogger.info("Password reset email sent")
    }

    func changePassword(newPassword: String) async throws {
        SecureLogger.info("Changing password")
        try await client.auth.update(user: UserAttributes(password: newPassword))
        SecureLogger.info("Password changed")
    }
    
    // MARK: - Store Sync (Complete Store)
    
    func syncStore(_ localStore: Store) async throws -> Store {
        guard let userId = currentUser?.id.uuidString else {
            throw NSError(domain: "Supabase", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        SecureLogger.info("Syncing store")
        
        // Load all data
        let cloudTransactions = try await loadTransactions(userId: userId)

        // CRITICAL: filter out transactions the user just deleted but that
        // haven't been pushed to the cloud yet. Without this guard, a pull
        // that races the 2-second debounce window will resurrect a deleted
        // transaction in the UI — user sees the deletion "undo itself", and
        // it'll only stay deleted on the next push cycle.
        let pendingDeletions = Set(localStore.deletedTransactionIds.compactMap { UUID(uuidString: $0) })
        let transactions: [Transaction] = pendingDeletions.isEmpty
            ? cloudTransactions
            : cloudTransactions.filter { !pendingDeletions.contains($0.id) }

        let budgets = try await loadBudgets(userId: userId)
        let categoryBudgets = try await loadCategoryBudgets(userId: userId)
        let customCategories = try await loadCustomCategories(userId: userId)
        // Recurring is derived from transactions at runtime — preserve whatever
        // RecurringDetector already produced locally; no cloud round-trip.
        let recurringTransactions = localStore.recurringTransactions
        
        // Merge strategy for budgets:
        //   Cloud is authoritative. Local values are only preserved as a
        //   safety net when the cloud has NO entry at all for a given month
        //   (key missing from dictionary). This prevents data loss during
        //   offline edits while still allowing intentional zero-value budgets.
        //
        //   If cloud returns a key (even with value 0), cloud wins.
        //   If cloud is missing a key entirely, local value is kept.
        var mergedBudgets = budgets
        for (key, value) in localStore.budgetsByMonth {
            if mergedBudgets[key] == nil {
                // Cloud doesn't have this month at all — preserve local
                mergedBudgets[key] = value
            }
            // If cloud has the key (even == 0), cloud wins — no override
        }
        var mergedCategoryBudgets = categoryBudgets
        for (monthKey, localCats) in localStore.categoryBudgetsByMonth {
            if mergedCategoryBudgets[monthKey] == nil {
                // Cloud has no data for this month — preserve all local categories
                mergedCategoryBudgets[monthKey] = localCats
            } else {
                // Cloud has this month — only fill in categories cloud is missing entirely
                for (catKey, value) in localCats {
                    if mergedCategoryBudgets[monthKey]?[catKey] == nil {
                        mergedCategoryBudgets[monthKey]?[catKey] = value
                    }
                }
            }
        }

        var syncedStore = localStore
        syncedStore.transactions = transactions
        syncedStore.budgetsByMonth = mergedBudgets
        syncedStore.categoryBudgetsByMonth = mergedCategoryBudgets
        syncedStore.customCategoriesWithIcons = customCategories
        syncedStore.recurringTransactions = recurringTransactions
        // Phase 7: legacy `customCategoryNames` is no longer rebuilt here;
        // `Store.migrateCustomCategoriesIfNeeded()` drains it on load.

        // Auto-recognize incoming custom categories.
        // A transaction can arrive tagged `.custom("Coffee")` even when
        // the cloud `categories` table doesn't have a row for "Coffee"
        // yet (e.g. macOS CSV import created it locally but the
        // category-sync push hasn't landed yet, or iOS pulled the tx
        // before the category). Without this, "Coffee" wouldn't appear
        // in iOS's category picker — the user would see the tag on the
        // tx but couldn't pick "Coffee" elsewhere.
        //
        // Matches macOS's behaviour: unknown categories are auto-
        // created from the data, not fallen-back-to-Other. The next
        // saveStore push propagates these new locals back to cloud so
        // every device converges.
        let knownCustomNames = Set(syncedStore.customCategoriesWithIcons.map { $0.name.lowercased() })
        var unseenNames: [String] = []
        var unseenSet = Set<String>()
        for tx in syncedStore.transactions {
            if case .custom(let name) = tx.category {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = trimmed.lowercased()
                guard !trimmed.isEmpty,
                      !knownCustomNames.contains(key),
                      !unseenSet.contains(key) else { continue }
                unseenSet.insert(key)
                unseenNames.append(trimmed)
            }
        }
        if !unseenNames.isEmpty {
            for name in unseenNames {
                syncedStore.addCustomCategory(name: name)
            }
            SecureLogger.info("Auto-created \(unseenNames.count) custom categor(y/ies) from incoming transactions")
        }

        SecureLogger.info("Store synced: \(transactions.count) transactions, \(recurringTransactions.count) recurring, \(customCategories.count) custom categories\(unseenNames.isEmpty ? "" : " (+\(unseenNames.count) auto-created)")")
        return syncedStore
    }
    
    func saveStore(_ store: Store) async throws {
        guard let userId = currentUser?.id.uuidString else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        SecureLogger.debug("Saving store")
        
        // 1. Hard delete removed transactions from Supabase.
        // **Errors propagate** so SyncCoordinator marks the push as failed and
        // keeps `deletedTransactionIds` populated for the next retry. Without
        // this, a swallowed error would lead SyncCoordinator to clear the
        // deletion markers, making the deletion impossible to ever propagate
        // — the local row was already gone, but the cloud row would live
        // forever and resurrect on the next pull.
        let pendingIds: [UUID] = store.deletedTransactionIds.compactMap(UUID.init(uuidString:))
        if !pendingIds.isEmpty {
            try await TransactionRepository.shared.deleteMany(ids: pendingIds)
            SecureLogger.info("Deleted \(pendingIds.count) transaction(s) from cloud")
        }
        
        // 2. Upsert only transactions modified locally since the last
        // successful sync. Without this, we'd blanket-upsert *every*
        // transaction on every push — which would re-insert any transaction
        // another device deleted in the meantime, because we still have it
        // in our in-memory store.
        //
        // First-ever push (lastSyncedAt == nil) → upserts everything.
        let cutoff = store.lastSyncedAt ?? .distantPast
        let dirtyTransactions = store.transactions.filter { $0.lastModified > cutoff }
        if !dirtyTransactions.isEmpty {
            try await TransactionRepository.shared.upsertMany(dirtyTransactions)
            SecureLogger.info("Upserted \(dirtyTransactions.count) of \(store.transactions.count) transaction(s) (cutoff: \(cutoff))")
        } else if !store.transactions.isEmpty {
            SecureLogger.debug("No dirty transactions to upsert (\(store.transactions.count) total, all unchanged since last sync)")
        }
        
        // 3+4. Budgets — delegated to BudgetManager (handles delete-missing + upsert).
        try await BudgetManager.shared.syncMonthlyTotals(store.budgetsByMonth)
        try await BudgetManager.shared.syncCategoryBudgets(store.categoryBudgetsByMonth)

        // 5. Save custom categories
        try await saveCustomCategories(store.customCategoriesWithIcons, userId: userId)
        
        // 6. Save recurring transactions
        try await saveRecurringTransactions(store.recurringTransactions, userId: userId)
        
        SecureLogger.info("Store saved")
    }
    
    // MARK: - Transactions  (delegated to TransactionRepository — Phase 5.3)

    func saveTransaction(_ transaction: Transaction, userId: String) async throws {
        try await TransactionRepository.shared.upsert(transaction)
    }

    func loadTransactions(userId: String) async throws -> [Transaction] {
        SecureLogger.debug("Loading transactions")
        let txs = try await TransactionRepository.shared.fetchAll()
        SecureLogger.info("Loaded \(txs.count) transactions")
        return txs
    }

    func deleteTransaction(_ transactionId: UUID) async throws {
        guard currentUser != nil else {
            SecureLogger.warning("deleteTransaction: No authenticated user")
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        try await TransactionRepository.shared.delete(id: transactionId)
    }
    
    // MARK: - Budgets  (delegated to BudgetManager — Phase 5.4)

    func saveBudget(userId: String, month: Date, amount: Int) async throws {
        let key = dateToMonthKey(month)
        try await BudgetManager.shared.syncMonthlyTotals([key: amount])
    }

    func loadBudgets(userId: String) async throws -> [String: Int] {
        try await BudgetManager.shared.fetchMonthlyTotals()
    }

    func saveCategoryBudget(userId: String, month: Date, category: String, amount: Int) async throws {
        let key = dateToMonthKey(month)
        // Single-row variant — caller flow uses the bulk path now.
        struct UpsertRow: Encodable {
            let month: String
            let category_key: String
            let amount: Int
        }
        try await client
            .from("monthly_category_budgets")
            .upsert(UpsertRow(month: key, category_key: category, amount: amount),
                    onConflict: "owner_id,month,category_key")
            .execute()
    }


    func loadCategoryBudgets(userId: String) async throws -> [String: [String: Int]] {
        try await BudgetManager.shared.fetchCategoryBudgets()
    }
    
    // MARK: - Real-time Sync (Phase 6)
    //
    // Opens one channel and one postgresChange stream per cross-device-
    // relevant table. RLS scopes events to the current user automatically,
    // so each device only receives its own changes.
    //
    // The `onUpdate` callback is debounced (1.5s) and fired once after a
    // burst of events — ContentView reacts by pulling from cloud, which
    // refreshes the in-memory store + the JSONB-blob syncs (AI / subs /
    // household / filter presets).

    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeStreamTasks: [Task<Void, Never>] = []
    private var realtimeDebounce: Task<Void, Never>?

    private static let realtimeWatchedTables: [String] = [
        "transactions", "monthly_budgets", "monthly_category_budgets",
        "goals", "goal_contributions", "categories", "accounts", "profiles",
        "subscription_state", "subscriptions", "household_state",
        "ai_memory", "ai_chat_sessions", "ai_chat_messages",
        "saved_filter_presets"
    ]

    func startRealtimeSync(userId: String, onUpdate: @escaping () -> Void) {
        guard realtimeChannel == nil else { return }   // already running
        let channelName = "centmond-\(userId)"
        let channel = client.channel(channelName)
        self.realtimeChannel = channel

        for table in Self.realtimeWatchedTables {
            let stream = channel.postgresChange(
                AnyAction.self, schema: "public", table: table
            )
            let task = Task { [weak self] in
                for await _ in stream {
                    await MainActor.run { self?.scheduleRealtimeRefresh(onUpdate: onUpdate) }
                }
            }
            realtimeStreamTasks.append(task)
        }

        Task { await channel.subscribe() }
        SecureLogger.info("Realtime: subscribed to \(Self.realtimeWatchedTables.count) tables")
    }

    func stopRealtimeSync() {
        realtimeDebounce?.cancel()
        realtimeDebounce = nil
        realtimeCycleActive = false
        realtimePullPending = false
        for t in realtimeStreamTasks { t.cancel() }
        realtimeStreamTasks.removeAll()
        if let channel = realtimeChannel {
            Task { await channel.unsubscribe() }
        }
        realtimeChannel = nil
        SecureLogger.debug("Realtime: stopped")
    }

    /// Realtime cycle scheduling state. Replaces the old
    /// cancel-and-restart debounce that starved during bursts of
    /// macOS pushes — every postgres_changes event reset the timer,
    /// so during a heavy CSV upload (~10s of chunked events) the pull
    /// never fired and the user had to relaunch to see new data.
    /// New rules mirror macOS CloudSyncCoordinator's queue pattern:
    ///   • `realtimeCycleActive` guards against concurrent cycles.
    ///   • Events arriving WHILE a cycle runs raise
    ///     `realtimePullPending`; the cycle re-fires itself on
    ///     completion if the flag is set.
    ///   • Events arriving while the debounce timer is already
    ///     scheduled are coalesced (no-op).
    private var realtimeCycleActive = false
    private var realtimePullPending = false

    private func scheduleRealtimeRefresh(onUpdate: @escaping () -> Void) {
        // OWN-ECHO GUARD: Postgres replication broadcasts our OWN writes
        // back as realtime events. If we just pushed (within 3s), the
        // event is almost certainly our own echo — pulling now risks
        // hitting a read-replica that hasn't caught up to the primary
        // yet, returning the OLD value, which then wins the
        // cloud-is-authoritative merge and the user sees their edit
        // revert. (Specifically reproduced with budget edits: type new
        // value → save → snaps back to old → next click fixes it.)
        // The 3s window covers typical replication lag (~10-300ms) plus
        // the 800ms realtime debounce.
        if let lastPush = SyncCoordinator.shared.lastSuccessfulSync,
           Date().timeIntervalSince(lastPush) < 3.0 {
            SecureLogger.debug("Realtime: skipping echo of own write (last push \(Int(Date().timeIntervalSince(lastPush) * 1000))ms ago)")
            return
        }
        // Cycle in flight → flag a re-run after it completes.
        if realtimeCycleActive {
            realtimePullPending = true
            return
        }
        // Debounce already armed → coalesce; the upcoming run picks
        // up everything that has changed.
        if realtimeDebounce != nil { return }

        realtimeDebounce = Task { @MainActor [weak self] in
            // 800 ms — long enough to coalesce the typical postgres
            // fan-out from one local save (server fans out faster than
            // that) but short enough that a single iOS edit lands on
            // macOS in well under a second. Was 2.5 s; reducing it
            // alone doesn't break starvation, the queue pattern does.
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self else { return }
            self.realtimeDebounce = nil
            await self.runRealtimeCycle(onUpdate: onUpdate)
        }
    }

    /// One non-overlapping realtime cycle: blob-state pulls in
    /// parallel, then `onUpdate` (which re-pulls the store via
    /// SyncCoordinator). Sets `realtimeCycleActive` so concurrent
    /// triggers don't pile on, and re-fires itself if events arrived
    /// during execution.
    private func runRealtimeCycle(onUpdate: @escaping () -> Void) async {
        realtimeCycleActive = true
        defer {
            realtimeCycleActive = false
            // Re-fire if events came in mid-cycle so we never miss
            // anything. One extra cycle at most — it'll catch up.
            if realtimePullPending {
                realtimePullPending = false
                scheduleRealtimeRefresh(onUpdate: onUpdate)
            }
        }
        await SubscriptionStateSync.pull()
        await SubscriptionsTableSync.pull()
        await SavedFilterPresetSync.pull()
        await AIStateSync.pull()
        onUpdate()
    }
    
    // MARK: - Analytics  (Phase 5.10 — writes to public.app_events)

    func trackEvent(name: String, properties: [String: Any]? = nil) async {
        // owner_id auto-fills via fill_owner_id trigger; anon events still land
        // with null owner_id when no user is signed in.
        struct InsertRow: Encodable {
            let event_name: String
            let properties: AnyJSONValue
            let device_id: String?
        }
        // Stringify property values so AnyJSONValue stays a flat object map
        // — keeps server-side queries simple (no nested numbers vs strings).
        let propsObject: [String: AnyJSONValue] = (properties ?? [:])
            .reduce(into: [:]) { $0[$1.key] = .string("\($1.value)") }

        let row = InsertRow(
            event_name: name,
            properties: .object(propsObject),
            device_id: Self.deviceId
        )
        do {
            try await client
                .from("app_events")
                .insert(row)
                .execute()
        } catch {
            SecureLogger.warning("Failed to track event: \(name)")
        }
    }

    /// Stable per-install device identifier (UUID kept in UserDefaults).
    /// Used for analytics + device_sessions joins.
    private static let deviceId: String = {
        let key = "centmond.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    /// Heartbeat into `device_sessions` so the dashboard / admin web can show
    /// "last seen" per device. Idempotent — upserts on (owner_id, device_id).
    func updateLastActive() async throws {
        guard currentUser != nil else { return }
        struct Row: Encodable {
            let device_id: String
            let platform: String
            let device_name: String?
            let app_version: String?
            let last_seen_at: String
        }
        let now = ISO8601DateFormatter().string(from: Date())
        let row = Row(
            device_id: Self.deviceId,
            platform: "ios",
            device_name: deviceName,
            app_version: AppConfig.shared.appVersion,
            last_seen_at: now
        )
        try await client
            .from("device_sessions")
            .upsert(row, onConflict: "owner_id,device_id")
            .execute()
    }

    private var deviceName: String? {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName
        #endif
    }
    
    // MARK: - Delete Month Data
    
    /// حذف کامل داده‌های یک ماه از Supabase
    /// شامل: transactions, budgets, category_budgets
    func deleteMonthData(userId: String, monthKey: String) async throws {
        guard let currentId = currentUser?.id.uuidString.lowercased(),
              userId.lowercased() == currentId else {
            SecureLogger.security("deleteMonthData: userId mismatch with authenticated user")
            throw NSError(domain: "SupabaseManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        }

        SecureLogger.debug("Deleting month data from Supabase: \(monthKey)")

        // 1. Transactions in [start, nextMonthStart)
        guard let monthStart = monthKeyToDate(monthKey),
              let monthEnd = Calendar.current.date(byAdding: .month, value: 1, to: monthStart) else {
            throw NSError(domain: "SupabaseManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid month key"])
        }
        let iso = ISO8601DateFormatter()
        try await client
            .from("transactions")
            .delete()
            .gte("occurred_at", value: iso.string(from: monthStart))
            .lt("occurred_at", value: iso.string(from: monthEnd))
            .execute()

        // 2+3. Budgets via the manager (handles both monthly_budgets and monthly_category_budgets).
        try await BudgetManager.shared.deleteMonth(monthKey)

        SecureLogger.info("Month data fully deleted")
    }
    
    // MARK: - Helpers
    
    private func dateToMonthKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
    
    private func monthKeyToDate(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.date(from: key)
    }
}

// MARK: - Recurring Transactions
//
// Per the locked rebuild decision, recurring transactions are **derived
// from transaction history** at runtime by `RecurringDetector` — there is
// no `recurring_transactions` table in the new schema. These two methods
// are kept so the existing `syncStore` / `saveStore` call sites compile,
// but they're no-ops. Local `Store.recurringTransactions` survives via
// the regular Store JSON snapshot in UserDefaults.
extension SupabaseManager {

    func saveRecurringTransactions(_ recurring: [RecurringTransaction], userId: String) async throws {
        // No-op: recurring is derived, not persisted.
    }

    func loadRecurringTransactions(userId: String) async throws -> [RecurringTransaction] {
        // No-op: recurring is derived, not persisted. Caller's local store
        // already holds the locally-detected list.
        return []
    }
}

// MARK: - Custom Categories
extension SupabaseManager {
    
    /// Save custom categories to Supabase. Delegates to `CategoryManager`,
    /// which reconciles the rows in `public.categories` (is_custom = true).
    func saveCustomCategories(_ categories: [CustomCategoryModel], userId: String) async throws {
        SecureLogger.debug("Saving \(categories.count) custom categories")
        try await CategoryManager.shared.sync(categories)
        SecureLogger.info("Custom categories saved")
    }

    /// Load custom categories from Supabase via `CategoryManager`.
    /// `userId` parameter is unused (RLS scopes the query to auth.uid()) but
    /// kept so the caller signature stays stable.
    func loadCustomCategories(userId: String) async throws -> [CustomCategoryModel] {
        SecureLogger.debug("Loading custom categories")
        let result = try await CategoryManager.shared.fetchCustom()
        SecureLogger.info("Loaded \(result.count) custom categories")
        return result
    }
}

// MARK: - User Extension
extension User {
    var uid: String {
        id.uuidString
    }
    
    // Note: User already has 'email' property from Supabase
    // No need to override it
    
    var isEmailVerified: Bool {
        // Check if email is confirmed in Supabase
        return emailConfirmedAt != nil
    }
}
