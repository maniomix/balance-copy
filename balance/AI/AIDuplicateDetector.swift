import Foundation

// ============================================================
// MARK: - AI Duplicate Detector
// ============================================================
//
// Phase 3 deliverable: detects duplicate and near-duplicate
// transactions in the user's data.
//
// Runs heuristically (no LLM) — checks amount, date, category,
// note similarity. Produces a ranked list of likely duplicates
// for user review.
//
// ============================================================

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let transactions: [Transaction]
    let confidence: Double         // 0–1
    let reason: DuplicateReason

    enum DuplicateReason: String {
        case exactMatch         // Same amount + date + category
        case sameDay            // Same amount + date, different category
        case nearDate           // Same amount, ±1 day
        case sameNote           // Same note text + similar amount
        case roundedMatch       // Amounts differ by rounding (<$1)
    }

    var suggestedAction: String {
        switch reason {
        case .exactMatch:
            return "These look identical — consider deleting one."
        case .sameDay:
            return "Same amount on the same day — could be a double charge."
        case .nearDate:
            return "Same amount on consecutive days — possible duplicate."
        case .sameNote:
            return "Similar notes and amounts — might be the same expense."
        case .roundedMatch:
            return "Very similar amounts — could be tip/tax rounding."
        }
    }
}

@MainActor
class AIDuplicateDetector {
    static let shared = AIDuplicateDetector()

    private init() {}

    // MARK: - Detect Duplicates

    /// Scan transactions for duplicates within a given month.
    func detectDuplicates(in transactions: [Transaction], month: Date? = nil) -> [DuplicateGroup] {
        let txns: [Transaction]
        if let month {
            txns = transactions.filter {
                Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
            }
        } else {
            txns = transactions
        }

        var groups: [DuplicateGroup] = []

        // ── Pass 1: Exact matches (same amount + date + category) ──
        groups.append(contentsOf: findExactMatches(txns))

        // ── Pass 2: Same-day matches (same amount + date, any category) ──
        groups.append(contentsOf: findSameDayMatches(txns, excluding: groups))

        // ── Pass 3: Near-date matches (same amount, ±1 day) ──
        groups.append(contentsOf: findNearDateMatches(txns, excluding: groups))

        // ── Pass 4: Similar note matches ──
        groups.append(contentsOf: findSimilarNoteMatches(txns, excluding: groups))

        // Sort by confidence (highest first)
        return groups.sorted { $0.confidence > $1.confidence }
    }

    /// Quick count for UI display.
    func duplicateCount(in transactions: [Transaction], month: Date? = nil) -> Int {
        detectDuplicates(in: transactions, month: month).count
    }

    // MARK: - Detection Passes

    private func findExactMatches(_ txns: [Transaction]) -> [DuplicateGroup] {
        var groups: [String: [Transaction]] = [:]

        for txn in txns {
            let key = "\(txn.amount)|\(dayKey(txn.date))|\(txn.category.storageKey)|\(txn.type.rawValue)"
            groups[key, default: []].append(txn)
        }

        return groups.values.compactMap { group in
            guard group.count > 1 else { return nil }
            return DuplicateGroup(transactions: group, confidence: 0.95, reason: .exactMatch)
        }
    }

    private func findSameDayMatches(_ txns: [Transaction], excluding existing: [DuplicateGroup]) -> [DuplicateGroup] {
        let existingIds = Set(existing.flatMap { $0.transactions.map(\.id) })
        let filtered = txns.filter { !existingIds.contains($0.id) }

        var groups: [String: [Transaction]] = [:]
        for txn in filtered {
            let key = "\(txn.amount)|\(dayKey(txn.date))|\(txn.type.rawValue)"
            groups[key, default: []].append(txn)
        }

        return groups.values.compactMap { group in
            guard group.count > 1 else { return nil }
            // Different categories → lower confidence
            return DuplicateGroup(transactions: group, confidence: 0.75, reason: .sameDay)
        }
    }

    private func findNearDateMatches(_ txns: [Transaction], excluding existing: [DuplicateGroup]) -> [DuplicateGroup] {
        let existingIds = Set(existing.flatMap { $0.transactions.map(\.id) })
        let filtered = txns.filter { !existingIds.contains($0.id) }
            .sorted { $0.date < $1.date }

        var groups: [DuplicateGroup] = []
        var used: Set<UUID> = []

        for i in 0..<filtered.count {
            guard !used.contains(filtered[i].id) else { continue }
            for j in (i + 1)..<filtered.count {
                guard !used.contains(filtered[j].id) else { continue }
                let dayDiff = abs(Calendar.current.dateComponents([.day],
                    from: filtered[i].date, to: filtered[j].date).day ?? 99)

                if dayDiff <= 1 && filtered[i].amount == filtered[j].amount &&
                   filtered[i].type == filtered[j].type {
                    groups.append(DuplicateGroup(
                        transactions: [filtered[i], filtered[j]],
                        confidence: 0.6,
                        reason: .nearDate
                    ))
                    used.insert(filtered[i].id)
                    used.insert(filtered[j].id)
                    break
                }
            }
        }

        return groups
    }

    private func findSimilarNoteMatches(_ txns: [Transaction], excluding existing: [DuplicateGroup]) -> [DuplicateGroup] {
        let existingIds = Set(existing.flatMap { $0.transactions.map(\.id) })
        let filtered = txns.filter { !existingIds.contains($0.id) && !$0.note.isEmpty }

        var groups: [DuplicateGroup] = []
        var used: Set<UUID> = []

        for i in 0..<filtered.count {
            guard !used.contains(filtered[i].id) else { continue }
            for j in (i + 1)..<filtered.count {
                guard !used.contains(filtered[j].id) else { continue }

                let noteSimilarity = stringSimilarity(filtered[i].note, filtered[j].note)
                let amountDiff = abs(filtered[i].amount - filtered[j].amount)
                let amountSimilar = amountDiff < max(100, filtered[i].amount / 10) // <$1 or <10%

                if noteSimilarity > 0.7 && amountSimilar {
                    groups.append(DuplicateGroup(
                        transactions: [filtered[i], filtered[j]],
                        confidence: 0.5,
                        reason: .sameNote
                    ))
                    used.insert(filtered[i].id)
                    used.insert(filtered[j].id)
                    break
                }
            }
        }

        return groups
    }

    // MARK: - Helpers

    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Simple string similarity (Jaccard on words).
    private func stringSimilarity(_ a: String, _ b: String) -> Double {
        let setA = Set(a.lowercased().split(separator: " ").map(String.init))
        let setB = Set(b.lowercased().split(separator: " ").map(String.init))
        guard !setA.isEmpty || !setB.isEmpty else { return 0 }
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return Double(intersection) / Double(union)
    }
}
