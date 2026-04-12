import Foundation
import Combine

// ============================================================
// MARK: - AI Merchant Memory (Phase 6)
// ============================================================
//
// Learns from user corrections to build a merchant→category
// mapping that overrides default suggestions. When a user says
// "Starbucks is coffee not dining," this memory persists that
// correction for all future transactions.
//
// Also tracks merchant-specific behavior rules:
//   • Default amount (e.g., "gym membership is always $50")
//   • Preferred note format
//   • Custom category overrides
//
// ============================================================

/// A learned merchant pattern from user behavior/corrections.
struct MerchantProfile: Codable, Identifiable {
    var id: String { merchantKey }    // Unique by normalized key
    let merchantKey: String           // Lowercased, trimmed merchant name
    var displayName: String           // Original casing for display
    var category: String              // Learned category storageKey
    var defaultAmount: Int?           // Typical amount in cents (learned from history)
    var preferredNote: String?        // Preferred note text
    var correctionCount: Int          // How many times user corrected to this category
    var lastUsed: Date
    var transactionCount: Int         // How many times this merchant appeared

    /// Confidence increases with more corrections.
    var confidence: Double {
        if correctionCount >= 3 { return 0.95 }
        if correctionCount >= 2 { return 0.85 }
        if correctionCount >= 1 { return 0.75 }
        return Double(min(transactionCount, 10)) / 15.0 + 0.3
    }
}

@MainActor
class AIMerchantMemory: ObservableObject {
    static let shared = AIMerchantMemory()

    @Published private(set) var merchants: [String: MerchantProfile] = [:]

    private let key = "ai.merchantMemory"

    private init() {
        load()
    }

    // MARK: - Query

    /// Look up a merchant profile by note/merchant text.
    func lookup(_ note: String) -> MerchantProfile? {
        let normalized = normalize(note)
        guard !normalized.isEmpty else { return nil }

        // Exact match
        if let profile = merchants[normalized] {
            return profile
        }

        // Partial match — check if any known merchant is a substring
        for (key, profile) in merchants {
            if normalized.contains(key) || key.contains(normalized) {
                return profile
            }
        }

        return nil
    }

    /// Suggest a category based on merchant memory.
    /// Returns nil if no memory exists.
    func suggestCategory(for note: String) -> (category: String, confidence: Double)? {
        guard let profile = lookup(note) else { return nil }
        return (profile.category, profile.confidence)
    }

    /// Get the default amount for a merchant, if learned.
    func suggestAmount(for note: String) -> Int? {
        lookup(note)?.defaultAmount
    }

    // MARK: - Learning

    /// Learn from a user correction: "X should be category Y."
    func learnCorrection(merchantNote: String, correctCategory: String) {
        let normalized = normalize(merchantNote)
        guard !normalized.isEmpty else { return }

        if var existing = merchants[normalized] {
            existing.category = correctCategory
            existing.correctionCount += 1
            existing.lastUsed = Date()
            merchants[normalized] = existing
        } else {
            merchants[normalized] = MerchantProfile(
                merchantKey: normalized,
                displayName: merchantNote.trimmingCharacters(in: .whitespacesAndNewlines),
                category: correctCategory,
                defaultAmount: nil,
                preferredNote: nil,
                correctionCount: 1,
                lastUsed: Date(),
                transactionCount: 1
            )
        }

        // Also update AICategorySuggester for backward compatibility
        if let cat = Category(storageKey: correctCategory) {
            AICategorySuggester.shared.learn(note: merchantNote, category: cat)
        }

        save()
    }

    /// Learn from a confirmed transaction (passive learning).
    func learnFromTransaction(note: String, category: String, amount: Int) {
        let normalized = normalize(note)
        guard !normalized.isEmpty else { return }

        if var existing = merchants[normalized] {
            existing.transactionCount += 1
            existing.lastUsed = Date()
            // Update default amount using running average
            if let prev = existing.defaultAmount {
                existing.defaultAmount = (prev + amount) / 2
            } else {
                existing.defaultAmount = amount
            }
            // Only update category from transaction if no corrections exist
            if existing.correctionCount == 0 {
                existing.category = category
            }
            merchants[normalized] = existing
        } else {
            merchants[normalized] = MerchantProfile(
                merchantKey: normalized,
                displayName: note.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                defaultAmount: amount,
                preferredNote: nil,
                correctionCount: 0,
                lastUsed: Date(),
                transactionCount: 1
            )
        }

        save()
    }

    /// Bulk learn from transaction history.
    func learnFromHistory(store: Store) {
        for txn in store.transactions where !txn.note.isEmpty {
            learnFromTransaction(
                note: txn.note,
                category: txn.category.storageKey,
                amount: txn.amount
            )
        }
    }

    // MARK: - Management

    /// Delete a merchant profile.
    func forget(_ merchantKey: String) {
        merchants.removeValue(forKey: merchantKey)
        save()
    }

    /// Clear all merchant memory.
    func clearAll() {
        merchants.removeAll()
        save()
    }

    /// Get top merchants sorted by usage.
    func topMerchants(limit: Int = 20) -> [MerchantProfile] {
        Array(merchants.values
            .sorted { $0.transactionCount > $1.transactionCount }
            .prefix(limit))
    }

    /// Get recently corrected merchants.
    func recentCorrections(limit: Int = 10) -> [MerchantProfile] {
        Array(merchants.values
            .filter { $0.correctionCount > 0 }
            .sorted { $0.lastUsed > $1.lastUsed }
            .prefix(limit))
    }

    // MARK: - Context for System Prompt

    /// Generate merchant memory context for the AI prompt.
    func contextSummary() -> String {
        let corrected = merchants.values
            .filter { $0.correctionCount > 0 }
            .sorted { $0.correctionCount > $1.correctionCount }
            .prefix(10)

        guard !corrected.isEmpty else { return "" }

        var lines = ["MERCHANT MEMORY (user-corrected categories):"]
        for m in corrected {
            lines.append("  \(m.displayName) → \(m.category) (corrected \(m.correctionCount)x)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func normalize(_ note: String) -> String {
        note.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .prefix(3)
            .joined(separator: " ")
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: MerchantProfile].self, from: data) {
            merchants = saved
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(merchants) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
