import Foundation
import SwiftUI
import Combine

// ============================================================
// MARK: - Subscription Detection Engine
// ============================================================
//
// Deterministic subscription detection from transaction history.
//
// Detection Strategy (all rules are transparent & explainable):
//
// 1. Group transactions by normalized merchant name
// 2. For each merchant group:
//    a. Check for regularity (consistent intervals: 7d, 30d, 365d)
//    b. Check for amount similarity (charges within 15% of median)
//    c. Require minimum 2 occurrences to flag
//    d. Assign confidence score based on match quality
// 3. Produce insight labels:
//    - Price increase: last charge > previous by >2%
//    - Upcoming renewal: within 7 days
//    - Maybe unused: >60 days without non-subscription transactions in same category
//    - Duplicate risk: multiple subscriptions in same category with similar amounts
//    - Missed charge: expected charge didn't appear within ±5 days of expected date
//
// ============================================================

@MainActor
class SubscriptionEngine: ObservableObject {

    static let shared = SubscriptionEngine()

    @Published var subscriptions: [DetectedSubscription] = []
    @Published var insights: [SubscriptionInsight] = []
    @Published var isLoading = false
    @Published var lastAnalyzedAt: Date?

    // Summary stats
    @Published var monthlyTotal: Int = 0
    @Published var yearlyTotal: Int = 0
    @Published var activeCount: Int = 0

    /// Single durable container. Replaces the three legacy UserDefaults
    /// keys. `analyze()` merges into `snapshot.records` rather than
    /// rebuilding the in-memory list, so user edits survive re-detection.
    private var snapshot: SubscriptionStoreSnapshot = SubscriptionStoreSnapshot()

    /// Signature of the last input we analyzed. Used to skip the (expensive)
    /// detection pass when called repeatedly with the same transactions —
    /// e.g. dashboard `.onAppear` followed by month-switch `.onChange` on
    /// the same data. Reset to `nil` on snapshot mutation paths that
    /// require re-analysis (none today; user edits flow through transactions).
    private var lastAnalyzedSignature: Int?

    /// Read-only window onto manual records. Kept for the few call sites
    /// that want "user-added subs only" without filtering themselves.
    var manualSubscriptions: [DetectedSubscription] {
        snapshot.records.filter { $0.source == .manual }
    }

    /// All hidden subscription records — exposed so the upcoming Phase 4
    /// "Hidden" section can render them.
    var hiddenSubscriptions: [DetectedSubscription] {
        snapshot.records.filter { snapshot.hiddenKeys.contains($0.merchantKey) }
    }

    private init() {
        if let migrated = SubscriptionStorePersistence.migrateLegacyIfPresent() {
            snapshot = migrated
        } else if let loaded = SubscriptionStorePersistence.load() {
            snapshot = loaded
        }
    }

    private func saveSnapshot() {
        SubscriptionStorePersistence.save(snapshot)
    }

    // MARK: - Manual Add / Remove

    @discardableResult
    func addManualSubscription(
        merchantName: String,
        category: Category,
        amountCents: Int,
        billingCycle: BillingCycle,
        nextRenewalDate: Date?,
        notes: String = ""
    ) -> DetectedSubscription {
        let key = DetectedSubscription.merchantKey(for: merchantName)

        // If a record already exists for this merchant key, treat the manual
        // add as an upgrade-in-place: flip source to .manual, fill in the
        // user-supplied amount/cycle/category, unhide.
        if let idx = snapshot.records.firstIndex(where: { $0.merchantKey == key }) {
            snapshot.records[idx].source = .manual
            snapshot.records[idx].merchantName = merchantName
            snapshot.records[idx].category = category
            snapshot.records[idx].expectedAmount = amountCents
            snapshot.records[idx].lastAmount = amountCents
            snapshot.records[idx].billingCycle = billingCycle
            snapshot.records[idx].nextRenewalDate = nextRenewalDate
            snapshot.records[idx].notes = notes
            snapshot.records[idx].status = .active
            snapshot.records[idx].userEditedStatus = true
            snapshot.records[idx].updatedAt = Date()
            snapshot.hiddenKeys.remove(key)
            saveSnapshot()
            republish()
            return snapshot.records[idx]
        }

        let sub = DetectedSubscription(
            merchantName: merchantName,
            merchantKey: key,
            category: category,
            expectedAmount: amountCents,
            lastAmount: amountCents,
            billingCycle: billingCycle,
            nextRenewalDate: nextRenewalDate,
            lastChargeDate: nil,
            status: .active,
            source: .manual,
            linkedTransactionIds: [],
            notes: notes,
            userEditedStatus: true,
            isAutoDetected: false,
            confidenceScore: 1.0,
            chargeHistory: []
        )
        snapshot.records.append(sub)
        saveSnapshot()
        republish()
        return sub
    }

    func removeManualSubscription(_ sub: DetectedSubscription) {
        snapshot.records.removeAll { $0.id == sub.id }
        saveSnapshot()
        republish()
    }

    // MARK: - Main Analysis

    /// Detect subscriptions from transactions and merge the result into the
    /// durable `snapshot.records`. Existing records are updated in place
    /// (charge history, last/next dates, confidence) while user-edited
    /// fields (status when `userEditedStatus`, notes, manual category) are
    /// preserved. Recurring-transaction-sourced records are reconciled too:
    /// orphaned ones (no longer in `store.recurringTransactions`) get
    /// pruned unless the user has edited them.
    func analyze(store: Store) async {
        let signature = store.transactionsSignature
        if signature == lastAnalyzedSignature { return }

        isLoading = true

        let transactions = store.transactions

        let detected = await Task.detached(priority: .userInitiated) {
            Self.detect(transactions: transactions, existingManual: [])
        }.value

        let recurringCandidates = Self.recurringCandidates(from: store.recurringTransactions)

        mergeDetected(detected)
        mergeRecurring(recurringCandidates)
        consumeLegacyStatusOverrides()

        self.insights = computeGlobalInsights()
        self.lastAnalyzedAt = Date()
        saveSnapshot()
        republish()
        self.isLoading = false
        self.lastAnalyzedSignature = signature
    }

    /// Re-derive the global insight list from the post-merge snapshot.
    /// Detection's `globalInsights` only sees auto-detected candidates;
    /// running this after merge means user-paused / hidden / manual rows
    /// are factored in correctly.
    private func computeGlobalInsights() -> [SubscriptionInsight] {
        // Hide model retired — every record is visible. (`hiddenKeys`
        // is cleared in republish; this filter is now a no-op but the
        // local var keeps the rest of the function unchanged.)
        let visible = snapshot.records
        var out: [SubscriptionInsight] = []

        if visible.contains(where: { $0.hasPriceIncrease && $0.status == .active }) {
            out.append(.priceIncreased)
        }
        if visible.contains(where: { sub in
            guard sub.status == .active, let d = sub.daysUntilRenewal else { return false }
            return d >= 0 && d <= 7
        }) {
            out.append(.upcomingRenewal)
        }
        if visible.contains(where: { $0.status == .suspectedUnused }) {
            out.append(.maybeUnused)
        }
        if visible.contains(where: { $0.hasMissedCharge }) {
            out.append(.missedCharge)
        }

        // Duplicate risk: same category + similar name OR similar amount.
        let active = visible.filter { $0.status == .active }
        outer: for i in 0..<active.count {
            for j in (i+1)..<active.count where active[i].category == active[j].category {
                let diff = abs(active[i].expectedAmount - active[j].expectedAmount)
                // Phase 3: amount band tightened 40% → 20%. Pairs with the
                // stricter token-set name match in `merchantNamesSimilar`.
                let threshold = max(active[i].expectedAmount, active[j].expectedAmount) / 5
                if diff <= threshold || Self.merchantNamesSimilar(active[i].merchantName, active[j].merchantName) {
                    out.append(.duplicateRisk)
                    break outer
                }
            }
        }

        if visible.contains(where: { $0.chargeHistory.count <= 3 && $0.isAutoDetected && $0.status == .active }) {
            out.append(.newlyDetected)
        }
        return out
    }

    // MARK: - Merge

    /// Apply detected candidates to the durable snapshot. New keys insert
    /// fresh `.detected` records; existing keys update charge history /
    /// dates / confidence while preserving user edits.
    private func mergeDetected(_ candidates: [DetectedSubscription]) {
        for candidate in candidates {
            let key = candidate.merchantKey.isEmpty
                ? DetectedSubscription.merchantKey(for: candidate.merchantName)
                : candidate.merchantKey
            if let idx = snapshot.records.firstIndex(where: { $0.merchantKey == key }) {
                applyDetectedUpdate(candidate, into: &snapshot.records[idx])
            } else {
                var record = candidate
                record.merchantKey = key
                record.source = .detected
                snapshot.records.append(record)
            }
        }
    }

    /// Merge logic for detected candidates onto an existing record.
    /// Detection-derived fields (charge history, dates, confidence,
    /// linked tx ids, last amount) are refreshed every analyze.
    /// User-controlled fields are preserved.
    private func applyDetectedUpdate(_ candidate: DetectedSubscription, into existing: inout DetectedSubscription) {
        // If a new charge has landed since we last looked, clear any
        // "still using it" dismissal — the user actually IS using it,
        // and we want suspectedUnused to be able to fire again later if
        // they go idle for two cycles in a row.
        if let newLast = candidate.lastChargeDate,
           let oldLast = existing.lastChargeDate,
           newLast > oldLast {
            existing.dismissedSuspectedUnused = false
        }

        existing.expectedAmount = candidate.expectedAmount
        existing.lastAmount = candidate.lastAmount
        existing.lastChargeDate = candidate.lastChargeDate
        existing.confidenceScore = candidate.confidenceScore
        existing.detectedIntervalDays = candidate.detectedIntervalDays
        existing.linkedTransactionIds = candidate.linkedTransactionIds
        existing.chargeHistory = candidate.chargeHistory
        existing.detectionRationale = candidate.detectionRationale
        // Renewal date: detection re-derives this each cycle. Honor it
        // unless the user manually overrode the cycle (manual source).
        if existing.source != .manual {
            existing.nextRenewalDate = candidate.nextRenewalDate
            existing.billingCycle = candidate.billingCycle
        }
        // Status: only auto-update when the user hasn't taken control.
        // Also: respect the suspected-unused dismissal — if detection
        // would have flagged it again, keep the prior status instead.
        if !existing.userEditedStatus {
            if candidate.status == .suspectedUnused && existing.dismissedSuspectedUnused {
                existing.status = .active
            } else {
                existing.status = candidate.status
            }
        }
        existing.updatedAt = Date()
    }

    /// Merge recurring-transaction-sourced candidates and prune orphans.
    /// A record with `source == .recurring` whose merchantKey is no longer
    /// present in the recurring set is removed (unless the user edited it,
    /// in which case it gets promoted to `.manual` so the edits survive).
    private func mergeRecurring(_ candidates: [DetectedSubscription]) {
        let liveKeys = Set(candidates.map(\.merchantKey))

        // Promote / prune existing .recurring rows.
        var i = 0
        while i < snapshot.records.count {
            let r = snapshot.records[i]
            if r.source == .recurring && !liveKeys.contains(r.merchantKey) {
                if r.userEditedStatus || !r.notes.isEmpty {
                    snapshot.records[i].source = .manual
                    i += 1
                } else {
                    snapshot.records.remove(at: i)
                    continue
                }
            }
            i += 1
        }

        // Insert / update from candidates.
        for candidate in candidates {
            if let idx = snapshot.records.firstIndex(where: { $0.merchantKey == candidate.merchantKey }) {
                // Already covered by detection or prior recurring — keep
                // the existing row; just refresh dates if recurring is
                // the only source.
                if snapshot.records[idx].source == .recurring {
                    snapshot.records[idx].nextRenewalDate = candidate.nextRenewalDate
                    snapshot.records[idx].lastChargeDate = candidate.lastChargeDate
                    snapshot.records[idx].expectedAmount = candidate.expectedAmount
                    if !snapshot.records[idx].userEditedStatus {
                        snapshot.records[idx].status = .active
                    }
                    snapshot.records[idx].updatedAt = Date()
                }
            } else {
                snapshot.records.append(candidate)
            }
        }
    }

    /// One-shot drain of pre-rebuild `statusOverrides` carried in via
    /// migration. Each entry only fires once a matching record exists.
    private func consumeLegacyStatusOverrides() {
        guard !snapshot.legacyStatusOverridesByKey.isEmpty else { return }
        for (key, raw) in snapshot.legacyStatusOverridesByKey {
            guard let status = SubscriptionStatus(rawValue: raw) else {
                snapshot.legacyStatusOverridesByKey.removeValue(forKey: key)
                continue
            }
            if let idx = snapshot.records.firstIndex(where: { $0.merchantKey == key }) {
                snapshot.records[idx].status = status
                snapshot.records[idx].userEditedStatus = true
                snapshot.records[idx].updatedAt = Date()
                snapshot.legacyStatusOverridesByKey.removeValue(forKey: key)
            }
        }
    }

    /// Push the latest filtered records to `@Published subscriptions` and
    /// refresh totals. `republish()` is the only place that touches the
    /// published list — every mutation goes through it. Phase 6a also
    /// reschedules subscription alerts from here so notifications stay
    /// in lockstep with the data without per-call-site wiring.
    private func republish() {
        // Hide-state model retired — show all records. Any leftover
        // hiddenKeys from older versions are cleared in place so the
        // persisted snapshot stops carrying dead state. Save only on
        // the cleanup pass to avoid an extra write on every republish.
        if !snapshot.hiddenKeys.isEmpty {
            snapshot.hiddenKeys.removeAll()
            saveSnapshot()
        }
        let visible = snapshot.records
        // Sort by monthly cost descending to match prior behavior.
        self.subscriptions = visible.sorted { $0.monthlyCost > $1.monthlyCost }
        recalcTotals()
        SubscriptionAlertScheduler.rescheduleAll(records: visible)
    }

    // MARK: - Manual Actions

    func markAsCancelled(_ sub: DetectedSubscription) {
        setStatus(.cancelled, for: sub)
    }

    func markAsPaused(_ sub: DetectedSubscription) {
        setStatus(.paused, for: sub)
    }

    /// Reactivate a subscription. Clears `userEditedStatus` so detection
    /// can take over the status field again, and unhides the merchant.
    func markAsActive(_ sub: DetectedSubscription) {
        guard let idx = snapshot.records.firstIndex(where: { $0.id == sub.id }) else { return }
        snapshot.records[idx].status = .active
        snapshot.records[idx].userEditedStatus = false
        snapshot.records[idx].updatedAt = Date()
        snapshot.hiddenKeys.remove(snapshot.records[idx].merchantKey)
        saveSnapshot()
        republish()
    }

    /// Apply an explicit user status (cancelled/paused) and lock detection
    /// out of overwriting it on the next analyze.
    private func setStatus(_ status: SubscriptionStatus, for sub: DetectedSubscription) {
        guard let idx = snapshot.records.firstIndex(where: { $0.id == sub.id }) else { return }
        snapshot.records[idx].status = status
        snapshot.records[idx].userEditedStatus = true
        snapshot.records[idx].updatedAt = Date()
        saveSnapshot()
        republish()
    }

    func updateNotes(_ sub: DetectedSubscription, notes: String) {
        guard let idx = snapshot.records.firstIndex(where: { $0.id == sub.id }) else { return }
        snapshot.records[idx].notes = notes
        snapshot.records[idx].updatedAt = Date()
        saveSnapshot()
        republish()
    }

    /// Delete a subscription completely — removes the record from
    /// `snapshot.records` and also clears any leftover hidden-key entry
    /// for the same merchant so re-detection isn't suppressed by stale
    /// state from before the hide/unhide model was retired.
    ///
    /// (Replaces the previous hide/unhide pair. The Hidden section in
    /// the UI is gone; users now permanently delete subscriptions
    /// instead of stashing them. Re-detection from transactions can
    /// re-add a deleted sub on the next analyze pass — that's fine.)
    func deleteSubscription(_ sub: DetectedSubscription) {
        snapshot.records.removeAll { $0.id == sub.id }
        snapshot.hiddenKeys.remove(sub.merchantKey)
        saveSnapshot()
        republish()
    }

    /// Legacy alias — kept so any in-flight callers don't break compile.
    /// Will be removed in a follow-up sweep once we confirm nothing
    /// upstream still calls it.
    @available(*, deprecated, message: "Use deleteSubscription(_:) — hide/unhide model retired.")
    func removeSubscription(_ sub: DetectedSubscription) {
        deleteSubscription(sub)
    }

    /// Phase 5a — write an edited record back into the snapshot by id.
    /// Used by the unified Add/Edit sheet when the user saves changes
    /// from the detail view. Recomputes `merchantKey` from the (possibly
    /// new) `merchantName` so the merge logic still finds the row.
    /// Bumps `updatedAt` so the UI refreshes; no re-detection needed.
    func updateSubscription(_ sub: DetectedSubscription) {
        guard let idx = snapshot.records.firstIndex(where: { $0.id == sub.id }) else { return }
        var updated = sub
        updated.merchantKey = DetectedSubscription.merchantKey(for: sub.merchantName)
        updated.updatedAt = Date()
        snapshot.records[idx] = updated
        saveSnapshot()
        republish()
    }

    /// User confirms they're still using a subscription that detection
    /// flagged as "Maybe Unused". Flips the record back to `.active` and
    /// remembers the dismissal so re-detection can't re-flag it until a
    /// new charge clears the flag (handled in `applyDetectedUpdate`).
    func dismissSuspectedUnused(_ sub: DetectedSubscription) {
        guard let idx = snapshot.records.firstIndex(where: { $0.id == sub.id }) else { return }
        snapshot.records[idx].dismissedSuspectedUnused = true
        if snapshot.records[idx].status == .suspectedUnused {
            snapshot.records[idx].status = .active
        }
        snapshot.records[idx].updatedAt = Date()
        saveSnapshot()
        republish()
    }

    private func recalcTotals() {
        monthlyTotal = subscriptions
            .filter { $0.status == .active }
            .reduce(0) { $0 + $1.monthlyCost }
        yearlyTotal = subscriptions
            .filter { $0.status == .active }
            .reduce(0) { $0 + $1.yearlyCost }
        activeCount = subscriptions.filter { $0.status == .active }.count
    }

    // MARK: - Recurring → Subscription Candidates

    /// Build subscription candidates from active RecurringTransactions.
    /// Returned with `source = .recurring` and a stable `merchantKey`.
    /// `mergeRecurring` handles dedup against detected/manual records and
    /// prunes orphans whose recurring transaction was deleted.
    static func recurringCandidates(from recurring: [RecurringTransaction]) -> [DetectedSubscription] {
        recurring.compactMap { rt in
            guard rt.isActive else { return nil }
            let key = DetectedSubscription.merchantKey(for: rt.name)
            guard !key.isEmpty else { return nil }

            let cycle: BillingCycle = {
                switch rt.frequency {
                case .daily: return .custom
                case .weekly: return .weekly
                case .monthly: return .monthly
                case .yearly: return .yearly
                }
            }()

            return DetectedSubscription(
                id: rt.id,
                merchantName: rt.name,
                merchantKey: key,
                category: rt.category,
                expectedAmount: rt.amount,
                lastAmount: rt.amount,
                billingCycle: cycle,
                nextRenewalDate: rt.nextOccurrence(),
                lastChargeDate: rt.lastProcessedDate,
                status: .active,
                source: .recurring,
                linkedTransactionIds: [],
                notes: rt.note,
                isAutoDetected: false,
                confidenceScore: 1.0,
                chargeHistory: []
            )
        }
    }

    // MARK: - Subscriptions by next renewal

    var upcomingRenewals: [DetectedSubscription] {
        subscriptions
            .filter { $0.status == .active && $0.nextRenewalDate != nil }
            .sorted { ($0.nextRenewalDate ?? .distantFuture) < ($1.nextRenewalDate ?? .distantFuture) }
    }

    /// Subscriptions with insights attached
    func insightsFor(_ sub: DetectedSubscription) -> [SubscriptionInsight] {
        var labels: [SubscriptionInsight] = []

        if sub.hasPriceIncrease {
            labels.append(.priceIncreased)
        }
        if let days = sub.daysUntilRenewal, days <= 7, days >= 0 {
            labels.append(.upcomingRenewal)
        }
        if sub.status == .suspectedUnused {
            labels.append(.maybeUnused)
        }
        if sub.hasMissedCharge {
            labels.append(.missedCharge)
        }

        // Duplicate risk: another active subscription in same category with similar name or amount
        let sameCategory = subscriptions.filter {
            $0.id != sub.id &&
            $0.status == .active &&
            $0.category == sub.category
        }
        for other in sameCategory {
            // Check amount similarity (within 20% — tightened in Phase 3)
            let diff = abs(other.expectedAmount - sub.expectedAmount)
            let threshold = max(sub.expectedAmount, other.expectedAmount) / 5
            let amountSimilar = diff <= threshold

            // Check name similarity
            let nameSimilar = Self.merchantNamesSimilar(sub.merchantName, other.merchantName)

            if amountSimilar || nameSimilar {
                labels.append(.duplicateRisk)
                break
            }
        }

        return labels
    }

    // MARK: - Subscription Summaries

    /// Subscriptions with price increases
    var priceIncreasedSubs: [DetectedSubscription] {
        subscriptions.filter { $0.hasPriceIncrease && $0.status == .active }
    }

    /// Subscriptions suspected to be unused
    var unusedSubs: [DetectedSubscription] {
        subscriptions.filter { $0.status == .suspectedUnused }
    }

    /// Subscriptions with missed charges
    var missedChargeSubs: [DetectedSubscription] {
        subscriptions.filter { $0.hasMissedCharge }
    }

    /// Total potential monthly savings from unused + cancelled subscriptions
    var potentialMonthlySavings: Int {
        unusedSubs.reduce(0) { $0 + $1.monthlyCost }
    }

    /// Active subscriptions renewing within N days
    func renewingWithin(days: Int) -> [DetectedSubscription] {
        subscriptions.filter { sub in
            guard sub.status == .active, let d = sub.daysUntilRenewal else { return false }
            return d >= 0 && d <= days
        }.sorted { ($0.daysUntilRenewal ?? 99) < ($1.daysUntilRenewal ?? 99) }
    }

    /// Quick summary snapshot for the dashboard
    var dashboardSnapshot: SubscriptionSnapshot {
        SubscriptionSnapshot(
            activeCount: activeCount,
            monthlyTotal: monthlyTotal,
            yearlyTotal: yearlyTotal,
            renewingSoon: renewingWithin(days: 7).count,
            unusedCount: unusedSubs.count,
            priceIncreaseCount: priceIncreasedSubs.count,
            missedChargeCount: missedChargeSubs.count,
            potentialSavings: potentialMonthlySavings
        )
    }

    /// Check whether two merchant names likely refer to the same service.
    ///
    /// Phase 3 — replaces the old prefix-and-contains heuristic with a
    /// token-set Jaccard ratio. Names are normalized via `merchantKey`
    /// (the same canonicalization the rest of the engine uses), split into
    /// tokens, and compared as sets. Single-token names short-circuit on
    /// equality. The 0.6 threshold drops false positives like
    /// "Apple One" / "Apple Music" (Jaccard ≈ 0.33) while still catching
    /// "Spotify" / "Spotify Premium" (Jaccard ≈ 0.5 → handled by the
    /// subset rule below) and "Adobe Creative Cloud" / "Adobe Cloud"
    /// (Jaccard ≈ 0.67).
    nonisolated static func merchantNamesSimilar(_ a: String, _ b: String) -> Bool {
        let ka = DetectedSubscription.merchantKey(for: a)
        let kb = DetectedSubscription.merchantKey(for: b)
        if ka.isEmpty || kb.isEmpty { return false }
        if ka == kb { return true }

        let ta = Set(ka.split(separator: " ").map(String.init))
        let tb = Set(kb.split(separator: " ").map(String.init))
        guard !ta.isEmpty, !tb.isEmpty else { return false }

        // Subset rule: if every token of the shorter name appears in the
        // longer one (and the shorter has ≥1 token of length ≥4), call it
        // a match. Catches "spotify" ⊂ "spotify premium" without lowering
        // the Jaccard threshold.
        let smaller = ta.count <= tb.count ? ta : tb
        let larger = ta.count <= tb.count ? tb : ta
        if smaller.isSubset(of: larger), smaller.contains(where: { $0.count >= 4 }) {
            return true
        }

        let intersection = ta.intersection(tb).count
        let union = ta.union(tb).count
        let jaccard = Double(intersection) / Double(max(1, union))
        return jaccard >= 0.6
    }

    // MARK: - Pure Detection Logic (off main thread)

    /// Phase 9 — formerly returned a `DetectionResult` wrapper holding the
    /// detected list plus a `globalInsights` array. The insights leg went
    /// dead in Phase 2 once `analyze()` started calling
    /// `computeGlobalInsights()` post-merge, so the wrapper is gone and
    /// `existingManual` (always `[]` since Phase 2) is gone too.
    nonisolated static func detect(
        transactions: [Transaction],
        existingManual: [DetectedSubscription] = []
    ) -> [DetectedSubscription] {
        let cal = Calendar.current
        let now = Date()

        // Only look at expenses
        let expenses = transactions.filter { $0.type == .expense }

        // ─── Step 1: Group by normalized merchant name ───

        let grouped = groupByMerchant(expenses)

        // ─── Step 2: Analyze each group ───

        var detected: [DetectedSubscription] = []

        for (merchant, txs) in grouped {
            guard txs.count >= 2 else { continue }

            // Sort by date ascending
            let sorted = txs.sorted { $0.date < $1.date }

            // ─── Step 2a: Compute intervals between charges ───

            var intervals: [Int] = []
            for i in 1..<sorted.count {
                let days = cal.dateComponents([.day], from: sorted[i-1].date, to: sorted[i].date).day ?? 0
                intervals.append(days)
            }

            guard !intervals.isEmpty else { continue }

            // ─── Step 2b: Detect billing cycle from intervals ───

            let medianInterval = median(intervals)
            let cycle = detectCycle(medianInterval: medianInterval)
            guard let billingCycle = cycle else { continue }

            // ─── Step 2c: Check interval regularity ───
            // Intervals should be within 30% of median to be considered regular

            let regularCount = intervals.filter { interval in
                let deviation = abs(interval - medianInterval)
                return Double(deviation) / Double(max(1, medianInterval)) <= 0.30
            }.count

            let regularityRatio = Double(regularCount) / Double(intervals.count)
            guard regularityRatio >= 0.5 else { continue } // At least 50% regular

            // ─── Step 2d: Check amount similarity ───

            let amounts = sorted.map { $0.amount }
            let medianAmount = medianInt(amounts)
            let similarCount = amounts.filter { amt in
                let deviation = abs(amt - medianAmount)
                return Double(deviation) / Double(max(1, medianAmount)) <= 0.15
            }.count

            let amountSimilarity = Double(similarCount) / Double(amounts.count)

            // ─── Step 2e: Compute confidence score ───

            let occurrenceScore = min(1.0, Double(sorted.count) / 6.0)
            let knownCycle: Double = billingCycle != .custom ? 1.0 : 0.0
            var confidence = 0.0
            confidence += regularityRatio * 0.4     // 40% from interval regularity
            confidence += amountSimilarity * 0.3    // 30% from amount consistency
            confidence += occurrenceScore * 0.2     // 20% from occurrence count
            confidence += knownCycle * 0.1          // 10% from recognized cycle

            guard confidence >= 0.45 else { continue }

            let rationale = DetectionRationale(
                regularityRatio: regularityRatio,
                amountSimilarity: amountSimilarity,
                occurrenceScore: occurrenceScore,
                knownCycle: knownCycle,
                medianIntervalDays: medianInterval,
                sampleCount: sorted.count
            )

            // ─── Step 2f: Build subscription ───

            let lastTx = sorted.last!
            let lastAmount = lastTx.amount
            // Use actual detected interval for next-renewal, not fixed approximation.
            // This avoids drift for non-standard cycles (e.g., 28-day monthly, quarterly).
            let nextRenewal = cal.date(byAdding: .day, value: medianInterval, to: lastTx.date)

            let chargeHistory = sorted.map { tx in
                ChargeRecord(transactionId: tx.id, amount: tx.amount, date: tx.date)
            }

            // Determine status
            var status: SubscriptionStatus = .active

            // If last charge was more than 2x the actual detected interval ago, mark as maybe unused
            let daysSinceLastCharge = cal.dateComponents([.day], from: lastTx.date, to: now).day ?? 0
            if daysSinceLastCharge > medianInterval * 2 {
                status = .suspectedUnused
            }

            let sub = DetectedSubscription(
                merchantName: merchant,
                category: sorted.last?.category ?? .bills,
                expectedAmount: medianAmount,
                lastAmount: lastAmount,
                billingCycle: billingCycle,
                nextRenewalDate: nextRenewal,
                lastChargeDate: lastTx.date,
                status: status,
                linkedTransactionIds: sorted.map { $0.id },
                isAutoDetected: true,
                confidenceScore: confidence,
                chargeHistory: chargeHistory,
                detectedIntervalDays: medianInterval,
                detectionRationale: rationale
            )

            detected.append(sub)
        }

        // ─── Step 2g: Merge near-identical detected subscriptions ───
        // If two detected subscriptions have similar merchant names (e.g. "spotify" and
        // "spotify premium"), merge the smaller into the larger to prevent fragmentation.
        var merged = detected
        var indicesToRemove = Set<Int>()
        for i in 0..<merged.count {
            guard !indicesToRemove.contains(i) else { continue }
            for j in (i+1)..<merged.count {
                guard !indicesToRemove.contains(j) else { continue }
                if merchantNamesSimilar(merged[i].merchantName, merged[j].merchantName) {
                    // Merge j into i (keep the one with more charges)
                    let (keep, drop) = merged[i].chargeHistory.count >= merged[j].chargeHistory.count ? (i, j) : (j, i)
                    // Absorb linked transactions and charge history from the dropped one
                    merged[keep].linkedTransactionIds += merged[drop].linkedTransactionIds
                    merged[keep].chargeHistory += merged[drop].chargeHistory
                    merged[keep].chargeHistory.sort { $0.date < $1.date }
                    // Update amounts from merged history
                    if let lastCharge = merged[keep].chargeHistory.last {
                        merged[keep].lastAmount = lastCharge.amount
                        merged[keep].lastChargeDate = lastCharge.date
                    }
                    indicesToRemove.insert(drop)
                }
            }
        }
        if !indicesToRemove.isEmpty {
            merged = merged.enumerated().filter { !indicesToRemove.contains($0.offset) }.map { $0.element }
        }

        // ─── Step 3: Merge with manual subscriptions ───

        var all = existingManual + merged

        // Sort by monthly cost descending
        all.sort { $0.monthlyCost > $1.monthlyCost }

        return all
    }

    // MARK: - Helpers

    /// Group transactions by normalized merchant name.
    /// Uses note field as merchant name (the main descriptor in this app).
    nonisolated private static func groupByMerchant(_ transactions: [Transaction]) -> [String: [Transaction]] {
        var groups: [String: [Transaction]] = [:]

        for tx in transactions {
            let name = normalizeMerchant(tx.note)
            guard !name.isEmpty else { continue }
            groups[name, default: []].append(tx)
        }

        return groups
    }

    /// Normalize merchant name for subscription grouping.
    /// Strips payment processor prefixes, trailing reference numbers,
    /// common suffixes, and collapses whitespace.
    /// Also used for status override keys and recurring dedup — the single
    /// source of truth for subscription identity.
    nonisolated static func normalizeMerchant(_ name: String) -> String {
        var result = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Remove common payment processor prefixes
        let prefixes = ["pp*", "sp ", "sq *", "paypal *", "google *", "apple.com/bill", "amzn ", "ach "]
        for prefix in prefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
            }
        }

        // Remove trailing reference/transaction numbers (e.g. "#12345", "- 8923")
        result = result.replacingOccurrences(
            of: "[\\s]*[-#*]+[\\s]*[0-9a-f]{3,}$",
            with: "",
            options: .regularExpression
        )

        // Remove trailing country codes and city names in all-caps after merchant
        result = result.replacingOccurrences(
            of: "\\s+(us|uk|nl|de|fr|ie|gb|ca|au)$",
            with: "",
            options: .regularExpression
        )

        // Strip common suffixes
        let suffixes = [".com", ".io", ".co", " inc", " llc", " ltd", " bv", " gmbh"]
        for suffix in suffixes {
            if result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
            }
        }

        // Collapse whitespace and trim
        let components = result.split(separator: " ").map(String.init)
        return components.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
    }

    /// Detect billing cycle from median interval in days
    nonisolated private static func detectCycle(medianInterval: Int) -> BillingCycle? {
        // Weekly: 5–9 days
        if medianInterval >= 5 && medianInterval <= 9 { return .weekly }
        // Monthly: 25–35 days
        if medianInterval >= 25 && medianInterval <= 35 { return .monthly }
        // Yearly: 340–395 days
        if medianInterval >= 340 && medianInterval <= 395 { return .yearly }
        // Custom: anything between weekly and yearly with some regularity
        if medianInterval >= 10 && medianInterval <= 339 { return .custom }
        return nil
    }

    /// Median of integer array
    nonisolated private static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        let count = sorted.count
        if count == 0 { return 0 }
        if count % 2 == 0 {
            return (sorted[count/2 - 1] + sorted[count/2]) / 2
        }
        return sorted[count/2]
    }

    /// Alias for amounts
    nonisolated private static func medianInt(_ values: [Int]) -> Int {
        median(values)
    }
}

// MARK: - Subscription Snapshot (value type for dashboard)

struct SubscriptionSnapshot {
    let activeCount: Int
    let monthlyTotal: Int
    let yearlyTotal: Int
    let renewingSoon: Int       // renewing within 7 days
    let unusedCount: Int
    let priceIncreaseCount: Int
    let missedChargeCount: Int
    let potentialSavings: Int   // monthly savings if unused subs cancelled

    /// Whether there are alerts worth showing on the dashboard
    var hasAlerts: Bool {
        unusedCount > 0 || priceIncreaseCount > 0 || missedChargeCount > 0
    }

    /// Most important alert text for the dashboard
    var urgentSummary: String? {
        if missedChargeCount > 0 {
            return "\(missedChargeCount) missed charge\(missedChargeCount == 1 ? "" : "s") — verify status"
        }
        if priceIncreaseCount > 0 {
            return "\(priceIncreaseCount) subscription\(priceIncreaseCount == 1 ? "" : "s") had a price increase"
        }
        if unusedCount > 0 {
            return "\(unusedCount) possibly unused — save \(DS.Format.money(potentialSavings))/mo"
        }
        return nil
    }
}
