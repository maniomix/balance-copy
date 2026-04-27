import Foundation

// ============================================================
// MARK: - AISubscription Reconciliation Service (Phase 3b — iOS port)
// ============================================================
//
// Links incoming `Transaction` rows to active `AISubscription` records,
// mints `AISubscriptionCharge` rows for matches, advances each
// subscription's `nextPaymentDate`, flags price hikes and duplicate
// charges. Ported from macOS Centmond, adapted to the Store struct
// (passed as `inout`) instead of SwiftData `ModelContext`.
//
// Three modes:
//   1. `reconcile(transaction:in:)` — single-row hook fired right after
//      a Transaction is inserted (NewTransactionSheet, AIActionExecutor,
//      ReceiptScanner). Cheap; touches at most one subscription.
//   2. `reconcileAll(in:)` — bulk pass over every active subscription
//      against every unlinked recent transaction. Used after CSV import
//      and as a manual "rescan". O(subs × txns) but both sets stay small.
//   3. `reconcile(subscription:in:)` — focused pass for one sub, used by
//      the detail view "rescan" button.
//
// Separate from `SubscriptionDetector` because they solve different
// problems: detection invents candidates from raw history; reconciliation
// links NEW transactions to ALREADY-confirmed aiSubscriptions.
// ============================================================

enum SubscriptionReconciliationService {

    // Tuning knobs. Same values as macOS; change the number, not the algorithm.
    static let amountTolerancePct: Double = 0.10         // ±10% of stored amount
    static let priceHikeThreshold: Double = 0.05         // > 5% delta = price change
    static let duplicateWindowFraction: Double = 1.0/3   // dup if within cadence/3 of prior charge
    static let recentWindowDays: Int = 120

    // MARK: - Single-transaction hook

    /// Try to link `transaction` to one active subscription. Idempotent —
    /// safe to call twice; the linked-charge guard skips if a charge already
    /// references this transaction id. Returns the matched AISubscription id.
    @discardableResult
    static func reconcile(
        transaction: Transaction,
        in store: inout Store
    ) -> UUID? {
        guard transaction.type == .expense, !transaction.isTransfer else { return nil }
        guard !isAlreadyLinked(transactionID: transaction.id, in: store) else { return nil }

        let subs = activeSubscriptions(in: store)
        guard let matchIdx = bestMatchIndex(for: transaction, among: subs, in: store) else { return nil }
        applyMatch(transaction: transaction, toSubscriptionAt: matchIdx, in: &store)
        return store.aiSubscriptions[matchIdx].id
    }

    // MARK: - Bulk rescan

    static func reconcileAll(in store: inout Store) {
        guard !activeSubscriptions(in: store).isEmpty else { return }
        let candidates = unlinkedRecentTransactions(in: store)
        for tx in candidates {
            let subs = activeSubscriptions(in: store)
            guard let matchIdx = bestMatchIndex(for: tx, among: subs, in: store) else { continue }
            applyMatch(transaction: tx, toSubscriptionAt: matchIdx, in: &store)
        }
    }

    // MARK: - Per-subscription rescan

    static func reconcile(subscriptionId: UUID, in store: inout Store) {
        guard let idx = store.aiSubscriptions.firstIndex(where: { $0.id == subscriptionId }) else { return }
        let sub = store.aiSubscriptions[idx]
        guard sub.status == .active || sub.status == .trial else { return }
        let candidates = unlinkedRecentTransactions(in: store)
        for tx in candidates where matches(transaction: tx, subscription: sub) {
            applyMatch(transaction: tx, toSubscriptionAt: idx, in: &store)
        }
    }

    // MARK: - Matching

    /// Returns the index (into `store.aiSubscriptions`) of the subscription
    /// whose `nextPaymentDate` is closest to the transaction date. Indexing
    /// (not the AISubscription itself) because iOS subs live in a struct array
    /// and we need to mutate through the index.
    private static func bestMatchIndex(
        for tx: Transaction,
        among subs: [AISubscription],
        in store: Store
    ) -> Int? {
        let candidates = subs.filter { matches(transaction: tx, subscription: $0) }
        guard !candidates.isEmpty else { return nil }
        let chosen = candidates.min {
            distance(tx.date, $0.nextPaymentDate) < distance(tx.date, $1.nextPaymentDate)
        }
        guard let chosen else { return nil }
        return store.aiSubscriptions.firstIndex(where: { $0.id == chosen.id })
    }

    private static func matches(transaction tx: Transaction, subscription sub: AISubscription) -> Bool {
        guard merchantMatches(tx.note, sub: sub) else { return false }
        guard amountMatches(tx.amount, sub.amount) else { return false }
        guard dateInWindow(tx.date, sub: sub) else { return false }
        return true
    }

    /// Matches a transaction note (iOS's merchant field) against a
    /// subscription's `merchantKey`. Falls back to deriving the key from
    /// `sub.serviceName` for legacy rows that predate Phase 3a.
    private static func merchantMatches(_ note: String, sub: AISubscription) -> Bool {
        let txKey = AISubscription.merchantKey(for: note)
        guard !txKey.isEmpty else { return false }
        let subKey = sub.merchantKey.isEmpty
            ? AISubscription.merchantKey(for: sub.serviceName)
            : sub.merchantKey
        guard !subKey.isEmpty else { return false }
        if txKey == subKey { return true }
        // Fuzzy: one contains the other — catches "Netflix" vs "NETFLIX 12345".
        if txKey.contains(subKey) || subKey.contains(txKey) { return true }
        return false
    }

    private static func amountMatches(_ txAmount: Int, _ subAmount: Int) -> Bool {
        guard subAmount > 0 else { return false }
        let tx = Double(txAmount)
        let base = Double(subAmount)
        let delta = abs(tx - base) / base
        // Generous tolerance — price hikes inside threshold still "match",
        // they just trigger the price-change side effect.
        return delta <= max(amountTolerancePct, priceHikeThreshold * 4)
    }

    /// A charge counts as a match when its date is within ½ cadence of
    /// `nextPaymentDate` OR within ½ cadence of `lastChargeDate + 1 cycle`.
    /// Two windows because users log historical transactions out of order
    /// and we still want those linked.
    private static func dateInWindow(_ date: Date, sub: AISubscription) -> Bool {
        let cadence = max(sub.effectiveCadenceDays, 1)
        let halfWindow = max(cadence / 2, 3)
        let cal = Calendar.current

        let nextDelta = abs(cal.dateComponents([.day], from: date, to: sub.nextPaymentDate).day ?? Int.max)
        if nextDelta <= halfWindow { return true }

        if let last = sub.lastChargeDate,
           let projectedFromLast = advance(last, cycle: sub.billingCycle, customDays: sub.customCadenceDays) {
            let lastDelta = abs(cal.dateComponents([.day], from: date, to: projectedFromLast).day ?? Int.max)
            if lastDelta <= halfWindow { return true }
        }
        return false
    }

    // MARK: - Apply

    private static func applyMatch(
        transaction tx: Transaction,
        toSubscriptionAt idx: Int,
        in store: inout Store
    ) {
        let sub = store.aiSubscriptions[idx]

        let isDup = isDuplicateInCadenceWindow(date: tx.date, subscriptionId: sub.id, in: store)

        let charge = AISubscriptionCharge(
            subscriptionId: sub.id,
            date: tx.date,
            amount: tx.amount,
            currency: sub.currency,
            transactionId: tx.id,
            matchedAutomatically: true,
            matchConfidence: 0.85,
            notes: nil,
            isFlaggedDuplicate: isDup
        )
        store.aiSubscriptionCharges.append(charge)

        // Detect price change BEFORE mutating amount so the pre-change
        // baseline is captured. Threshold-gated to avoid rounding noise.
        let oldAmount = sub.amount
        let newAmount = tx.amount
        if oldAmount > 0 {
            let delta = Double(newAmount - oldAmount) / Double(oldAmount)
            if abs(delta) >= priceHikeThreshold {
                let change = AISubscriptionPriceChange(
                    subscriptionId: sub.id,
                    observedAt: tx.date,
                    oldAmount: oldAmount,
                    newAmount: newAmount
                )
                store.aiSubscriptionPriceChanges.append(change)
                store.aiSubscriptions[idx].amount = newAmount
            }
        }

        // Dates + housekeeping
        if store.aiSubscriptions[idx].firstChargeDate == nil {
            store.aiSubscriptions[idx].firstChargeDate = tx.date
        }
        store.aiSubscriptions[idx].lastChargeDate = tx.date
        if store.aiSubscriptions[idx].merchantKey.isEmpty {
            store.aiSubscriptions[idx].merchantKey = AISubscription.merchantKey(for: sub.serviceName)
        }

        if let projected = advance(tx.date, cycle: sub.billingCycle, customDays: sub.customCadenceDays) {
            // Only move forward — never set nextPaymentDate to the past
            // because a back-dated import landed.
            if projected > store.aiSubscriptions[idx].nextPaymentDate {
                store.aiSubscriptions[idx].nextPaymentDate = projected
            }
        }
        store.aiSubscriptions[idx].updatedAt = Date()
    }

    private static func isDuplicateInCadenceWindow(
        date: Date,
        subscriptionId: UUID,
        in store: Store
    ) -> Bool {
        guard let sub = store.aiSubscriptions.first(where: { $0.id == subscriptionId }) else { return false }
        let cadence = max(sub.effectiveCadenceDays, 1)
        let dupWindow = max(Int(Double(cadence) * duplicateWindowFraction), 1)
        let cal = Calendar.current
        let priorCharges = store.aiSubscriptionCharges.filter { $0.subscriptionId == subscriptionId }
        for prior in priorCharges {
            let delta = abs(cal.dateComponents([.day], from: date, to: prior.date).day ?? Int.max)
            if delta <= dupWindow { return true }
        }
        return false
    }

    // MARK: - Fetch helpers

    private static func activeSubscriptions(in store: Store) -> [AISubscription] {
        store.aiSubscriptions.filter { $0.status == .active || $0.status == .trial }
    }

    private static func isAlreadyLinked(transactionID: UUID, in store: Store) -> Bool {
        store.aiSubscriptionCharges.contains { $0.transactionId == transactionID }
    }

    /// Recent (≤ `recentWindowDays`), unlinked expense transactions sorted by
    /// date. Window-limited so a multi-year import doesn't try to back-link
    /// ancient rows we'd treat as duplicates.
    private static func unlinkedRecentTransactions(in store: Store) -> [Transaction] {
        let linkedIDs = Set(store.aiSubscriptionCharges.compactMap(\.transactionId))
        let cutoff = Calendar.current.date(byAdding: .day, value: -recentWindowDays, to: Date()) ?? .distantPast
        return store.transactions
            .filter { $0.type == .expense && !$0.isTransfer && $0.date >= cutoff && !linkedIDs.contains($0.id) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Date math

    private static func advance(_ date: Date, cycle: AIBillingCycle, customDays: Int?) -> Date? {
        let cal = Calendar.current
        switch cycle {
        case .weekly:     return cal.date(byAdding: .weekOfYear, value: 1, to: date)
        case .biweekly:   return cal.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly:    return cal.date(byAdding: .month,      value: 1, to: date)
        case .quarterly:  return cal.date(byAdding: .month,      value: 3, to: date)
        case .semiannual: return cal.date(byAdding: .month,      value: 6, to: date)
        case .annual:     return cal.date(byAdding: .year,       value: 1, to: date)
        case .custom:     return cal.date(byAdding: .day, value: max(customDays ?? 30, 1), to: date)
        }
    }

    private static func distance(_ a: Date, _ b: Date) -> Int {
        abs(Calendar.current.dateComponents([.day], from: a, to: b).day ?? Int.max)
    }
}
