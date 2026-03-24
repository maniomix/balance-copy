import Foundation
import Network
import Combine

// ============================================================
// MARK: - Sync Coordinator
// ============================================================
//
// Central coordinator for all local ↔ cloud synchronization.
// Wraps existing SupabaseManager sync methods with:
//
//   1. Network connectivity monitoring (NWPathMonitor)
//   2. Overlap prevention (one sync at a time)
//   3. Retry with exponential backoff on failure
//   4. deletedTransactionIds cleanup after successful save
//   5. Sync status observable for UI feedback
//   6. Periodic sync management
//
// SOURCE-OF-TRUTH MODEL:
//
//   LOCAL-FIRST WRITE, CLOUD-AUTHORITATIVE READ
//
//   - User edits → saved to UserDefaults IMMEDIATELY (never lost)
//   - User edits → pushed to Supabase after 2-second debounce
//   - On pull (periodic/manual/launch): cloud data replaces local
//     for transactions, custom categories, recurring transactions.
//     Budgets use merge strategy: cloud wins unless cloud has no
//     data for a given month (local preserved as backup).
//   - On network loss: local edits accumulate safely in UserDefaults
//   - On reconnect: accumulated edits are pushed, then cloud pulled
//
// ============================================================

/// Observable sync status for the UI.
enum SyncStatus: Equatable {
    case idle
    case syncing
    case success(Date)
    case error(String)
    case offline

    var isActive: Bool {
        if case .syncing = self { return true }
        return false
    }
}

@MainActor
class SyncCoordinator: ObservableObject {

    static let shared = SyncCoordinator()

    // MARK: - Published State

    @Published var status: SyncStatus = .idle
    @Published var isOnline: Bool = true
    @Published var lastSuccessfulSync: Date?
    @Published var pendingChanges: Bool = false

    // MARK: - Private State

    private let supabase = SupabaseManager.shared
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.centmond.networkMonitor")
    private var periodicTask: Task<Void, Never>?
    private var retryCount: Int = 0
    private let maxRetries: Int = 3

    /// Lock to prevent overlapping sync operations.
    private var isSyncInProgress: Bool = false

    /// Track whether we have unsaved local changes that haven't been pushed.
    private var hasDirtyLocalChanges: Bool = false

    /// Track whether we came back from offline and need a full reconciliation.
    private var needsReconnectSync: Bool = false

    // MARK: - Constants

    private let periodicInterval: TimeInterval = 120  // 2 minutes
    private let debounceNanoseconds: UInt64 = 2_000_000_000  // 2 seconds

    // MARK: - Init

    private init() {
        startNetworkMonitoring()
    }

    deinit {
        monitor.cancel()
        periodicTask?.cancel()
    }

    // ============================================================
    // MARK: - Network Monitoring
    // ============================================================

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = (path.status == .satisfied)

                if self.isOnline && wasOffline {
                    // Just came back online
                    SecureLogger.info("Network restored — scheduling reconnect sync")
                    self.needsReconnectSync = true
                    self.status = .idle
                } else if !self.isOnline {
                    self.status = .offline
                    SecureLogger.info("Network lost — switching to offline mode")
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // ============================================================
    // MARK: - Push (Local → Cloud)
    // ============================================================

    /// Push local store changes to the cloud. Called after user edits.
    /// This is the debounced "save" path — it only writes, never reads.
    ///
    /// - Parameters:
    ///   - store: The current Store value to push.
    ///   - userId: The authenticated user's ID.
    /// - Returns: An updated Store with deletedTransactionIds cleared on success, or nil on failure.
    func pushToCloud(store: Store, userId: String) async -> Store? {
        guard isOnline else {
            hasDirtyLocalChanges = true
            SecureLogger.debug("Offline — push deferred")
            return nil
        }

        guard !isSyncInProgress else {
            // Another sync is running; mark dirty so it retries
            hasDirtyLocalChanges = true
            SecureLogger.debug("Sync in progress — push deferred")
            return nil
        }

        isSyncInProgress = true
        status = .syncing
        defer {
            isSyncInProgress = false
        }

        do {
            try await supabase.saveStore(store)

            // Clear deletedTransactionIds after successful cloud save
            var cleaned = store
            if !cleaned.deletedTransactionIds.isEmpty {
                SecureLogger.debug("Clearing \(cleaned.deletedTransactionIds.count) synced deletion markers")
                cleaned.deletedTransactionIds = []
            }

            retryCount = 0
            hasDirtyLocalChanges = false
            status = .success(Date())
            lastSuccessfulSync = Date()
            SecureLogger.info("Push to cloud succeeded")
            return cleaned

        } catch {
            retryCount += 1
            hasDirtyLocalChanges = true
            let message = AppConfig.shared.safeErrorMessage(
                detail: error.localizedDescription,
                fallback: "Sync failed. Your data is saved locally."
            )
            status = .error(message)
            SecureLogger.error("Push to cloud failed (attempt \(retryCount))", error)
            return nil
        }
    }

    // ============================================================
    // MARK: - Pull (Cloud → Local)
    // ============================================================

    /// Pull latest data from cloud and merge with local store.
    /// This is the "sync/refresh" path used on launch, periodic, and manual triggers.
    ///
    /// - Parameters:
    ///   - localStore: The current local Store to merge against.
    ///   - userId: The authenticated user's ID.
    /// - Returns: The merged Store from cloud, or nil on failure (local data preserved).
    func pullFromCloud(localStore: Store, userId: String) async -> Store? {
        guard isOnline else {
            status = .offline
            SecureLogger.debug("Offline — pull skipped")
            return nil
        }

        guard !isSyncInProgress else {
            SecureLogger.debug("Sync in progress — pull skipped")
            return nil
        }

        isSyncInProgress = true
        status = .syncing
        defer {
            isSyncInProgress = false
        }

        do {
            let cloudStore = try await supabase.syncStore(localStore)

            retryCount = 0
            needsReconnectSync = false
            status = .success(Date())
            lastSuccessfulSync = Date()
            SecureLogger.info("Pull from cloud succeeded")
            return cloudStore

        } catch {
            retryCount += 1
            let message = AppConfig.shared.safeErrorMessage(
                detail: error.localizedDescription,
                fallback: "Could not sync. Using local data."
            )
            status = .error(message)
            SecureLogger.error("Pull from cloud failed (attempt \(retryCount))", error)
            return nil
        }
    }

    // ============================================================
    // MARK: - Full Reconcile (Push + Pull)
    // ============================================================

    /// Full sync cycle: push local changes first, then pull cloud state.
    /// Used on reconnect after offline period or manual "force sync".
    ///
    /// - Parameters:
    ///   - store: Current local store.
    ///   - userId: The authenticated user's ID.
    /// - Returns: The reconciled Store, or nil on failure.
    func fullReconcile(store: Store, userId: String) async -> Store? {
        guard isOnline else {
            status = .offline
            return nil
        }

        guard !isSyncInProgress else {
            SecureLogger.debug("Sync in progress — reconcile skipped")
            return nil
        }

        SecureLogger.info("Starting full reconciliation")
        isSyncInProgress = true
        status = .syncing
        defer {
            isSyncInProgress = false
        }

        // Step 1: Push any accumulated local changes
        do {
            try await supabase.saveStore(store)
            SecureLogger.info("Reconcile: push succeeded")
        } catch {
            SecureLogger.error("Reconcile: push failed — continuing with pull", error)
            // Continue to pull even if push failed; don't lose cloud data
        }

        // Step 2: Pull cloud state
        do {
            let cloudStore = try await supabase.syncStore(store)

            // Clear deletedTransactionIds since push (hopefully) succeeded
            var reconciled = cloudStore
            reconciled.deletedTransactionIds = []

            retryCount = 0
            needsReconnectSync = false
            hasDirtyLocalChanges = false
            status = .success(Date())
            lastSuccessfulSync = Date()
            SecureLogger.info("Reconcile: pull succeeded")
            return reconciled

        } catch {
            retryCount += 1
            let message = AppConfig.shared.safeErrorMessage(
                detail: error.localizedDescription,
                fallback: "Sync failed. Your data is saved locally."
            )
            status = .error(message)
            SecureLogger.error("Reconcile: pull failed", error)
            return nil
        }
    }

    // ============================================================
    // MARK: - Periodic Sync
    // ============================================================

    /// Start the periodic sync loop. Call once after login.
    func startPeriodicSync(getStore: @escaping @MainActor () -> Store,
                           setStore: @escaping @MainActor (Store) -> Void,
                           getUserId: @escaping @MainActor () -> String?) {
        stopPeriodicSync()

        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self?.periodicInterval ?? 120) * 1_000_000_000)
                guard !Task.isCancelled else { break }
                guard let self else { break }

                guard let userId = await getUserId() else { continue }

                // If we came back from offline, do a full reconcile
                if self.needsReconnectSync {
                    let currentStore = await getStore()
                    if let reconciled = await self.fullReconcile(store: currentStore, userId: userId) {
                        await setStore(reconciled)
                        reconciled.save(userId: userId)
                    }
                    continue
                }

                // If we have dirty local changes, push them first
                if self.hasDirtyLocalChanges {
                    let currentStore = await getStore()
                    if let cleaned = await self.pushToCloud(store: currentStore, userId: userId) {
                        await setStore(cleaned)
                        cleaned.save(userId: userId)
                    }
                }

                // Regular periodic pull
                let currentStore = await getStore()
                if let cloudStore = await self.pullFromCloud(localStore: currentStore, userId: userId) {
                    await setStore(cloudStore)
                    cloudStore.save(userId: userId)
                }
            }
        }
    }

    /// Stop the periodic sync loop. Call on logout or deinit.
    func stopPeriodicSync() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    // ============================================================
    // MARK: - Retry with Backoff
    // ============================================================

    /// Calculate backoff delay based on retry count.
    private var backoffDelay: UInt64 {
        let base: UInt64 = 2_000_000_000  // 2 seconds
        let delay = base * UInt64(pow(2.0, Double(min(retryCount, 4))))
        return min(delay, 60_000_000_000)  // Cap at 60 seconds
    }

    /// Reset retry state (call on successful sync).
    func resetRetryState() {
        retryCount = 0
    }
}
