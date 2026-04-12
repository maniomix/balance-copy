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

        parts.append("User language: \(preferredLanguage)")

        if !topCategories.isEmpty {
            parts.append("Top spending categories: \(topCategories.joined(separator: ", "))")
        }
        if averageExpense > 0 {
            let avg = String(format: "$%.2f", Double(averageExpense) / 100.0)
            parts.append("Average expense: \(avg)")
        }
        if typicalBudget > 0 {
            let budget = String(format: "$%.2f", Double(typicalBudget) / 100.0)
            parts.append("Typical monthly budget: \(budget)")
        }
        if let peak = spendingPeakDay {
            let dayName = Calendar.current.weekdaySymbols[peak - 1]
            parts.append("Spends most on: \(dayName)s")
        }

        return parts.isEmpty ? "" : "USER PREFERENCES\n" + parts.joined(separator: "\n")
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
