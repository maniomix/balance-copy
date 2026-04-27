import Foundation

// ============================================================
// MARK: - Review Queue Service (Phase 6b — iOS port)
// ============================================================
//
// Central producer of `ReviewQueueItem`s surfaced by the Review Queue.
// Fetches each collection from Store exactly once, passes the
// snapshot to every detector via `ReviewQueueContext`, and lets
// detectors filter + group in memory.
//
// Ported from macOS Centmond. Adaptations:
//   - Reads from `Store` instead of SwiftData `ModelContext`
//   - Dismissals persist in `Store.dismissedReviewKeys` instead of
//     a `DismissedDetection` @Model table
//   - All iOS recurring templates are expense-only
// ============================================================

enum ReviewQueueService {

    // MARK: - Tunables

    /// Keep any one reason from drowning the hub.
    static let perReasonCap = 50

    // MARK: - Entry point

    /// Build the full queue from the current store. Sorted by severity
    /// (blocker first) → sortDate (newest first) → amount magnitude
    /// (largest first), then capped per-reason. Muted reasons and
    /// dismissed keys are filtered out.
    @MainActor
    static func buildQueue(in store: Store) -> [ReviewQueueItem] {
        let ctx = ReviewQueueContext.load(from: store)

        var items: [ReviewQueueItem] = []
        items.reserveCapacity(256)
        items.append(contentsOf: ReviewDetectors.rowLocal(ctx: ctx))
        items.append(contentsOf: ReviewDetectors.duplicateCandidate(ctx: ctx))
        items.append(contentsOf: ReviewDetectors.unusualAmount(ctx: ctx))
        items.append(contentsOf: ReviewDetectors.unlinkedSubscription(ctx: ctx))

        let muted = ReviewQueueTelemetry.shared.mutedReasons
        let filtered = items.filter {
            !ctx.dismissedKeys.contains($0.dismissalKey) && !muted.contains($0.reason)
        }
        return capped(sorted(filtered))
    }

    @MainActor
    static func counts(in store: Store) -> [ReviewReasonCode: Int] {
        let queue = buildQueue(in: store)
        return Dictionary(grouping: queue, by: \.reason).mapValues(\.count)
    }

    // MARK: - Dismissal

    /// Persist a dismissal so the item stops surfacing. Bumps the weekly
    /// "resolved" counter via `ReviewQueueTelemetry`.
    @MainActor
    static func dismiss(_ item: ReviewQueueItem, in store: inout Store) {
        let key = item.dismissalKey
        if !store.dismissedReviewKeys.contains(key) {
            store.dismissedReviewKeys.append(key)
        }
        ReviewQueueTelemetry.shared.recordResolved()
    }

    static func undismiss(_ item: ReviewQueueItem, in store: inout Store) {
        let key = item.dismissalKey
        store.dismissedReviewKeys.removeAll { $0 == key }
    }

    // MARK: - Pipeline helpers

    private static func sorted(_ items: [ReviewQueueItem]) -> [ReviewQueueItem] {
        items.sorted { a, b in
            if a.severity != b.severity { return a.severity > b.severity }
            if a.sortDate != b.sortDate { return a.sortDate > b.sortDate }
            return a.amountMagnitude > b.amountMagnitude
        }
    }

    private static func capped(_ items: [ReviewQueueItem]) -> [ReviewQueueItem] {
        var perReason: [ReviewReasonCode: Int] = [:]
        var out: [ReviewQueueItem] = []
        out.reserveCapacity(items.count)
        for item in items {
            let used = perReason[item.reason, default: 0]
            guard used < perReasonCap else { continue }
            perReason[item.reason] = used + 1
            out.append(item)
        }
        return out
    }
}

// MARK: - Shared snapshot

/// Single pre-fetched snapshot fed to every detector so `buildQueue`
/// reads each Store collection exactly once per call. Detectors treat
/// it as read-only.
struct ReviewQueueContext {
    let now: Date
    let transactions: [Transaction]
    let aiSubscriptions: [AISubscription]
    let activeTemplates: [RecurringTransaction]
    let dismissedKeys: Set<String>

    static func load(from store: Store) -> ReviewQueueContext {
        let txns = store.transactions.sorted { $0.date > $1.date }
        let activeTemplates = store.recurringTransactions.filter { $0.isActive }
        return ReviewQueueContext(
            now: Date(),
            transactions: txns,
            aiSubscriptions: store.aiSubscriptions,
            activeTemplates: activeTemplates,
            dismissedKeys: Set(store.dismissedReviewKeys)
        )
    }
}
