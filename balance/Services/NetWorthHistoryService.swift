import Foundation

// ============================================================
// MARK: - Net Worth History Service (Phase 4c — iOS port)
// ============================================================
//
// Writes `NetWorthSnapshot` aggregates into `Store.netWorthSnapshots`.
// Call on launch / scene-active / midnight — overlapping fires are
// harmless (idempotent per calendar day).
//
// Historical backfill walks backwards from each account's live
// `currentBalance` by unwinding transaction deltas for that account.
//
// Ported from macOS Centmond. iOS adaptations:
//   - Stores into Store (value type) instead of SwiftData context
//   - Accounts are passed in (they live in `AccountManager`, outside Store)
//   - Amounts: Int cents (Account.currentBalance Double → cents at boundary)
//   - Dropped `AccountBalancePoint` per-account daily rows — not needed by
//     current iOS UI. Can be re-added when account-detail charting lands.
//   - Account filter uses only `!isArchived` (iOS Account lacks
//     `isClosed` / `includeInNetWorth`)
//   - Sign convention matches macOS: assets added, liabilities subtracted
//     using the absolute value of the historical balance
// ============================================================

enum NetWorthHistoryService {

    // MARK: - Settings

    private static let backfillKey     = "netWorthBackfillDays"
    private static let autoSnapshotKey = "netWorthAutoSnapshotEnabled"

    static var effectiveBackfillDays: Int {
        let raw = UserDefaults.standard.integer(forKey: backfillKey)
        let value = raw == 0 ? 365 : raw
        return min(max(value, 30), 1825)   // clamp 1 month to 5 years
    }

    static var effectiveAutoSnapshotEnabled: Bool {
        if UserDefaults.standard.object(forKey: autoSnapshotKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: autoSnapshotKey)
    }

    // MARK: - Public API

    /// Writes a snapshot for today if one does not already exist for the
    /// current calendar day. Returns true when it actually wrote a row.
    /// Skipped entirely when auto-snapshot is disabled.
    @discardableResult
    static func tick(store: inout Store, accounts: [Account]) -> Bool {
        guard effectiveAutoSnapshotEnabled else { return false }
        let day = Calendar.current.startOfDay(for: Date())
        guard !snapshotExists(on: day, in: store) else { return false }
        writeSnapshot(on: day, source: .auto, accounts: accounts, sortedTxnsCache: nil, store: &store)
        return true
    }

    /// Forces a new snapshot right now ("Snapshot now" action). Replaces
    /// any row on the same day so repeated taps don't pile up duplicates.
    static func snapshotNow(store: inout Store, accounts: [Account]) {
        let day = Calendar.current.startOfDay(for: Date())
        deleteSnapshots(on: day, store: &store)
        writeSnapshot(on: day, source: .manual, accounts: accounts, sortedTxnsCache: nil, store: &store)
    }

    /// Soft fill: writes missing daily rows from the earliest existing
    /// snapshot (or `daysBack` days ago, whichever is later) through today.
    /// Skips days that already have a row. Safe to re-run.
    static func backfillIfNeeded(store: inout Store, accounts: [Account], daysBack: Int? = nil) {
        let daysBack = daysBack ?? effectiveBackfillDays
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let earliestWanted = cal.date(byAdding: .day, value: -daysBack, to: today) else { return }

        let existingDays = Set(store.netWorthSnapshots.map { cal.startOfDay(for: $0.date) })
        guard !accounts.isEmpty else { return }

        // Pre-sort each account's transactions desc ONCE. Cold 365-day
        // backfill is O(days × totalTxns) without this; O(totalTxns log +
        // days × avgAfterCutoff) with.
        let sortedCache = sortedDescTxnCache(for: accounts, allTxns: store.transactions)

        var day = earliestWanted
        while day <= today {
            if !existingDays.contains(day) {
                writeSnapshot(on: day, source: .backfill, accounts: accounts, sortedTxnsCache: sortedCache, store: &store)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
    }

    /// Destructive: wipes every snapshot, then rebuilds a `daysBack`-day
    /// daily timeline from scratch.
    static func rebuildHistory(store: inout Store, accounts: [Account], daysBack: Int? = nil) {
        let daysBack = daysBack ?? effectiveBackfillDays
        store.netWorthSnapshots.removeAll()

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -daysBack, to: today) else { return }
        guard !accounts.isEmpty else { return }

        let sortedCache = sortedDescTxnCache(for: accounts, allTxns: store.transactions)

        var day = start
        while day <= today {
            let source: NetWorthSnapshot.SnapshotSource = (day == today) ? .rebuild : .backfill
            writeSnapshot(on: day, source: source, accounts: accounts, sortedTxnsCache: sortedCache, store: &store)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
    }

    // MARK: - Core write

    /// Writes one `NetWorthSnapshot` for the given calendar day. Caller is
    /// responsible for idempotency checks (see `tick` / `backfillIfNeeded`).
    private static func writeSnapshot(
        on day: Date,
        source: NetWorthSnapshot.SnapshotSource,
        accounts: [Account],
        sortedTxnsCache: [UUID: [Transaction]]?,
        store: inout Store
    ) {
        let active = accounts.filter { !$0.isArchived }
        guard !active.isEmpty else { return }

        var totalAssetsCents = 0
        var totalLiabCents = 0

        for account in active {
            let cached = sortedTxnsCache?[account.id]
            let balanceCents = historicalBalanceCents(
                for: account,
                on: day,
                sortedTxnsDesc: cached,
                allTxns: store.transactions
            )
            if account.type.isLiability {
                totalLiabCents += abs(balanceCents)
            } else {
                totalAssetsCents += balanceCents
            }
        }

        let snapshot = NetWorthSnapshot(
            date: day,
            totalAssets: totalAssetsCents,
            totalLiabilities: totalLiabCents,
            source: source
        )
        store.netWorthSnapshots.append(snapshot)
    }

    // MARK: - Historical math

    /// Reconstructs an account's balance (cents) on `day` by unwinding
    /// every transaction dated AFTER `day` from the live `currentBalance`.
    /// Current-day calls become a no-op and return `currentBalance`.
    ///
    /// Pass `sortedTxnsDesc` (date descending) when calling in a loop —
    /// backfill/rebuild walk D days × A accounts and re-filtering the
    /// entire transaction array every iteration was the single biggest
    /// cost on macOS. With desc-sorted cache, this becomes linear with
    /// early exit at `cutoff`.
    private static func historicalBalanceCents(
        for account: Account,
        on day: Date,
        sortedTxnsDesc: [Transaction]?,
        allTxns: [Transaction]
    ) -> Int {
        let cutoff = Calendar.current.startOfDay(for: day)
        var delta = 0
        if let sorted = sortedTxnsDesc {
            for t in sorted {
                if t.date <= cutoff { break }
                delta += t.type == .income ? t.amount : -t.amount
            }
        } else {
            for t in allTxns where t.accountId == account.id && t.date > cutoff {
                delta += t.type == .income ? t.amount : -t.amount
            }
        }
        let liveCents = Int((account.currentBalance * 100).rounded())
        return liveCents - delta
    }

    /// Per-account transactions sorted desc by date. Built once per
    /// backfill/rebuild pass.
    private static func sortedDescTxnCache(for accounts: [Account], allTxns: [Transaction]) -> [UUID: [Transaction]] {
        var byAccount: [UUID: [Transaction]] = [:]
        byAccount.reserveCapacity(accounts.count)
        for tx in allTxns {
            guard let aid = tx.accountId else { continue }
            byAccount[aid, default: []].append(tx)
        }
        for aid in byAccount.keys {
            byAccount[aid]?.sort { $0.date > $1.date }
        }
        return byAccount
    }

    // MARK: - Helpers

    private static func snapshotExists(on day: Date, in store: Store) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return false }
        return store.netWorthSnapshots.contains { $0.date >= start && $0.date < end }
    }

    private static func deleteSnapshots(on day: Date, store: inout Store) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        store.netWorthSnapshots.removeAll { $0.date >= start && $0.date < end }
    }
}
