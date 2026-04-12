import Foundation
import Combine

// ============================================================
// MARK: - AI Recurring Transaction Detector
// ============================================================
//
// Phase 3 deliverable: scans transaction history for patterns
// that look like recurring payments (subscriptions, bills,
// installments) that haven't been set up as recurring yet.
//
// Pure heuristic — no LLM needed.
//
// ============================================================

struct DetectedRecurring: Identifiable {
    let id = UUID()
    let merchantName: String
    let amount: Int                    // cents (average)
    let frequency: EstimatedFrequency
    let confidence: Double             // 0–1
    let matchingTransactions: [Transaction]
    let suggestedCategory: String

    enum EstimatedFrequency: String {
        case weekly    = "weekly"
        case biweekly  = "biweekly"
        case monthly   = "monthly"
        case quarterly = "quarterly"
        case yearly    = "yearly"

        var dayRange: ClosedRange<Int> {
            switch self {
            case .weekly:    return 5...9
            case .biweekly:  return 12...16
            case .monthly:   return 27...34
            case .quarterly: return 85...100
            case .yearly:    return 350...380
            }
        }
    }

    /// Whether this is already tracked as a subscription/recurring.
    var isAlreadyTracked: Bool {
        // Will be set during detection
        false
    }
}

@MainActor
class AIRecurringDetector {
    static let shared = AIRecurringDetector()

    private init() {}

    // MARK: - Detect

    /// Scan all transactions for recurring patterns.
    func detect(transactions: [Transaction], existingRecurring: [RecurringTransaction] = []) -> [DetectedRecurring] {
        // Group transactions by normalized merchant/note
        let groups = groupByMerchant(transactions)

        var results: [DetectedRecurring] = []

        for (merchant, txns) in groups {
            guard txns.count >= 2 else { continue }

            // Sort by date
            let sorted = txns.sorted { $0.date < $1.date }

            // Calculate intervals between consecutive transactions
            let intervals = calculateIntervals(sorted)
            guard !intervals.isEmpty else { continue }

            // Detect frequency
            if let frequency = detectFrequency(intervals) {
                // Calculate amount consistency
                let amounts = sorted.map(\.amount)
                let avgAmount = amounts.reduce(0, +) / amounts.count
                let amountVariance = calculateVariance(amounts)
                let isConsistentAmount = amountVariance < 0.15 // <15% variance

                // Skip if already tracked as recurring
                let alreadyTracked = existingRecurring.contains { existing in
                    existing.name.lowercased().contains(merchant.lowercased()) ||
                    merchant.lowercased().contains(existing.name.lowercased())
                }
                guard !alreadyTracked else { continue }

                // Calculate confidence
                var confidence = 0.5
                if txns.count >= 4 { confidence += 0.15 }
                if txns.count >= 6 { confidence += 0.1 }
                if isConsistentAmount { confidence += 0.2 }
                if amountVariance < 0.05 { confidence += 0.1 } // Very consistent
                confidence = min(0.95, confidence)

                let category = sorted.first?.category.storageKey ?? "bills"

                results.append(DetectedRecurring(
                    merchantName: merchant,
                    amount: avgAmount,
                    frequency: frequency,
                    confidence: confidence,
                    matchingTransactions: sorted,
                    suggestedCategory: category
                ))
            }
        }

        return results.sorted { $0.confidence > $1.confidence }
    }

    /// Quick summary for AI context.
    func summary(transactions: [Transaction], existingRecurring: [RecurringTransaction]) -> String {
        let detected = detect(transactions: transactions, existingRecurring: existingRecurring)
        guard !detected.isEmpty else { return "" }

        var lines = ["DETECTED RECURRING PATTERNS (not yet tracked):"]
        for d in detected.prefix(5) {
            let amt = formatCents(d.amount)
            lines.append("  \(d.merchantName): ~\(amt)/\(d.frequency.rawValue) (conf: \(Int(d.confidence * 100))%)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Analysis

    private func groupByMerchant(_ transactions: [Transaction]) -> [String: [Transaction]] {
        var groups: [String: [Transaction]] = [:]

        for txn in transactions where txn.type == .expense {
            let key = normalizeMerchant(txn.note)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(txn)
        }

        return groups
    }

    /// Normalize merchant name for grouping.
    private func normalizeMerchant(_ note: String) -> String {
        let lower = note.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove common suffixes/prefixes
        let removals = ["payment", "charge", "#", "ref:", "invoice", "bill",
                        "پرداخت", "فاکتور", "قبض"]
        var result = lower
        for removal in removals {
            result = result.replacingOccurrences(of: removal, with: "")
        }

        // Remove numbers at the end (invoice numbers, etc.)
        if let range = result.range(of: "\\s*\\d+\\s*$", options: .regularExpression) {
            result = String(result[..<range.lowerBound])
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Calculate day intervals between consecutive transactions.
    private func calculateIntervals(_ sorted: [Transaction]) -> [Int] {
        guard sorted.count >= 2 else { return [] }
        var intervals: [Int] = []
        for i in 1..<sorted.count {
            let days = Calendar.current.dateComponents([.day],
                from: sorted[i - 1].date, to: sorted[i].date).day ?? 0
            if days > 0 { intervals.append(days) }
        }
        return intervals
    }

    /// Detect the most likely frequency from intervals.
    private func detectFrequency(_ intervals: [Int]) -> DetectedRecurring.EstimatedFrequency? {
        guard !intervals.isEmpty else { return nil }

        let avg = intervals.reduce(0, +) / intervals.count

        let frequencies: [DetectedRecurring.EstimatedFrequency] = [
            .weekly, .biweekly, .monthly, .quarterly, .yearly
        ]

        for freq in frequencies {
            if freq.dayRange.contains(avg) {
                // Check that most intervals fall within range
                let inRange = intervals.filter { freq.dayRange.contains($0) }.count
                if Double(inRange) / Double(intervals.count) > 0.6 {
                    return freq
                }
            }
        }

        return nil
    }

    /// Calculate coefficient of variation (0 = identical, 1 = highly variable).
    private func calculateVariance(_ amounts: [Int]) -> Double {
        guard amounts.count > 1 else { return 0 }
        let avg = Double(amounts.reduce(0, +)) / Double(amounts.count)
        guard avg > 0 else { return 0 }
        let variance = amounts.map { pow(Double($0) - avg, 2) }.reduce(0, +) / Double(amounts.count)
        return sqrt(variance) / avg
    }

    private func formatCents(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100.0)
    }
}
