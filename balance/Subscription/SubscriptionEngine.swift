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

    // Persisted subscription status overrides (keyed by normalized merchant name)
    private static let statusOverridesKey = "subscriptions.status_overrides"

    private var statusOverrides: [String: String] = [:] {
        didSet { saveStatusOverrides() }
    }

    private init() {
        loadStatusOverrides()
    }

    private func loadStatusOverrides() {
        statusOverrides = UserDefaults.standard.dictionary(forKey: Self.statusOverridesKey) as? [String: String] ?? [:]
    }

    private func saveStatusOverrides() {
        UserDefaults.standard.set(statusOverrides, forKey: Self.statusOverridesKey)
    }

    // MARK: - Main Analysis

    /// Analyze transactions to detect and update subscriptions.
    /// Merges auto-detected subscriptions with manually-managed ones.
    func analyze(store: Store) async {
        isLoading = true

        let transactions = store.transactions
        let existing = subscriptions.filter { !$0.isAutoDetected }

        let result = await Task.detached(priority: .userInitiated) {
            Self.detect(transactions: transactions, existingManual: existing)
        }.value

        // Apply persisted status overrides to re-detected subscriptions.
        // Uses normalizeMerchant() for key consistency with detection grouping.
        var subs = result.subscriptions
        for i in subs.indices {
            let merchantKey = Self.normalizeMerchant(subs[i].merchantName)
            if let overrideRaw = statusOverrides[merchantKey],
               let override = SubscriptionStatus(rawValue: overrideRaw) {
                subs[i].status = override
            }
        }

        // Merge recurring transactions as subscriptions.
        // Use normalizeMerchant() for both sides to ensure consistent dedup.
        let existingNormalized = Set(subs.map { Self.normalizeMerchant($0.merchantName) })
        let recurringAsSubs = Self.convertRecurringToSubscriptions(store.recurringTransactions, existingNormalizedNames: existingNormalized)
        subs.append(contentsOf: recurringAsSubs)

        self.subscriptions = subs
        self.insights = result.globalInsights
        self.monthlyTotal = subs
            .filter { $0.status == .active }
            .reduce(0) { $0 + $1.monthlyCost }
        self.yearlyTotal = subs
            .filter { $0.status == .active }
            .reduce(0) { $0 + $1.yearlyCost }
        self.activeCount = subs.filter { $0.status == .active }.count
        self.lastAnalyzedAt = Date()
        self.isLoading = false
    }

    // MARK: - Manual Actions

    func markAsCancelled(_ sub: DetectedSubscription) {
        guard let idx = subscriptions.firstIndex(where: { $0.id == sub.id }) else { return }
        subscriptions[idx].status = .cancelled
        subscriptions[idx].updatedAt = Date()
        persistStatus(for: subscriptions[idx])
        recalcTotals()
    }

    func markAsPaused(_ sub: DetectedSubscription) {
        guard let idx = subscriptions.firstIndex(where: { $0.id == sub.id }) else { return }
        subscriptions[idx].status = .paused
        subscriptions[idx].updatedAt = Date()
        persistStatus(for: subscriptions[idx])
        recalcTotals()
    }

    func markAsActive(_ sub: DetectedSubscription) {
        guard let idx = subscriptions.firstIndex(where: { $0.id == sub.id }) else { return }
        subscriptions[idx].status = .active
        subscriptions[idx].updatedAt = Date()
        // Remove override so auto-detection takes over again
        let merchantKey = Self.normalizeMerchant(subscriptions[idx].merchantName)
        statusOverrides.removeValue(forKey: merchantKey)
        recalcTotals()
    }

    private func persistStatus(for sub: DetectedSubscription) {
        let merchantKey = Self.normalizeMerchant(sub.merchantName)
        statusOverrides[merchantKey] = sub.status.rawValue
    }

    func updateNotes(_ sub: DetectedSubscription, notes: String) {
        guard let idx = subscriptions.firstIndex(where: { $0.id == sub.id }) else { return }
        subscriptions[idx].notes = notes
        subscriptions[idx].updatedAt = Date()
    }

    func removeSubscription(_ sub: DetectedSubscription) {
        subscriptions.removeAll { $0.id == sub.id }
        recalcTotals()
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

    // MARK: - Recurring → Subscription Conversion

    /// Convert active RecurringTransactions into DetectedSubscriptions,
    /// skipping any that already exist (by normalized merchant name match).
    static func convertRecurringToSubscriptions(_ recurring: [RecurringTransaction], existingNormalizedNames: Set<String>) -> [DetectedSubscription] {
        recurring.compactMap { rt in
            guard rt.isActive else { return nil }
            // Use the same normalization as detection grouping to prevent duplicates
            let key = normalizeMerchant(rt.name)
            guard !key.isEmpty, !existingNormalizedNames.contains(key) else { return nil }

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
                category: rt.category,
                expectedAmount: rt.amount,
                lastAmount: rt.amount,
                billingCycle: cycle,
                nextRenewalDate: rt.nextOccurrence(),
                lastChargeDate: rt.lastProcessedDate,
                status: .active,
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
            // Check amount similarity (within 40%)
            let diff = abs(other.expectedAmount - sub.expectedAmount)
            let threshold = max(sub.expectedAmount, other.expectedAmount) * 2 / 5 // 40%
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

    /// Check if two merchant names are likely the same service
    nonisolated static func merchantNamesSimilar(_ a: String, _ b: String) -> Bool {
        let na = a.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let nb = b.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if na == nb { return true }
        // Check if one contains the other (e.g. "spotify" in "spotify premium")
        if na.contains(nb) || nb.contains(na) { return true }
        // Check first word match (e.g. "netflix" == "netflix hd")
        let aFirst = na.split(separator: " ").first.map(String.init) ?? na
        let bFirst = nb.split(separator: " ").first.map(String.init) ?? nb
        if aFirst == bFirst && aFirst.count >= 4 { return true }
        return false
    }

    // MARK: - Pure Detection Logic (off main thread)

    struct DetectionResult {
        let subscriptions: [DetectedSubscription]
        let globalInsights: [SubscriptionInsight]
    }

    nonisolated static func detect(
        transactions: [Transaction],
        existingManual: [DetectedSubscription]
    ) -> DetectionResult {
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

            var confidence = 0.0
            confidence += regularityRatio * 0.4     // 40% from interval regularity
            confidence += amountSimilarity * 0.3    // 30% from amount consistency
            confidence += min(1.0, Double(sorted.count) / 6.0) * 0.2  // 20% from occurrence count
            confidence += (billingCycle != .custom ? 0.1 : 0.0) // 10% from recognized cycle

            guard confidence >= 0.45 else { continue }

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
                detectedIntervalDays: medianInterval
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

        // ─── Step 4: Detect global insights ───

        var globalInsights: [SubscriptionInsight] = []

        // Any price increases?
        if all.contains(where: { $0.hasPriceIncrease }) {
            globalInsights.append(.priceIncreased)
        }

        // Any upcoming in 7 days?
        if all.contains(where: {
            guard let days = $0.daysUntilRenewal else { return false }
            return days <= 7 && days >= 0 && $0.status == .active
        }) {
            globalInsights.append(.upcomingRenewal)
        }

        // Any suspected unused?
        if all.contains(where: { $0.status == .suspectedUnused }) {
            globalInsights.append(.maybeUnused)
        }

        // Missed charge check
        if all.contains(where: { $0.hasMissedCharge }) {
            globalInsights.append(.missedCharge)
        }

        // Duplicate risk check — broader: same category + similar name OR similar amount
        let activeSubs = all.filter { $0.status == .active }
        var hasDuplicate = false
        for i in 0..<activeSubs.count {
            for j in (i+1)..<activeSubs.count {
                if activeSubs[i].category == activeSubs[j].category {
                    // Amount similarity
                    let diff = abs(activeSubs[i].expectedAmount - activeSubs[j].expectedAmount)
                    let threshold = max(activeSubs[i].expectedAmount, activeSubs[j].expectedAmount) * 2 / 5
                    let amountSimilar = diff <= threshold

                    // Name similarity
                    let nameSimilar = merchantNamesSimilar(
                        activeSubs[i].merchantName, activeSubs[j].merchantName
                    )

                    if amountSimilar || nameSimilar {
                        hasDuplicate = true
                        break
                    }
                }
            }
            if hasDuplicate { break }
        }
        if hasDuplicate {
            globalInsights.append(.duplicateRisk)
        }

        // Newly detected (subscriptions with only 2-3 charges)
        if all.contains(where: { $0.chargeHistory.count <= 3 && $0.isAutoDetected && $0.status == .active }) {
            globalInsights.append(.newlyDetected)
        }

        return DetectionResult(subscriptions: all, globalInsights: globalInsights)
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
