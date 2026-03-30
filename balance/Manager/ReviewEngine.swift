import Foundation
import SwiftUI
import Combine

// ============================================================
// MARK: - Transaction Review Engine
// ============================================================
//
// Deterministic, explainable transaction review system.
//
// Detection Rules (all transparent):
//
// 1. UNCATEGORIZED: Transaction category == .other with non-empty note
//    → Suggest category based on keyword matching against note text
//    → Priority: medium (high if amount > 3x average)
//
// 2. POSSIBLE DUPLICATE: Same amount, same day (or ±1 day),
//    similar note (Levenshtein distance ≤ 30% of length)
//    → Priority: high
//
// 3. SPENDING SPIKE: Transaction amount > 3x the rolling 3-month
//    average for that category
//    → Priority: medium (high if > 5x average)
//
// 4. RECURRING CANDIDATE: 3+ transactions to same merchant with
//    roughly equal intervals (±5 days) that aren't already in
//    recurring transactions
//    → Priority: low
//
// 5. MERCHANT NORMALIZATION: Same merchant appears with multiple
//    name variants (case differences, trailing numbers, etc.)
//    → Priority: low
//
// ============================================================

@MainActor
class ReviewEngine: ObservableObject {

    static let shared = ReviewEngine()

    @Published var items: [ReviewItem] = []
    @Published var isLoading = false
    @Published var lastAnalyzedAt: Date?

    // Dismissed stable keys persist across app launches so items don't reappear.
    // Uses an ordered array internally so the cap drops oldest entries, not arbitrary ones.
    private var dismissedStableKeys: Set<String> = []
    private var dismissedStableKeysOrdered: [String] = []

    private static let dismissedKeysKey = "review.dismissed_keys"
    private static let maxDismissedKeys = 500

    private init() {
        loadDismissedKeys()
    }

    private func loadDismissedKeys() {
        let arr = UserDefaults.standard.stringArray(forKey: Self.dismissedKeysKey) ?? []
        dismissedStableKeysOrdered = arr
        dismissedStableKeys = Set(arr)
    }

    private func saveDismissedKeys() {
        // Cap at maxDismissedKeys — drop oldest entries (front of array)
        if dismissedStableKeysOrdered.count > Self.maxDismissedKeys {
            let overflow = dismissedStableKeysOrdered.count - Self.maxDismissedKeys
            let dropped = dismissedStableKeysOrdered.prefix(overflow)
            dropped.forEach { dismissedStableKeys.remove($0) }
            dismissedStableKeysOrdered = Array(dismissedStableKeysOrdered.dropFirst(overflow))
        }
        UserDefaults.standard.set(dismissedStableKeysOrdered, forKey: Self.dismissedKeysKey)
    }

    private func addDismissedKey(_ key: String) {
        guard !dismissedStableKeys.contains(key) else { return }
        dismissedStableKeys.insert(key)
        dismissedStableKeysOrdered.append(key)
        saveDismissedKeys()
    }

    // MARK: - Summary Stats

    var pendingCount: Int {
        items.filter { $0.status == .pending }.count
    }

    var highPriorityCount: Int {
        items.filter { $0.status == .pending && $0.priority == .high }.count
    }

    var uncategorizedCount: Int {
        items.filter { $0.status == .pending && $0.type == .uncategorized }.count
    }

    var duplicateCount: Int {
        items.filter { $0.status == .pending && $0.type == .possibleDuplicate }.count
    }

    var spikeCount: Int {
        items.filter { $0.status == .pending && $0.type == .spendingSpike }.count
    }

    var recurringCandidateCount: Int {
        items.filter { $0.status == .pending && $0.type == .recurringCandidate }.count
    }

    var merchantNormCount: Int {
        items.filter { $0.status == .pending && $0.type == .merchantNormalization }.count
    }

    var pendingItems: [ReviewItem] {
        items
            .filter { $0.status == .pending }
            .sorted { $0.priority > $1.priority }
    }

    func pendingByType(_ type: ReviewType) -> [ReviewItem] {
        items.filter { $0.status == .pending && $0.type == type }
    }

    /// Total amount at risk from potential duplicates (sum of duplicate amounts)
    var duplicateRiskAmount: Int {
        pendingByType(.possibleDuplicate).reduce(0) { total, item in
            total + (item.spikeAmount ?? 0) // spikeAmount is reused, but for duplicates we sum tx amounts
        }
    }

    /// Quick summary snapshot for the dashboard
    var dashboardSnapshot: ReviewSnapshot {
        ReviewSnapshot(
            pendingCount: pendingCount,
            highPriorityCount: highPriorityCount,
            duplicateCount: duplicateCount,
            uncategorizedCount: uncategorizedCount,
            spikeCount: spikeCount,
            recurringCandidateCount: recurringCandidateCount,
            topIssueReason: pendingItems.first?.reason,
            topIssueType: pendingItems.first?.type
        )
    }

    // MARK: - Main Analysis

    /// Analyze transactions for the selected month.
    /// Results change when the user navigates between months.
    func analyze(store: Store) async {
        isLoading = true

        let cal = Calendar.current
        let selectedMonth = store.selectedMonth

        // Filter transactions relevant to the selected month:
        // Use selected month ± 1 month for context (duplicate detection, spike comparison)
        let contextStart = cal.date(byAdding: .month, value: -2, to:
            cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!)!
        let contextEnd = cal.date(byAdding: .month, value: 2, to:
            cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!)!

        let contextTransactions = store.transactions.filter {
            $0.date >= contextStart && $0.date < contextEnd
        }
        // Primary month transactions (for uncategorized, duplicates)
        let monthTransactions = store.transactions.filter {
            cal.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
        }
        let recurring = store.recurringTransactions

        let result = await Task.detached(priority: .userInitiated) {
            Self.detect(
                transactions: monthTransactions,
                contextTransactions: contextTransactions,
                recurringTransactions: recurring
            )
        }.value

        // Current transaction IDs for ghost pruning
        let currentTxIds = Set(store.transactions.map { $0.id })

        // Filter out dismissed items by stableKey
        let newItems = result.filter { !dismissedStableKeys.contains($0.stableKey) }

        // Deduplicate by stableKey — keep the first occurrence of each
        var seenKeys = Set<String>()
        let deduped = newItems.filter { item in
            guard !seenKeys.contains(item.stableKey) else { return false }
            seenKeys.insert(item.stableKey)
            return true
        }

        // Prune: only keep items whose target transactions still exist
        let valid = deduped.filter { item in
            item.transactionIds.contains { currentTxIds.contains($0) }
        }

        self.items = valid
        self.lastAnalyzedAt = Date()
        self.isLoading = false
    }

    // MARK: - Actions

    /// Resolve an item (action was taken).
    /// Persists the stable key so re-analysis won't recreate the same item.
    func resolve(_ item: ReviewItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].status = .resolved
        items[idx].resolvedAt = Date()
        AnalyticsManager.shared.track(.reviewItemResolved(type: item.type.rawValue))

        addDismissedKey(item.stableKey)
        // Remove from active list — it's now persisted in dismissedStableKeys
        items.remove(at: idx)
    }

    /// Dismiss an item (user says it's fine).
    /// Persists the stable key so it won't reappear.
    func dismiss(_ item: ReviewItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].status = .dismissed
        items[idx].resolvedAt = Date()
        AnalyticsManager.shared.track(.reviewItemResolved(type: "dismissed_\(item.type.rawValue)"))

        addDismissedKey(item.stableKey)
        // Remove from active list — it's now persisted in dismissedStableKeys
        items.remove(at: idx)
    }

    /// Assign category to a transaction.
    /// Safe no-op if target transactions no longer exist.
    func assignCategory(item: ReviewItem, category: Category, store: inout Store) {
        var mutated = false
        for txId in item.transactionIds {
            if let idx = store.transactions.firstIndex(where: { $0.id == txId }) {
                store.transactions[idx].category = category
                store.transactions[idx].lastModified = Date()
                mutated = true
            }
        }
        if !mutated {
            SecureLogger.info("ReviewEngine.assignCategory: no target transactions found, resolving as no-op")
        }
        resolve(item)
    }

    /// Mark transactions as duplicates (remove all but the first).
    /// Only removes transactions that still exist; safe no-op for missing ones.
    func markDuplicate(item: ReviewItem, store: inout Store) {
        // Keep the first transaction, remove the rest
        let idsToRemove = Array(item.transactionIds.dropFirst())
        for txId in idsToRemove {
            if store.transactions.contains(where: { $0.id == txId }) {
                store.transactions.removeAll { $0.id == txId }
                store.trackDeletion(of: txId)
            }
        }
        resolve(item)
    }

    /// Create a recurring transaction from a candidate.
    /// Safe no-op if the source transaction no longer exists.
    func createRecurring(item: ReviewItem, store: inout Store) {
        guard let firstTxId = item.transactionIds.first,
              let tx = store.transactions.first(where: { $0.id == firstTxId }) else {
            SecureLogger.info("ReviewEngine.createRecurring: source transaction missing, resolving as no-op")
            resolve(item)
            return
        }

        let recurring = RecurringTransaction(
            name: tx.note.isEmpty ? tx.category.title : tx.note,
            amount: tx.amount,
            category: tx.category,
            frequency: .monthly,
            startDate: tx.date,
            paymentMethod: tx.paymentMethod
        )

        store.recurringTransactions.append(recurring)
        resolve(item)
    }

    /// Normalize merchant names across transactions.
    /// Safe no-op if target transactions no longer exist.
    func normalizeMerchant(item: ReviewItem, normalizedName: String, store: inout Store) {
        var mutated = false
        for txId in item.transactionIds {
            if let idx = store.transactions.firstIndex(where: { $0.id == txId }) {
                store.transactions[idx].note = normalizedName
                store.transactions[idx].lastModified = Date()
                mutated = true
            }
        }
        if !mutated {
            SecureLogger.info("ReviewEngine.normalizeMerchant: no target transactions found, resolving as no-op")
        }
        resolve(item)
    }

    // MARK: - Pure Detection (off main thread)

    /// Detect review items for the selected month.
    /// - `transactions`: transactions IN the selected month (primary focus)
    /// - `contextTransactions`: transactions ± 2 months (for spike comparison, recurring detection)
    nonisolated static func detect(
        transactions: [Transaction],
        contextTransactions: [Transaction],
        recurringTransactions: [RecurringTransaction]
    ) -> [ReviewItem] {
        var items: [ReviewItem] = []

        let cal = Calendar.current

        // ─── Rule 1: Uncategorized (selected month only) ───
        items.append(contentsOf: detectUncategorized(transactions))

        // ─── Rule 2: Possible Duplicates (selected month only) ───
        items.append(contentsOf: detectDuplicates(transactions))

        // ─── Rule 3: Spending Spikes (use context for averages, flag selected month tx) ───
        items.append(contentsOf: detectSpikes(transactions, contextTransactions: contextTransactions, cal: cal))

        // ─── Rule 4: Recurring Candidates (use context for pattern detection) ───
        items.append(contentsOf: detectRecurringCandidates(contextTransactions, existing: recurringTransactions, cal: cal))

        // ─── Rule 5: Merchant Normalization (selected month only) ───
        items.append(contentsOf: detectMerchantIssues(transactions))

        return items
    }

    // MARK: Rule 1: Uncategorized

    nonisolated private static func detectUncategorized(_ transactions: [Transaction]) -> [ReviewItem] {
        var items: [ReviewItem] = []

        let uncategorized = transactions.filter { tx in
            tx.category == .other && tx.type == .expense && !tx.note.trimmingCharacters(in: .whitespaces).isEmpty
        }

        let avgExpense: Int = {
            let expenses = transactions.filter { $0.type == .expense }
            guard !expenses.isEmpty else { return 0 }
            return expenses.reduce(0) { $0 + $1.amount } / expenses.count
        }()

        for tx in uncategorized {
            let suggested = suggestCategory(from: tx.note)
            let isLarge = avgExpense > 0 && tx.amount > avgExpense * 3
            let priority: ReviewPriority = isLarge ? .high : .medium

            items.append(ReviewItem(
                transactionIds: [tx.id],
                type: .uncategorized,
                priority: priority,
                reason: "Transaction '\(tx.note)' is categorized as Other" + (suggested != nil ? ". Suggested: \(suggested!.title)" : ""),
                suggestedAction: .assignCategory,
                merchantName: tx.note,
                suggestedCategory: suggested
            ))
        }

        return items
    }

    /// Keyword-based category suggestion
    nonisolated private static func suggestCategory(from note: String) -> Category? {
        let lower = note.lowercased()

        let keywords: [(Category, [String])] = [
            (.groceries, ["grocery", "supermarket", "lidl", "aldi", "albert heijn", "jumbo", "coop", "rewe", "edeka", "market", "food"]),
            (.rent, ["rent", "housing", "mortgage", "landlord", "huur"]),
            (.bills, ["electric", "water", "gas", "internet", "phone", "mobile", "utility", "insurance", "netflix", "spotify", "subscription"]),
            (.transport, ["uber", "lyft", "taxi", "fuel", "petrol", "gas station", "parking", "train", "bus", "ov-chipkaart", "ns ", "transit"]),
            (.health, ["pharmacy", "doctor", "hospital", "dentist", "apotheek", "medical", "gym", "fitness"]),
            (.education, ["tuition", "course", "book", "udemy", "school", "university", "college", "training"]),
            (.dining, ["restaurant", "cafe", "coffee", "starbucks", "mcdonald", "burger", "pizza", "takeout", "takeaway", "deliveroo", "uber eats", "thuisbezorgd"]),
            (.shopping, ["amazon", "bol.com", "zalando", "h&m", "zara", "clothing", "electronics", "ikea", "store", "shop"])
        ]

        for (category, words) in keywords {
            for word in words {
                if lower.contains(word) {
                    return category
                }
            }
        }

        return nil
    }

    // MARK: Rule 2: Possible Duplicates

    /// Stronger duplicate detection:
    /// - Allows ±2 days (not just ±1)
    /// - Allows amounts within 5% of each other (not just exact match)
    /// - Weights: exact amount + same day = high, near-match = medium
    nonisolated private static func detectDuplicates(_ transactions: [Transaction]) -> [ReviewItem] {
        var items: [ReviewItem] = []
        var processed = Set<UUID>()
        let cal = Calendar.current

        let sorted = transactions.sorted { $0.date < $1.date }

        for i in 0..<sorted.count {
            guard !processed.contains(sorted[i].id) else { continue }
            guard sorted[i].type == .expense else { continue }

            var group: [Transaction] = [sorted[i]]

            for j in (i+1)..<sorted.count {
                guard !processed.contains(sorted[j].id) else { continue }

                // Within ±2 days
                let daysDiff = abs(cal.dateComponents([.day], from: sorted[i].date, to: sorted[j].date).day ?? 99)
                guard daysDiff <= 2 else { continue }

                // Amount within 5% (handles slight differences like tip variations)
                let amountDiff = abs(sorted[i].amount - sorted[j].amount)
                let maxAmount = max(sorted[i].amount, sorted[j].amount)
                let amountMatch = maxAmount > 0 ? Double(amountDiff) / Double(maxAmount) <= 0.05 : sorted[i].amount == sorted[j].amount
                guard amountMatch else { continue }

                // Similar note (at least one non-empty, and similar)
                if !sorted[i].note.isEmpty && !sorted[j].note.isEmpty {
                    let similarity = stringSimilarity(sorted[i].note, sorted[j].note)
                    guard similarity >= 0.6 else { continue } // slightly more lenient
                }

                // Same type
                guard sorted[i].type == sorted[j].type else { continue }

                group.append(sorted[j])
            }

            if group.count >= 2 {
                let ids = group.map { $0.id }
                ids.forEach { processed.insert($0) }
                let groupId = UUID() // Not used for identity — stableKey handles dedup
                let names = group.map { $0.note.isEmpty ? $0.category.title : $0.note }
                let nameStr = names.first ?? "transaction"

                // Exact amount + same day = high priority; otherwise medium
                let isExact = Set(group.map { $0.amount }).count == 1
                let isSameDay = Set(group.map { cal.component(.day, from: $0.date) }).count == 1
                let priority: ReviewPriority = (isExact && isSameDay) ? .high : .medium

                items.append(ReviewItem(
                    transactionIds: ids,
                    type: .possibleDuplicate,
                    priority: priority,
                    reason: "\(group.count) charges of ~\(DS.Format.money(group[0].amount)) for '\(nameStr)' within \(isSameDay ? "the same day" : "2 days")",
                    suggestedAction: .markDuplicate,
                    duplicateGroupId: groupId
                ))
            }
        }

        return items
    }

    /// Normalized string similarity (0.0 = different, 1.0 = identical)
    nonisolated private static func stringSimilarity(_ a: String, _ b: String) -> Double {
        let s1 = a.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let s2 = b.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s1 == s2 { return 1.0 }
        let maxLen = max(s1.count, s2.count)
        guard maxLen > 0 else { return 1.0 }
        let dist = levenshtein(s1, s2)
        return 1.0 - (Double(dist) / Double(maxLen))
    }

    /// Simple Levenshtein distance
    nonisolated private static func levenshtein(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,       // deletion
                    curr[j-1] + 1,     // insertion
                    prev[j-1] + cost   // substitution
                )
            }
            prev = curr
        }

        return prev[n]
    }

    // MARK: Rule 3: Spending Spikes

    /// Detect spending spikes using IQR-based outlier detection.
    /// This is more robust than simple mean-based detection because
    /// it's not skewed by previous spikes in the history.
    ///
    /// A transaction is flagged if amount > Q3 + 1.5 * IQR for its category.
    /// Priority is high if amount > Q3 + 3.0 * IQR (extreme outlier).
    nonisolated private static func detectSpikes(
        _ monthTransactions: [Transaction],
        contextTransactions: [Transaction],
        cal: Calendar
    ) -> [ReviewItem] {
        var items: [ReviewItem] = []

        let monthExpenses = monthTransactions.filter { $0.type == .expense }
        let contextExpenses = contextTransactions.filter { $0.type == .expense }

        // Build category amount distributions from context
        var contextByCategory: [String: [Int]] = [:]
        for tx in contextExpenses {
            contextByCategory[tx.category.storageKey, default: []].append(tx.amount)
        }

        for tx in monthExpenses {
            let catKey = tx.category.storageKey
            guard let catAmounts = contextByCategory[catKey], catAmounts.count >= 4 else { continue }

            let sorted = catAmounts.sorted()
            let q1 = sorted[sorted.count / 4]
            let q3 = sorted[sorted.count * 3 / 4]
            let iqr = q3 - q1
            guard iqr > 0 else { continue } // all amounts are similar, no spike possible

            let mildThreshold = q3 + iqr * 3 / 2  // 1.5 × IQR
            let extremeThreshold = q3 + iqr * 3    // 3.0 × IQR

            if tx.amount > mildThreshold {
                let avg = sorted.reduce(0, +) / sorted.count
                let ratio = avg > 0 ? Double(tx.amount) / Double(avg) : 0
                let priority: ReviewPriority = tx.amount > extremeThreshold ? .high : .medium

                items.append(ReviewItem(
                    transactionIds: [tx.id],
                    type: .spendingSpike,
                    priority: priority,
                    reason: "\(DS.Format.money(tx.amount)) is \(String(format: "%.1f", ratio))x the average for \(tx.category.title)",
                    suggestedAction: .reviewAmount,
                    spikeAmount: tx.amount,
                    spikeAverage: avg
                ))
            }
        }

        return items
    }

    // MARK: Rule 4: Recurring Candidates

    nonisolated private static func detectRecurringCandidates(
        _ transactions: [Transaction],
        existing: [RecurringTransaction],
        cal: Calendar
    ) -> [ReviewItem] {
        var items: [ReviewItem] = []

        let expenses = transactions.filter { $0.type == .expense && !$0.note.trimmingCharacters(in: .whitespaces).isEmpty }

        // Group by normalized note
        var byNote: [String: [Transaction]] = [:]
        for tx in expenses {
            let key = tx.note.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            byNote[key, default: []].append(tx)
        }

        // Names already in recurring
        let existingNames = Set(existing.map { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })

        for (name, txs) in byNote {
            guard txs.count >= 3 else { continue }
            guard !existingNames.contains(name) else { continue }

            let sorted = txs.sorted { $0.date < $1.date }

            // Check interval regularity
            var intervals: [Int] = []
            for i in 1..<sorted.count {
                let days = cal.dateComponents([.day], from: sorted[i-1].date, to: sorted[i].date).day ?? 0
                intervals.append(days)
            }

            guard !intervals.isEmpty else { continue }

            let medianInterval = median(intervals)
            guard medianInterval >= 5 else { continue } // at least weekly

            // Check regularity: intervals within ±5 days of median
            let regularCount = intervals.filter { abs($0 - medianInterval) <= 5 }.count
            let regularity = Double(regularCount) / Double(intervals.count)
            guard regularity >= 0.6 else { continue }

            // Check amount consistency
            let amounts = sorted.map { $0.amount }
            let avgAmount = amounts.reduce(0, +) / amounts.count
            let consistent = amounts.filter { abs($0 - avgAmount) <= avgAmount / 4 }.count // within 25%
            let amountConsistency = Double(consistent) / Double(amounts.count)
            guard amountConsistency >= 0.5 else { continue }

            let merchantDisplay = sorted.last?.note ?? name
            let cycleName: String
            if medianInterval <= 9 { cycleName = "weekly" }
            else if medianInterval <= 35 { cycleName = "monthly" }
            else if medianInterval <= 100 { cycleName = "quarterly" }
            else { cycleName = "periodic" }

            items.append(ReviewItem(
                transactionIds: sorted.map { $0.id },
                type: .recurringCandidate,
                priority: .low,
                reason: "'\(merchantDisplay)' appears \(sorted.count) times with a ~\(cycleName) pattern (avg €\(String(format: "%.2f", Double(avgAmount) / 100.0)))",
                suggestedAction: .createRecurring,
                merchantName: merchantDisplay
            ))
        }

        return items
    }

    // MARK: Rule 5: Merchant Normalization

    nonisolated private static func detectMerchantIssues(_ transactions: [Transaction]) -> [ReviewItem] {
        var items: [ReviewItem] = []

        let withNotes = transactions.filter { !$0.note.trimmingCharacters(in: .whitespaces).isEmpty }

        // Group by aggressive normalization (lowercase, remove trailing digits/special chars)
        var groups: [String: [String: [Transaction]]] = [:]  // normalized -> original -> txs
        for tx in withNotes {
            let original = tx.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = aggressiveNormalize(original)
            guard !normalized.isEmpty else { continue }
            groups[normalized, default: [:]][original, default: []].append(tx)
        }

        for (_, variants) in groups {
            guard variants.count >= 2 else { continue }

            // Multiple different spellings of the same merchant
            let allTxs = variants.values.flatMap { $0 }
            guard allTxs.count >= 3 else { continue }

            // Find the most common variant as the suggestion
            let mostCommon = variants.max(by: { $0.value.count < $1.value.count })!
            let variantNames = variants.keys.sorted()

            items.append(ReviewItem(
                transactionIds: allTxs.map { $0.id },
                type: .merchantNormalization,
                priority: .low,
                reason: "'\(variantNames.joined(separator: "', '"))' appear to be the same merchant. Suggested: '\(mostCommon.key)'",
                suggestedAction: .mergeMerchant,
                merchantName: mostCommon.key
            ))
        }

        return items
    }

    /// Aggressively normalize: lowercase, remove trailing digits, strip payment
    /// processor prefixes, strip common suffixes, trim punctuation.
    nonisolated private static func aggressiveNormalize(_ name: String) -> String {
        var result = name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove payment processor prefixes
        let prefixes = ["pp*", "sp ", "sq *", "paypal *", "google *", "apple.com/bill ", "amzn "]
        for prefix in prefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
            }
        }

        // Remove trailing digits and special chars (e.g., "Netflix #123" → "netflix")
        result = result.replacingOccurrences(of: "[\\s]*[-#*]+[\\s]*[0-9a-f]{2,}$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove common suffixes
        let suffixes = [".com", ".io", ".co", " inc", " llc", " ltd", " bv", " gmbh"]
        for suffix in suffixes {
            if result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
            }
        }

        result = result.trimmingCharacters(in: .punctuationCharacters)

        // Collapse multiple spaces
        let parts = result.split(separator: " ").map(String.init)
        return parts.joined(separator: " ")
    }

    nonisolated private static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        let count = sorted.count
        if count == 0 { return 0 }
        if count % 2 == 0 { return (sorted[count/2 - 1] + sorted[count/2]) / 2 }
        return sorted[count/2]
    }
}

// MARK: - Review Snapshot (value type for dashboard)

struct ReviewSnapshot {
    let pendingCount: Int
    let highPriorityCount: Int
    let duplicateCount: Int
    let uncategorizedCount: Int
    let spikeCount: Int
    let recurringCandidateCount: Int
    let topIssueReason: String?
    let topIssueType: ReviewType?

    /// Whether there are alerts worth showing on the dashboard
    var hasAlerts: Bool {
        highPriorityCount > 0 || duplicateCount > 0
    }

    /// Most important alert text for the dashboard
    var urgentSummary: String? {
        if duplicateCount > 0 {
            return "\(duplicateCount) possible duplicate\(duplicateCount == 1 ? "" : "s") — review to avoid double charges"
        }
        if spikeCount > 0 {
            return "\(spikeCount) unusual spending spike\(spikeCount == 1 ? "" : "s") detected"
        }
        if uncategorizedCount > 0 {
            return "\(uncategorizedCount) transaction\(uncategorizedCount == 1 ? "" : "s") need categorizing"
        }
        return nil
    }
}
