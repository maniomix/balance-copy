import Foundation

// ============================================================
// MARK: - Review Queue Insight Detectors (Phase 6b — iOS port)
// ============================================================
//
// Emits insights when the Review Queue grows past engagement
// thresholds or accumulates blockers. Namespaced dedupe keys under
// "review:" so dismissals stay siloed per the shared-key convention.
//
// Ported from macOS Centmond. Adapts to iOS `AIInsight` API
// (uses `type:` + `body:` instead of macOS's `kind:` + `warning:`,
// with macOS-compat aliases added in Phase 2).
// ============================================================

enum ReviewQueueInsightDetectors {

    /// Aggregate entry — wire into `AIInsightEngine.refresh(store:)`.
    @MainActor
    static func all(store: Store) -> [AIInsight] {
        var out: [AIInsight] = []
        let queue = ReviewQueueService.buildQueue(in: store)
        out.append(contentsOf: backlog(queue: queue))
        out.append(contentsOf: blockers(queue: queue))
        return out
    }

    /// Fires when the queue balloons past 15 items — implies the user is
    /// ignoring review entirely, which silently distorts budget + runway.
    private static func backlog(queue: [ReviewQueueItem]) -> [AIInsight] {
        let threshold = 15
        guard queue.count >= threshold else { return [] }
        return [AIInsight(
            type: .patternDetected,
            title: "Review queue is piling up",
            body: "\(queue.count) items are waiting for review. Uncategorized rows skew budget totals and runway projections.",
            severity: .warning,
            advice: "Open the Review Queue and triage — most items take a single tap.",
            cause: "Items flagged by Review Queue detectors but not yet accepted or dismissed.",
            dedupeKey: "review:backlog",
            deeplink: .reviewQueue
        )]
    }

    /// Fires when ≥1 blocker-severity item exists. Blockers (missing
    /// account, unlinked subscription) silently break math, so they
    /// surface even with a small overall queue.
    private static func blockers(queue: [ReviewQueueItem]) -> [AIInsight] {
        let blockerItems = queue.filter { $0.severity == .blocker }
        guard !blockerItems.isEmpty else { return [] }
        let count = blockerItems.count
        let title = count == 1 ? "1 review-queue blocker" : "\(count) review-queue blockers"
        return [AIInsight(
            type: .cashflowRisk,
            title: title,
            body: "Blockers leave transactions out of balance and distort net-worth math. Resolve them before trusting the numbers.",
            severity: .critical,
            advice: "Open the Review Queue and filter by the blocker reason.",
            cause: "Items with structural issues (missing account, unlinked subscription).",
            dedupeKey: "review:blockers",
            deeplink: .reviewQueue
        )]
    }
}
