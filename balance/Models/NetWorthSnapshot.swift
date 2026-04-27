import Foundation

// ============================================================
// MARK: - Net Worth Snapshot (Phase 4c — iOS port)
// ============================================================
//
// A point-in-time aggregate of the user's net worth. Written by
// `NetWorthHistoryService` on launch / scene-active / midnight,
// plus on-demand ("Snapshot now") and during historical backfill.
//
// Standalone aggregate — no reference to Account — so archiving
// or deleting an account does not retroactively rewrite history.
//
// Ported from macOS Centmond as a Codable struct stored on Store;
// amounts are Int cents (iOS convention) instead of Decimal.
// ============================================================

struct NetWorthSnapshot: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var totalAssets: Int            // cents
    var totalLiabilities: Int       // cents (stored as positive magnitude)
    var netWorth: Int               // cents (assets − liabilities)
    var source: SnapshotSource
    let createdAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        totalAssets: Int,
        totalLiabilities: Int,
        source: SnapshotSource = .auto,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.totalAssets = totalAssets
        self.totalLiabilities = totalLiabilities
        self.netWorth = totalAssets - totalLiabilities
        self.source = source
        self.createdAt = createdAt
    }

    enum SnapshotSource: String, Codable, CaseIterable {
        case auto         // scheduled (launch/midnight)
        case manual       // user tapped "Snapshot now"
        case backfill     // derived from transaction history
        case rebuild      // destructive rebuild action
    }
}
