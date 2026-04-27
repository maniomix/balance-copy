import Foundation

// ============================================================
// MARK: - Review Detectors (Phase 6b — iOS port)
// ============================================================
//
// Pure producers of `ReviewQueueItem`s from a pre-fetched `ReviewQueueContext`.
// Every detector reads from the shared snapshot — no Store re-reads —
// so `ReviewQueueService.buildQueue` runs exactly once over each
// collection no matter how many detectors are active.
//
// Ported from macOS Centmond, subset for iOS. Skipped reasons (iOS
// data layer doesn't support them yet):
//   - `pendingTxn` / `staleCleared` — iOS Transaction has no status
//   - `negativeIncome` — iOS amount is always ≥0; direction via `type`
//   - `unreviewedTransfer` — iOS has only `.expense` / `.income`
//   - `unlinkedRecurring` — iOS Transaction has no `recurringTemplateId`
// ============================================================

enum ReviewDetectors {

    // MARK: - Row-local (single pass)

    /// Walks the transaction list ONCE and emits items for every
    /// row-local reason. O(N) instead of one pass per reason.
    static func rowLocal(ctx: ReviewQueueContext) -> [ReviewQueueItem] {
        let now = ctx.now
        var out: [ReviewQueueItem] = []
        out.reserveCapacity(ctx.transactions.count / 4)

        for tx in ctx.transactions {
            // Future-dated — suggested-severity regardless of category.
            if tx.date > now {
                out.append(make(.futureDated, severity: .suggested, for: tx))
            }

            // Uncategorized — iOS Category is non-optional, so we treat
            // `.other` as the "needs a real category" bucket.
            if tx.category.storageKey == "other" {
                out.append(make(.uncategorizedTxn, severity: .suggested, for: tx))
            }

            // Missing account — many iOS rows legitimately have no account
            // (manual cash entries), so this is .low severity not blocker.
            if tx.accountId == nil {
                out.append(make(.missingAccount, severity: .low, for: tx))
            }
        }
        return out
    }

    // MARK: - Duplicate candidate

    /// Same merchant + same amount within a 2-day window → flag both sides.
    /// Bucket by `(note, amount)` so the inner loop only runs on already-
    /// agreeing pairs.
    static func duplicateCandidate(ctx: ReviewQueueContext) -> [ReviewQueueItem] {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -90, to: ctx.now) else { return [] }
        let candidates = ctx.transactions.filter { $0.date > cutoff }
        guard candidates.count >= 2 else { return [] }

        struct Bucket: Hashable { let note: String; let amount: Int }
        let grouped = Dictionary(grouping: candidates) {
            Bucket(note: $0.note.lowercased(), amount: $0.amount)
        }

        let window: TimeInterval = 2 * 24 * 60 * 60
        var flagged = Set<UUID>()
        var out: [ReviewQueueItem] = []

        for (_, rows) in grouped where rows.count >= 2 {
            let sorted = rows.sorted { $0.date < $1.date }
            for i in sorted.indices {
                let tx = sorted[i]
                var j = i + 1
                while j < sorted.count,
                      sorted[j].date.timeIntervalSince(tx.date) <= window {
                    let other = sorted[j]
                    for candidate in [tx, other] where flagged.insert(candidate.id).inserted {
                        out.append(make(.duplicateCandidate, severity: .suggested, for: candidate))
                    }
                    j += 1
                }
            }
        }
        return out
    }

    // MARK: - Unusual amount

    /// Per-merchant outlier: amount > 6× the merchant's recent median,
    /// with ≥5 prior samples in the 180-day window.
    static func unusualAmount(ctx: ReviewQueueContext) -> [ReviewQueueItem] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -180, to: ctx.now) else { return [] }
        let candidates = ctx.transactions.filter { $0.date > cutoff }
        let byMerchant = Dictionary(grouping: candidates, by: { $0.note.lowercased() })
        var out: [ReviewQueueItem] = []

        for (_, group) in byMerchant where group.count >= 5 {
            let magnitudes = group.map(\.amount).sorted()
            let median = magnitudes[magnitudes.count / 2]
            guard median > 0 else { continue }
            let threshold = median * 6
            for tx in group where tx.amount > threshold {
                out.append(make(.unusualAmount, severity: .suggested, for: tx))
            }
        }
        return out
    }

    // MARK: - Unlinked subscription

    /// Active subscription whose `lastChargeDate` is more than
    /// `cadence + 10 days` in the past — probably missed a charge
    /// or the merchant name changed and reconciliation missed it.
    static func unlinkedSubscription(ctx: ReviewQueueContext) -> [ReviewQueueItem] {
        let now = ctx.now
        var out: [ReviewQueueItem] = []
        for sub in ctx.aiSubscriptions where sub.status == .active {
            guard let last = sub.lastChargeDate else { continue }
            let grace = sub.effectiveCadenceDays + 10
            let daysSince = Calendar.current.dateComponents([.day], from: last, to: now).day ?? 0
            guard daysSince > grace else { continue }
            out.append(ReviewQueueItem(
                id: UUID(),
                reason: .unlinkedSubscription,
                severity: .suggested,
                transactionId: nil,
                recurringTemplateId: nil,
                subscriptionId: sub.id,
                dedupeKey: "unlinkedSubscription:\(sub.id.uuidString)",
                sortDate: last,
                amountMagnitude: sub.amount
            ))
        }
        return out
    }

    // MARK: - Factory

    /// Standardized transaction-bound item builder. Callers pass only
    /// reason + severity + the transaction.
    @inline(__always)
    private static func make(
        _ reason: ReviewReasonCode,
        severity: ReviewSeverity,
        for tx: Transaction
    ) -> ReviewQueueItem {
        ReviewQueueItem(
            id: UUID(),
            reason: reason,
            severity: severity,
            transactionId: tx.id,
            recurringTemplateId: nil,
            subscriptionId: nil,
            dedupeKey: "\(reason.rawValue):\(tx.id.uuidString)",
            sortDate: tx.date,
            amountMagnitude: tx.amount
        )
    }
}
