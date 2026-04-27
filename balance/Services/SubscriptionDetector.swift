import Foundation

// ============================================================
// MARK: - AISubscription Detector (Phase 3a — iOS port)
// ============================================================
//
// Pure-heuristic (no LLM) subscription detection. Ported from
// macOS Centmond `SubscriptionDetector.swift`. Adapted to iOS:
//
//   - Reads from `Store` (value type) instead of SwiftData context
//   - Uses `Transaction.note` as the merchant string (iOS has no
//     separate `payee` field)
//   - Amounts are `Int` cents, statistics computed as Double
//   - Dismissed merchants live in `Store.aiDismissedSubscriptionKeys`
//     (macOS uses a DismissedDetection @Model table)
//
// Flow: take expense transactions → drop anything already linked to
// an existing AISubscription → group by normalized merchant key →
// compute median/stddev of intervals and amounts → map to AIBillingCycle
// (or .custom) → score confidence → rank.
// ============================================================

// MARK: - Candidate

/// Candidate subscription surfaced by the detector. Intentionally NOT
/// persisted — candidates live only in memory until the user confirms
/// or dismisses. Confirming mints a `AISubscription` + `AISubscriptionCharge`
/// rows; dismissing appends to `Store.aiDismissedSubscriptionKeys`.
struct DetectedSubscriptionCandidate: Identifiable, Hashable {
    let id: UUID
    let merchantKey: String
    let displayName: String
    let amount: Int                  // cents
    let currency: String
    let billingCycle: AIBillingCycle
    let customCadenceDays: Int?
    let confidence: Double
    let nextPredictedDate: Date
    let firstChargeDate: Date
    let lastChargeDate: Date
    let chargeCount: Int
    let matchingTransactionIDs: [UUID]
    let amountCoefficientOfVariation: Double
    let intervalCoefficientOfVariation: Double
    let suggestedCategory: String?
    let hasPriceChange: Bool
    let priceChangePercent: Double?

    /// Bump confidence +0.15 (capped at 0.98) when the user pre-labelled
    /// this merchant as a subscription via a CSV hint column.
    func boostedByHint() -> DetectedSubscriptionCandidate {
        DetectedSubscriptionCandidate(
            id: id, merchantKey: merchantKey, displayName: displayName,
            amount: amount, currency: currency, billingCycle: billingCycle,
            customCadenceDays: customCadenceDays,
            confidence: min(confidence + 0.15, 0.98),
            nextPredictedDate: nextPredictedDate,
            firstChargeDate: firstChargeDate, lastChargeDate: lastChargeDate,
            chargeCount: chargeCount, matchingTransactionIDs: matchingTransactionIDs,
            amountCoefficientOfVariation: amountCoefficientOfVariation,
            intervalCoefficientOfVariation: intervalCoefficientOfVariation,
            suggestedCategory: suggestedCategory,
            hasPriceChange: hasPriceChange, priceChangePercent: priceChangePercent
        )
    }
}

// MARK: - Detector

enum SubscriptionDetector {

    // Tuning knobs. Kept together so they're easy to find when the user
    // says "too noisy" or "missed X".
    static let minChargeCount: Int = 3
    static let amountVarianceCeiling: Double = 0.25    // CoV above this → not a sub
    static let intervalVarianceCeiling: Double = 0.30  // CoV above this → too irregular
    static let priceChangeThreshold: Double = 0.05     // > 5% delta = price hike

    // Ephemeral CSV-hint handoff — same pattern as macOS.
    private static let hintsDefaultsKey = "pendingSubscriptionImportHints"

    static func stashHintedKeys(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        UserDefaults.standard.set(Array(keys), forKey: hintsDefaultsKey)
    }

    static func consumeHintedKeys() -> Set<String> {
        let defaults = UserDefaults.standard
        let raw = defaults.stringArray(forKey: hintsDefaultsKey) ?? []
        if !raw.isEmpty { defaults.removeObject(forKey: hintsDefaultsKey) }
        return Set(raw)
    }

    // MARK: - Public API

    /// Run the detector against the Store's current state. Returns a sorted
    /// list of candidates with existing-subscription / dismissed merchants
    /// already filtered out.
    static func detect(
        store: Store,
        hintedMerchantKeys: Set<String> = []
    ) -> [DetectedSubscriptionCandidate] {
        let expenses = store.transactions.filter { $0.type == .expense && !$0.isTransfer }
        let linkedIDs = Set(store.aiSubscriptionCharges.compactMap(\.transactionId))
        let existingKeys = Set(store.aiSubscriptions.map { $0.merchantKey })
        let dismissedKeys = Set(store.aiDismissedSubscriptionKeys)

        let candidates = analyze(
            transactions: expenses,
            excludeTransactionIDs: linkedIDs,
            hintedMerchantKeys: hintedMerchantKeys
        )

        return candidates
            .filter { !existingKeys.contains($0.merchantKey) }
            .filter { !dismissedKeys.contains($0.merchantKey) }
            .sorted { $0.confidence > $1.confidence }
    }

    /// Dismiss a candidate — appends its merchant key to the Store's dismiss
    /// list so the next `detect(...)` skips this merchant. Keyed on
    /// `merchantKey`, not on the candidate id, so re-running detection
    /// (new ids) still matches.
    static func dismiss(_ candidate: DetectedSubscriptionCandidate, store: inout Store) {
        if !store.aiDismissedSubscriptionKeys.contains(candidate.merchantKey) {
            store.aiDismissedSubscriptionKeys.append(candidate.merchantKey)
        }
    }

    /// Confirm a candidate — mints a `AISubscription` with `source = .detected`,
    /// `autoDetected = true`, the detector's confidence, and backfills
    /// `AISubscriptionCharge` rows for every matching transaction. Returns
    /// the new subscription for UI navigation.
    @discardableResult
    static func confirm(
        _ candidate: DetectedSubscriptionCandidate,
        store: inout Store
    ) -> AISubscription {
        var sub = AISubscription(
            serviceName: candidate.displayName,
            categoryName: candidate.suggestedCategory ?? "AISubscriptions",
            amount: candidate.amount,
            currency: candidate.currency,
            billingCycle: candidate.billingCycle,
            customCadenceDays: candidate.customCadenceDays,
            nextPaymentDate: candidate.nextPredictedDate,
            lastChargeDate: candidate.lastChargeDate,
            firstChargeDate: candidate.firstChargeDate,
            source: .detected,
            autoDetected: true,
            detectionConfidence: candidate.confidence
        )
        sub.merchantKey = candidate.merchantKey
        store.aiSubscriptions.append(sub)

        // Backfill charge history so the detail timeline is populated
        // from day one.
        let byID = Dictionary(uniqueKeysWithValues: store.transactions.map { ($0.id, $0) })
        for txnID in candidate.matchingTransactionIDs {
            guard let tx = byID[txnID] else { continue }
            let charge = AISubscriptionCharge(
                subscriptionId: sub.id,
                date: tx.date,
                amount: tx.amount,
                currency: candidate.currency,
                transactionId: tx.id,
                matchedAutomatically: true,
                matchConfidence: candidate.confidence
            )
            store.aiSubscriptionCharges.append(charge)
        }
        return sub
    }

    // MARK: - Analysis (pure)

    /// Pure function — takes transactions, returns candidates. No Store,
    /// no filtering against existing aiSubscriptions. Separated so the
    /// algorithm can be unit-tested against a fixture.
    static func analyze(
        transactions: [Transaction],
        excludeTransactionIDs: Set<UUID> = [],
        hintedMerchantKeys: Set<String> = []
    ) -> [DetectedSubscriptionCandidate] {
        var groups: [String: [Transaction]] = [:]
        for tx in transactions {
            if excludeTransactionIDs.contains(tx.id) { continue }
            let key = AISubscription.merchantKey(for: tx.note)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(tx)
        }

        var out: [DetectedSubscriptionCandidate] = []
        for (key, bucket) in groups {
            let isHinted = hintedMerchantKeys.contains(key)
            // Hinted merchants only need 2 charges to surface — the human
            // pre-labelled them, so we trust them more than an arbitrary
            // repeat-purchase group.
            let threshold = isHinted ? max(minChargeCount - 1, 2) : minChargeCount
            guard bucket.count >= threshold else { continue }
            let sorted = bucket.sorted { $0.date < $1.date }
            guard var candidate = makeCandidate(merchantKey: key, sorted: sorted) else { continue }
            if isHinted { candidate = candidate.boostedByHint() }
            out.append(candidate)
        }
        return out
    }

    private static func makeCandidate(
        merchantKey: String,
        sorted: [Transaction]
    ) -> DetectedSubscriptionCandidate? {
        let intervals = consecutiveDayDeltas(sorted)
        guard !intervals.isEmpty else { return nil }

        let intervalStats = stats(of: intervals.map(Double.init))
        // Interval CoV — scatter-shot merchants (coffee shop) will blow
        // past the ceiling. Single most important false-positive filter.
        guard intervalStats.coefficientOfVariation <= intervalVarianceCeiling else { return nil }

        let amounts = sorted.map { Double($0.amount) }
        let amountStats = stats(of: amounts)
        guard amountStats.coefficientOfVariation <= amountVarianceCeiling else { return nil }

        let medianInterval = Int(intervalStats.median.rounded())
        let (cycle, customDays) = mapIntervalToCycle(medianInterval)

        // Median instead of mean — protects against a one-off promo charge
        // dragging the average down.
        let amountCents = Int(amountStats.median.rounded())

        let lastDate = sorted.last?.date ?? Date()
        let firstDate = sorted.first?.date ?? Date()
        let nextDate = predictNextDate(lastCharge: lastDate, cycle: cycle, customDays: customDays)

        // Price-change detection: compare the last charge to the median
        // of the prior charges. If the delta exceeds threshold, flag it.
        let priceChange: (hasChange: Bool, percent: Double?) = {
            guard sorted.count >= 3 else { return (false, nil) }
            let last = amounts.last ?? 0
            let priorMedian = median(of: Array(amounts.dropLast()))
            guard priorMedian > 0 else { return (false, nil) }
            let delta = (last - priorMedian) / priorMedian
            return (abs(delta) >= priceChangeThreshold, delta)
        }()

        let confidence = scoreConfidence(
            chargeCount: sorted.count,
            amountCov: amountStats.coefficientOfVariation,
            intervalCov: intervalStats.coefficientOfVariation,
            cycleIsExact: cycle != .custom
        )

        let displayName = bestDisplayName(from: sorted)
        let category = mostCommonCategoryName(in: sorted)
        let currency = "USD" // iOS doesn't wire per-account currency yet

        return DetectedSubscriptionCandidate(
            id: UUID(),
            merchantKey: merchantKey,
            displayName: displayName,
            amount: amountCents,
            currency: currency,
            billingCycle: cycle,
            customCadenceDays: customDays,
            confidence: confidence,
            nextPredictedDate: nextDate,
            firstChargeDate: firstDate,
            lastChargeDate: lastDate,
            chargeCount: sorted.count,
            matchingTransactionIDs: sorted.map(\.id),
            amountCoefficientOfVariation: amountStats.coefficientOfVariation,
            intervalCoefficientOfVariation: intervalStats.coefficientOfVariation,
            suggestedCategory: category,
            hasPriceChange: priceChange.hasChange,
            priceChangePercent: priceChange.percent
        )
    }

    private static func consecutiveDayDeltas(_ sorted: [Transaction]) -> [Int] {
        guard sorted.count >= 2 else { return [] }
        var out: [Int] = []
        let cal = Calendar.current
        for i in 1..<sorted.count {
            let d = cal.dateComponents([.day], from: sorted[i - 1].date, to: sorted[i].date).day ?? 0
            if d > 0 { out.append(d) }
        }
        return out
    }

    /// Maps a median interval (days) to the closest `AIBillingCycle` with
    /// 20% tolerance. Falls back to `.custom` if nothing fits — better to
    /// surface a weird cadence than silently snap to monthly.
    private static func mapIntervalToCycle(_ days: Int) -> (AIBillingCycle, Int?) {
        let targets: [(AIBillingCycle, Int)] = [
            (.weekly, 7),
            (.biweekly, 14),
            (.monthly, 30),
            (.quarterly, 91),
            (.semiannual, 182),
            (.annual, 365)
        ]
        for (cycle, target) in targets {
            let tolerance = Double(target) * 0.20
            if abs(Double(days) - Double(target)) <= tolerance {
                return (cycle, nil)
            }
        }
        return (.custom, days)
    }

    private static func predictNextDate(
        lastCharge: Date,
        cycle: AIBillingCycle,
        customDays: Int?
    ) -> Date {
        let cal = Calendar.current
        switch cycle {
        case .weekly:     return cal.date(byAdding: .weekOfYear, value: 1, to: lastCharge) ?? lastCharge
        case .biweekly:   return cal.date(byAdding: .weekOfYear, value: 2, to: lastCharge) ?? lastCharge
        case .monthly:    return cal.date(byAdding: .month,      value: 1, to: lastCharge) ?? lastCharge
        case .quarterly:  return cal.date(byAdding: .month,      value: 3, to: lastCharge) ?? lastCharge
        case .semiannual: return cal.date(byAdding: .month,      value: 6, to: lastCharge) ?? lastCharge
        case .annual:     return cal.date(byAdding: .year,       value: 1, to: lastCharge) ?? lastCharge
        case .custom:     return cal.date(byAdding: .day, value: max(customDays ?? 30, 1), to: lastCharge) ?? lastCharge
        }
    }

    /// Starts at 0.4, rewards high charge count, low amount variance, low
    /// interval variance, and an exact standard cycle. Caps at 0.95 — never
    /// claim total certainty on a heuristic match.
    private static func scoreConfidence(
        chargeCount: Int,
        amountCov: Double,
        intervalCov: Double,
        cycleIsExact: Bool
    ) -> Double {
        var score = 0.4
        if chargeCount >= 3 { score += 0.1 }
        if chargeCount >= 5 { score += 0.1 }
        if chargeCount >= 8 { score += 0.05 }
        if amountCov <= 0.10 { score += 0.15 } else if amountCov <= 0.20 { score += 0.05 }
        if intervalCov <= 0.10 { score += 0.15 } else if intervalCov <= 0.20 { score += 0.05 }
        if cycleIsExact { score += 0.05 }
        return min(score, 0.95)
    }

    private static func bestDisplayName(from txns: [Transaction]) -> String {
        var counts: [String: Int] = [:]
        for tx in txns {
            let note = tx.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { continue }
            counts[note, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
            ?? txns.first?.note
            ?? ""
    }

    private static func mostCommonCategoryName(in txns: [Transaction]) -> String? {
        var counts: [String: Int] = [:]
        for tx in txns {
            let name = tx.category.title
            guard !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Statistics

    private struct Summary {
        let mean: Double
        let median: Double
        let stddev: Double
        var coefficientOfVariation: Double { mean > 0 ? stddev / mean : .infinity }
    }

    private static func stats(of values: [Double]) -> Summary {
        guard !values.isEmpty else { return Summary(mean: 0, median: 0, stddev: 0) }
        let mean = values.reduce(0, +) / Double(values.count)
        let med = median(of: values)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return Summary(mean: mean, median: med, stddev: sqrt(variance))
    }

    private static func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
