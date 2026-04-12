import Foundation

// ============================================================
// MARK: - AI Category Suggester
// ============================================================
//
// Rule-based auto-categorization engine.
// Suggests a category based on transaction note/merchant text.
//
// Two layers:
// 1. User history — learns from past categorizations.
// 2. Keyword rules — built-in patterns for common merchants.
//
// No LLM call needed — instant, offline, and deterministic.
//
// ============================================================

@MainActor
class AICategorySuggester {
    static let shared = AICategorySuggester()

    /// Persisted merchant→category mapping, learned from user transactions.
    private var merchantMap: [String: String] {
        didSet { save() }
    }

    private let key = "ai.merchantCategoryMap"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            self.merchantMap = saved
        } else {
            self.merchantMap = [:]
        }
    }

    // MARK: - Suggestion

    /// Suggest a category for a given note/merchant text.
    /// Returns nil if no match found.
    func suggest(note: String) -> Category? {
        let lower = note.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }

        // 1. Check learned merchant map first (user patterns > built-in)
        for (merchant, catKey) in merchantMap {
            if lower.contains(merchant) {
                return Category(storageKey: catKey)
            }
        }

        // 2. Built-in keyword rules
        return keywordMatch(lower)
    }

    /// Suggest with confidence score (0.0–1.0).
    func suggestWithConfidence(note: String) -> (category: Category, confidence: Double)? {
        let lower = note.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }

        // Learned mapping → high confidence
        for (merchant, catKey) in merchantMap {
            if lower.contains(merchant) {
                if let cat = Category(storageKey: catKey) {
                    return (cat, 0.9)
                }
            }
        }

        // Keyword match → medium confidence
        if let cat = keywordMatch(lower) {
            return (cat, 0.7)
        }

        return nil
    }

    // MARK: - Learning

    /// Learn from a confirmed transaction — associate merchant/note with category.
    func learn(note: String, category: Category) {
        let lower = note.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard lower.count >= 3 else { return }

        // Extract first 2–3 significant words as the merchant key
        let words = lower.split(separator: " ").prefix(3)
        let merchantKey = words.joined(separator: " ")
        guard !merchantKey.isEmpty else { return }

        merchantMap[merchantKey] = category.storageKey
    }

    /// Learn from all existing transactions in the store.
    func learnFromHistory(store: Store) {
        for txn in store.transactions {
            let note = txn.note.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard note.count >= 3 else { continue }
            let words = note.split(separator: " ").prefix(3)
            let merchantKey = words.joined(separator: " ")
            merchantMap[merchantKey] = txn.category.storageKey
        }
    }

    // MARK: - Built-in Keyword Rules

    private func keywordMatch(_ text: String) -> Category? {
        // Groceries
        let groceryKeywords = [
            "grocery", "supermarket", "aldi", "lidl", "rewe", "edeka", "penny",
            "netto", "kaufland", "carrefour", "tesco", "albert heijn", "spar",
            "migros", "coop", "whole foods", "trader joe"
        ]
        if groceryKeywords.contains(where: { text.contains($0) }) { return .groceries }

        // Dining
        let diningKeywords = [
            "restaurant", "cafe", "coffee", "starbucks", "mcdonald", "burger",
            "pizza", "sushi", "kebab", "bakery", "lunch", "dinner", "breakfast",
            "uber eats", "deliveroo", "lieferando", "just eat", "doordash"
        ]
        if diningKeywords.contains(where: { text.contains($0) }) { return .dining }

        // Transport
        let transportKeywords = [
            "uber", "lyft", "taxi", "bus", "train", "metro", "subway",
            "gas", "fuel", "petrol", "benzin", "shell", "bp", "parking",
            "toll", "flight", "airline", "ryanair", "lufthansa", "db bahn",
            "flixbus"
        ]
        if transportKeywords.contains(where: { text.contains($0) }) { return .transport }

        // Shopping
        let shoppingKeywords = [
            "amazon", "ebay", "zalando", "h&m", "zara", "ikea", "mediamarkt",
            "saturn", "apple store", "clothing", "shoes", "electronics"
        ]
        if shoppingKeywords.contains(where: { text.contains($0) }) { return .shopping }

        // Health
        let healthKeywords = [
            "pharmacy", "apotheke", "doctor", "arzt", "hospital", "clinic",
            "dental", "zahnarzt", "gym", "fitness", "medicine", "health"
        ]
        if healthKeywords.contains(where: { text.contains($0) }) { return .health }

        // Bills / Utilities
        let billKeywords = [
            "electricity", "strom", "water", "internet", "phone", "mobile",
            "telekom", "vodafone", "o2", "insurance", "versicherung",
            "netflix", "spotify", "disney", "youtube", "subscription"
        ]
        if billKeywords.contains(where: { text.contains($0) }) { return .bills }

        // Rent
        let rentKeywords = [
            "rent", "miete", "landlord", "vermieter", "housing", "wohnung"
        ]
        if rentKeywords.contains(where: { text.contains($0) }) { return .rent }

        // Education
        let educationKeywords = [
            "university", "college", "school", "course", "udemy", "book",
            "tuition", "studien", "schule", "library"
        ]
        if educationKeywords.contains(where: { text.contains($0) }) { return .education }

        return nil
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(merchantMap) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
