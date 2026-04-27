import Foundation
import Combine

// ============================================================
// MARK: - AI User Preferences
// ============================================================
//
// Learns and remembers user behavior patterns to personalize
// AI responses. Persisted in UserDefaults.
//
// Tracks:
//   • Preferred language (detected from chat messages)
//   • Most used categories
//   • Average expense amount
//   • Typical transaction times
//   • Preferred payment methods
//   • Custom prompt patterns (what users ask most)
//
// ============================================================

@MainActor
class AIUserPreferences: ObservableObject {
    static let shared = AIUserPreferences()

    // MARK: - Published State

    @Published private(set) var preferredLanguage: String  // "en", "fa", "de"
    @Published private(set) var topCategories: [String]     // top 5 category keys
    @Published private(set) var averageExpense: Int          // cents
    @Published private(set) var typicalBudget: Int           // cents
    @Published private(set) var commonPrompts: [String]      // recent unique prompts
    @Published private(set) var spendingPeakDay: Int?        // day of week (1=Sun, 7=Sat)
    @Published private(set) var preferredPaymentMethod: String?

    // MARK: - Internal Counters

    private var languageCounts: [String: Int]
    private var categoryCounts: [String: Int]
    private var totalExpenseAmount: Int
    private var expenseCount: Int
    private var dayOfWeekCounts: [Int: Int]
    private var paymentMethodCounts: [String: Int]

    private let key = "ai.userPreferences"

    // MARK: - Init

    private init() {
        // Load persisted state
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(StoredPreferences.self, from: data) {
            self.preferredLanguage = saved.preferredLanguage
            self.topCategories = saved.topCategories
            self.averageExpense = saved.averageExpense
            self.typicalBudget = saved.typicalBudget
            self.commonPrompts = saved.commonPrompts
            self.spendingPeakDay = saved.spendingPeakDay
            self.preferredPaymentMethod = saved.preferredPaymentMethod
            self.languageCounts = saved.languageCounts
            self.categoryCounts = saved.categoryCounts
            self.totalExpenseAmount = saved.totalExpenseAmount
            self.expenseCount = saved.expenseCount
            self.dayOfWeekCounts = saved.dayOfWeekCounts
            self.paymentMethodCounts = saved.paymentMethodCounts
        } else {
            self.preferredLanguage = "en"
            self.topCategories = []
            self.averageExpense = 0
            self.typicalBudget = 0
            self.commonPrompts = []
            self.spendingPeakDay = nil
            self.preferredPaymentMethod = nil
            self.languageCounts = [:]
            self.categoryCounts = [:]
            self.totalExpenseAmount = 0
            self.expenseCount = 0
            self.dayOfWeekCounts = [:]
            self.paymentMethodCounts = [:]
        }
    }

    // MARK: - Learning

    /// Learn from a user's chat message.
    func learnFromMessage(_ text: String) {
        // Detect language
        let lang = detectLanguage(text)
        languageCounts[lang, default: 0] += 1
        preferredLanguage = languageCounts.max(by: { $0.value < $1.value })?.key ?? "en"

        // Track prompt patterns (keep last 20 unique)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 5 && !commonPrompts.contains(trimmed) {
            commonPrompts.append(trimmed)
            if commonPrompts.count > 20 {
                commonPrompts.removeFirst()
            }
        }

        save()
    }

    /// Learn from transaction data (call on app launch with store).
    func learnFromTransactions(store: Store) {
        categoryCounts = [:]
        totalExpenseAmount = 0
        expenseCount = 0
        dayOfWeekCounts = [:]
        paymentMethodCounts = [:]

        for txn in store.transactions where txn.type == .expense {
            // Category counts
            categoryCounts[txn.category.storageKey, default: 0] += 1

            // Average expense
            totalExpenseAmount += txn.amount
            expenseCount += 1

            // Day of week
            let weekday = Calendar.current.component(.weekday, from: txn.date)
            dayOfWeekCounts[weekday, default: 0] += 1

            // Payment method
            paymentMethodCounts[txn.paymentMethod.rawValue, default: 0] += 1
        }

        // Compute derived values
        topCategories = categoryCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map(\.key)

        averageExpense = expenseCount > 0 ? totalExpenseAmount / expenseCount : 0

        spendingPeakDay = dayOfWeekCounts
            .max(by: { $0.value < $1.value })?.key

        preferredPaymentMethod = paymentMethodCounts
            .max(by: { $0.value < $1.value })?.key

        // Budget learning
        let currentMonthKey = Store.monthKey(Date())
        if let budget = store.budgetsByMonth[currentMonthKey], budget > 0 {
            typicalBudget = budget
        }

        save()
    }

    // MARK: - Context for AI

    /// Generate a preferences summary for the system prompt.
    func contextSummary() -> String {
        var parts: [String] = []

        // Language preference — guides response language
        parts.append("User language: \(preferredLanguage) (\(languageDetail))")

        // Spending categories — ranked with counts
        if !topCategories.isEmpty {
            let ranked = topCategories.prefix(5).compactMap { cat -> String? in
                guard let count = categoryCounts[cat] else { return cat }
                return "\(cat)(\(count)x)"
            }
            parts.append("Top spending categories: \(ranked.joined(separator: ", "))")
        }

        // Amount context — helps model pick reasonable defaults
        if averageExpense > 0 {
            let avg = String(format: "$%.2f", Double(averageExpense) / 100.0)
            parts.append("Average expense: \(avg) (\(expenseCount) total transactions)")
        }
        if typicalBudget > 0 {
            let budget = String(format: "$%.2f", Double(typicalBudget) / 100.0)
            parts.append("Typical monthly budget: \(budget)")
        }

        // Spending timing patterns
        if let peak = spendingPeakDay {
            let dayName = Calendar.current.weekdaySymbols[peak - 1]
            parts.append("Spends most on: \(dayName)s")
        }

        // Common interaction patterns — what the user usually asks about
        let promptPatterns = extractPromptPatterns()
        if !promptPatterns.isEmpty {
            parts.append("Common requests: \(promptPatterns.joined(separator: ", "))")
        }

        return parts.isEmpty ? "" : "USER PREFERENCES\n" + parts.joined(separator: "\n")
    }

    /// Detect what kinds of things the user typically asks about.
    private var languageDetail: String {
        let total = languageCounts.values.reduce(0, +)
        guard total > 0 else { return "default" }
        let sorted = languageCounts.sorted { $0.value > $1.value }
        if sorted.count == 1 { return "always" }
        let top = sorted[0]
        let pct = Int(Double(top.value) / Double(total) * 100)
        return "\(pct)% of messages"
    }

    /// Extract high-level patterns from common prompts.
    private func extractPromptPatterns() -> [String] {
        guard commonPrompts.count >= 3 else { return [] }

        var patterns: [String: Int] = [:]
        let keywords: [(pattern: String, label: String)] = [
            ("add|اضافه|بزن", "adding transactions"),
            ("budget|بودجه", "budget management"),
            ("goal|هدف|پس.انداز", "goals & savings"),
            ("how much|چقد|spending|خرج", "spending analysis"),
            ("compare|مقایسه|بهتر", "comparisons"),
            ("tip|advice|پیشنهاد|توصیه", "seeking advice"),
            ("subscription|اشتراک", "subscriptions"),
            ("delete|حذف|cancel|لغو", "removing items"),
        ]

        for prompt in commonPrompts {
            let lower = prompt.lowercased()
            for (pattern, label) in keywords {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
                    patterns[label, default: 0] += 1
                }
            }
        }

        return patterns
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)
    }

    // MARK: - Language Detection

    private func detectLanguage(_ text: String) -> String {
        // Simple heuristic: check for Farsi/Arabic Unicode range
        let farsiRange = text.unicodeScalars.filter { (0x0600...0x06FF).contains($0.value) || (0xFB50...0xFDFF).contains($0.value) }
        if farsiRange.count > text.count / 3 { return "fa" }

        // German indicators
        let germanWords = ["ich", "und", "der", "die", "das", "ist", "nicht", "haben", "werden"]
        let words = text.lowercased().split(separator: " ")
        let germanCount = words.filter { germanWords.contains(String($0)) }.count
        if germanCount >= 2 { return "de" }

        return "en"
    }

    // MARK: - Persistence

    private func save() {
        let stored = StoredPreferences(
            preferredLanguage: preferredLanguage,
            topCategories: topCategories,
            averageExpense: averageExpense,
            typicalBudget: typicalBudget,
            commonPrompts: commonPrompts,
            spendingPeakDay: spendingPeakDay,
            preferredPaymentMethod: preferredPaymentMethod,
            languageCounts: languageCounts,
            categoryCounts: categoryCounts,
            totalExpenseAmount: totalExpenseAmount,
            expenseCount: expenseCount,
            dayOfWeekCounts: dayOfWeekCounts,
            paymentMethodCounts: paymentMethodCounts
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private struct StoredPreferences: Codable {
        var preferredLanguage: String
        var topCategories: [String]
        var averageExpense: Int
        var typicalBudget: Int
        var commonPrompts: [String]
        var spendingPeakDay: Int?
        var preferredPaymentMethod: String?
        var languageCounts: [String: Int]
        var categoryCounts: [String: Int]
        var totalExpenseAmount: Int
        var expenseCount: Int
        var dayOfWeekCounts: [Int: Int]
        var paymentMethodCounts: [String: Int]
    }
}
