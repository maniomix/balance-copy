# Balance — Sync Architecture

## Source-of-Truth Model

**LOCAL-FIRST WRITE, CLOUD-AUTHORITATIVE READ**

User edits are saved to `UserDefaults` immediately and are never lost — even if the network is unavailable or a cloud push fails. Cloud data is authoritative on reads: when a pull completes, cloud state replaces local state for most data types, with a merge strategy for budgets.

### Write Path (Local → Cloud)

1. User makes a change (add/edit/delete transaction, update budget, etc.)
2. SwiftUI's `.onChange(of: store)` fires
3. The new store is saved to `UserDefaults` **immediately** (not debounced)
4. After a 2-second debounce, `SyncCoordinator.pushToCloud()` is called
5. On success, `deletedTransactionIds` are cleared from the local store
6. On failure (offline/error), `hasDirtyLocalChanges` is flagged for retry

### Read Path (Cloud → Local)

1. On app launch: `SyncCoordinator.pullFromCloud()` replaces local data with cloud data
2. On auth state change: Same pull-from-cloud path
3. Every 2 minutes: Periodic sync checks for cloud updates
4. On manual refresh: `SyncCoordinator.fullReconcile()` pushes then pulls

### Merge Strategy by Data Type

| Data Type | Strategy |
|-----------|----------|
| Transactions | Cloud replaces local |
| Custom categories | Cloud replaces local |
| Recurring transactions | Cloud replaces local |
| Budgets | **Merge**: cloud wins for each month-key. If cloud has no entry for a month-key (`nil`), local value is preserved as backup. A cloud value of `0` is intentional and wins over local. |
| `deletedTransactionIds` | Cleared after successful push; not pulled from cloud |

---

## Key Components

### SyncCoordinator (`Sync/SyncCoordinator.swift`)

Central coordinator for all sync operations. Singleton, `@MainActor`, `ObservableObject`.

**Responsibilities:**
- Network connectivity monitoring via `NWPathMonitor`
- Overlap prevention (`isSyncInProgress` flag — one sync at a time)
- Retry tracking with exponential backoff (2s base, 60s cap)
- `deletedTransactionIds` cleanup after successful push
- Sync status observable for UI feedback (`SyncStatus` enum)
- Periodic sync management (2-minute interval)
- Reconnect detection: flags `needsReconnectSync` when network restores, triggers `fullReconcile` on next periodic tick

**Public API:**

| Method | Direction | Usage |
|--------|-----------|-------|
| `pushToCloud(store:userId:)` | Local → Cloud | After user edits (debounced 2s) |
| `pullFromCloud(localStore:userId:)` | Cloud → Local | Launch, periodic, auth change |
| `fullReconcile(store:userId:)` | Push + Pull | Reconnect, manual "force sync" |
| `startPeriodicSync(...)` | Both | Called once after login |
| `stopPeriodicSync()` | — | Called on logout |

### SyncStatus

```
.idle        — No sync activity
.syncing     — Sync in progress
.success(Date) — Last successful sync timestamp
.error(String) — Last error (sanitized for production)
.offline     — No network connectivity
```

### SupabaseManager (`SupaBase/SupabaseManager.swift`)

Handles the actual Supabase API calls. SyncCoordinator wraps these methods.

- `saveStore(_:)` — Upserts all store data to Supabase tables
- `syncStore(_:)` — Fetches cloud data and merges with local store

### ContentView Integration

| SwiftUI Modifier | Behavior |
|------------------|----------|
| `.onChange(of: store)` #1 | Notification rule evaluation, engine regeneration |
| `.onChange(of: store)` #2 | Immediate local save + debounced `pushToCloud` |
| `.onChange(of: scenePhase)` | Local save on background, analytics session management |
| `.task(id: isAuthenticated)` | Pull from cloud on login; stop sync + reset on logout |
| `loadUserData()` | Local load → cloud pull → start periodic sync |
| `manualSync()` | Full reconcile (push + pull) |

---

## Offline Behavior

1. **Network lost**: `SyncCoordinator.status` → `.offline`, all push/pull calls return `nil` gracefully
2. **Edits while offline**: Saved to `UserDefaults` immediately, `hasDirtyLocalChanges` flagged
3. **Network restored**: `needsReconnectSync` flagged → next periodic tick runs `fullReconcile()` (push accumulated changes, then pull latest cloud state)
4. **No data loss**: Local-first write ensures user never loses work regardless of network state

## Deletion Tracking

- When a user deletes a transaction, its ID is added to `store.deletedTransactionIds`
- On `pushToCloud`, `SupabaseManager.saveStore()` processes these deletions on the server
- After a successful push, `deletedTransactionIds` is cleared from the local store
- This prevents re-deletion attempts on subsequent syncs

## Race Condition Prevention

- `isSyncInProgress` flag prevents overlapping sync operations
- If a push is attempted while sync is in progress, `hasDirtyLocalChanges` is flagged for retry
- If a pull is attempted while sync is in progress, it returns `nil` (local data preserved)
- The debounce on `.onChange(of: store)` (2 seconds) coalesces rapid edits into a single push

---

## Changes Made (Hardening Pass)

1. **Created `SyncCoordinator`** — centralized sync logic that was previously scattered across ContentView
2. **Fixed budget merge zero-value ambiguity** — changed `== nil || == 0` to just `== nil` so intentional zero budgets from cloud are preserved
3. **Removed duplicate auth state from SupabaseManager** — `currentUser` is now a computed property delegating to `AuthManager.shared`
4. **Updated ContentView sync triggers** — `.onChange(of: store)` and `.task(id: isAuthenticated)` now route through SyncCoordinator
5. **Replaced all sync-related `print()` calls** with `SecureLogger` (no sensitive data in production logs)
6. **Added `stopPeriodicSync()` on logout** — prevents background sync after user signs out
7. **`deletedTransactionIds` cleanup** — cleared after successful cloud push, not left to accumulate
