import Foundation
import Combine

// ============================================================
// MARK: - AI Event Bus (Phase 5)
// ============================================================
//
// Monitors app events and dispatches them to watch rules
// and the insight engine. Acts as the nervous system for
// proactive AI features.
//
// Events: transaction added/edited/deleted, budget threshold
// crossed, goal milestone, subscription renewal, etc.
//
// ============================================================

/// An event that occurs in the app, dispatched to observers.
struct AIEvent: Identifiable {
    let id = UUID()
    let type: EventType
    let timestamp: Date
    let payload: [String: String]     // Flexible key-value data

    enum EventType: String, Codable {
        // Transaction events
        case transactionAdded
        case transactionEdited
        case transactionDeleted

        // Budget events
        case budgetSet
        case budgetThreshold50
        case budgetThreshold80
        case budgetExceeded
        case categoryBudgetExceeded

        // Goal events
        case goalCreated
        case goalContribution
        case goalMilestone25
        case goalMilestone50
        case goalMilestone75
        case goalCompleted

        // Subscription events
        case subscriptionAdded
        case subscriptionRenewing
        case subscriptionCancelled
        case subscriptionPriceChange

        // Account events
        case balanceUpdated
        case transferCompleted

        // Recurring events
        case recurringAdded
        case recurringCancelled

        // Periodic events
        case dailyCheck
        case weeklyCheck
        case monthStart
        case monthEnd
    }

    init(type: EventType, payload: [String: String] = [:]) {
        self.type = type
        self.timestamp = Date()
        self.payload = payload
    }
}

/// A user-defined watch rule that triggers when conditions are met.
struct AIWatchRule: Identifiable, Codable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var trigger: WatchTrigger
    var condition: WatchCondition
    var action: WatchAction

    init(name: String, trigger: WatchTrigger, condition: WatchCondition, action: WatchAction) {
        self.id = UUID()
        self.name = name
        self.isEnabled = true
        self.trigger = trigger
        self.condition = condition
        self.action = action
    }

    enum WatchTrigger: String, Codable, CaseIterable {
        case anyExpense          // Fire on any expense added
        case categoryExpense     // Fire when specific category expense added
        case budgetThreshold     // Fire when budget crosses a threshold
        case dailySpending       // Fire on daily check if daily spending exceeds limit
        case weeklySpending      // Fire on weekly check if weekly spending exceeds limit
        case goalProgress        // Fire when goal reaches milestone
        case subscriptionRenewal // Fire before subscription renewal
        case unusualExpense      // Fire when expense is X times category average
    }

    struct WatchCondition: Codable {
        var category: String?        // Category filter (nil = any)
        var thresholdAmount: Int?    // Amount threshold in cents
        var thresholdPercent: Double? // Percentage threshold (0-1)
        var multiplier: Double?      // For unusual expense detection (e.g. 3x)
        var daysBefore: Int?         // For subscription renewal warning
    }

    enum WatchAction: String, Codable, CaseIterable {
        case notification        // Push notification
        case insightBanner       // Show insight banner in app
        case both                // Both notification and banner
    }
}

@MainActor
class AIEventBus: ObservableObject {
    static let shared = AIEventBus()

    @Published var recentEvents: [AIEvent] = []
    @Published var watchRules: [AIWatchRule] = []
    @Published var triggeredAlerts: [TriggeredAlert] = []

    private let rulesKey = "ai.watchRules"
    private let maxEvents = 100
    private var cancellables = Set<AnyCancellable>()

    struct TriggeredAlert: Identifiable {
        let id = UUID()
        let rule: AIWatchRule
        let event: AIEvent
        let message: String
        let timestamp: Date
    }

    private init() {
        loadRules()
    }

    // MARK: - Dispatch Events

    /// Post an event to the bus. All watch rules are evaluated.
    func post(_ event: AIEvent) {
        recentEvents.insert(event, at: 0)
        if recentEvents.count > maxEvents {
            recentEvents = Array(recentEvents.prefix(maxEvents))
        }

        // Evaluate watch rules
        evaluateRules(for: event)
    }

    /// Convenience: post a transaction-added event with details.
    func postTransactionAdded(amount: Int, category: String, note: String, type: String) {
        post(AIEvent(type: .transactionAdded, payload: [
            "amount": "\(amount)",
            "category": category,
            "note": note,
            "transactionType": type
        ]))
    }

    /// Post a budget threshold event.
    func postBudgetThreshold(ratio: Double, spent: Int, budget: Int) {
        let eventType: AIEvent.EventType
        if ratio >= 1.0 {
            eventType = .budgetExceeded
        } else if ratio >= 0.8 {
            eventType = .budgetThreshold80
        } else if ratio >= 0.5 {
            eventType = .budgetThreshold50
        } else {
            return
        }

        post(AIEvent(type: eventType, payload: [
            "ratio": String(format: "%.2f", ratio),
            "spent": "\(spent)",
            "budget": "\(budget)"
        ]))
    }

    /// Post a goal milestone event.
    func postGoalMilestone(goalName: String, progress: Double) {
        let eventType: AIEvent.EventType
        if progress >= 1.0 {
            eventType = .goalCompleted
        } else if progress >= 0.75 {
            eventType = .goalMilestone75
        } else if progress >= 0.5 {
            eventType = .goalMilestone50
        } else if progress >= 0.25 {
            eventType = .goalMilestone25
        } else {
            return
        }

        post(AIEvent(type: eventType, payload: [
            "goalName": goalName,
            "progress": String(format: "%.0f", progress * 100)
        ]))
    }

    // MARK: - Watch Rules Management

    func addRule(_ rule: AIWatchRule) {
        watchRules.append(rule)
        saveRules()
    }

    func updateRule(_ rule: AIWatchRule) {
        if let idx = watchRules.firstIndex(where: { $0.id == rule.id }) {
            watchRules[idx] = rule
            saveRules()
        }
    }

    func deleteRule(_ id: UUID) {
        watchRules.removeAll { $0.id == id }
        saveRules()
    }

    func toggleRule(_ id: UUID) {
        if let idx = watchRules.firstIndex(where: { $0.id == id }) {
            watchRules[idx].isEnabled.toggle()
            saveRules()
        }
    }

    // MARK: - Default Rules

    /// Create sensible default watch rules for new users.
    func setupDefaults() {
        guard watchRules.isEmpty else { return }

        let defaults: [AIWatchRule] = [
            AIWatchRule(
                name: "Budget 80% warning",
                trigger: .budgetThreshold,
                condition: .init(thresholdPercent: 0.8),
                action: .both
            ),
            AIWatchRule(
                name: "Large expense alert",
                trigger: .unusualExpense,
                condition: .init(multiplier: 3.0),
                action: .insightBanner
            ),
            AIWatchRule(
                name: "Daily spending limit",
                trigger: .dailySpending,
                condition: .init(thresholdAmount: 10000), // $100
                action: .insightBanner
            ),
            AIWatchRule(
                name: "Subscription renewal reminder",
                trigger: .subscriptionRenewal,
                condition: .init(daysBefore: 3),
                action: .notification
            )
        ]

        watchRules = defaults
        saveRules()
    }

    // MARK: - Rule Evaluation

    private func evaluateRules(for event: AIEvent) {
        for rule in watchRules where rule.isEnabled {
            if let message = ruleMatches(rule, event: event) {
                let alert = TriggeredAlert(
                    rule: rule,
                    event: event,
                    message: message,
                    timestamp: Date()
                )
                triggeredAlerts.insert(alert, at: 0)

                // Generate insight for the banner
                if rule.action == .insightBanner || rule.action == .both {
                    AIInsightEngine.shared.eventInsight = AIInsight(
                        type: .patternDetected,
                        title: rule.name,
                        body: message,
                        severity: .warning
                    )
                }
            }
        }
    }

    private func ruleMatches(_ rule: AIWatchRule, event: AIEvent) -> String? {
        switch rule.trigger {
        case .anyExpense:
            guard event.type == .transactionAdded,
                  event.payload["transactionType"] == "expense" else { return nil }
            let amount = Int(event.payload["amount"] ?? "0") ?? 0
            return "New expense: \(formatCents(amount)) for \(event.payload["note"] ?? "unknown")"

        case .categoryExpense:
            guard event.type == .transactionAdded,
                  let cat = event.payload["category"],
                  cat == rule.condition.category else { return nil }
            let amount = Int(event.payload["amount"] ?? "0") ?? 0
            return "\(cat.capitalized) expense: \(formatCents(amount))"

        case .budgetThreshold:
            guard event.type == .budgetThreshold80 || event.type == .budgetExceeded else { return nil }
            let ratio = Double(event.payload["ratio"] ?? "0") ?? 0
            if let threshold = rule.condition.thresholdPercent, ratio >= threshold {
                let pct = Int(ratio * 100)
                return "Budget is at \(pct)% — \(event.payload["spent"] ?? "?") of \(event.payload["budget"] ?? "?")"
            }
            return nil

        case .dailySpending:
            guard event.type == .dailyCheck else { return nil }
            let dailySpent = Int(event.payload["dailySpent"] ?? "0") ?? 0
            if let threshold = rule.condition.thresholdAmount, dailySpent > threshold {
                return "Daily spending \(formatCents(dailySpent)) exceeds your \(formatCents(threshold)) limit"
            }
            return nil

        case .weeklySpending:
            guard event.type == .weeklyCheck else { return nil }
            let weeklySpent = Int(event.payload["weeklySpent"] ?? "0") ?? 0
            if let threshold = rule.condition.thresholdAmount, weeklySpent > threshold {
                return "Weekly spending \(formatCents(weeklySpent)) exceeds your \(formatCents(threshold)) limit"
            }
            return nil

        case .goalProgress:
            guard event.type == .goalMilestone50 || event.type == .goalMilestone75 ||
                  event.type == .goalCompleted else { return nil }
            let name = event.payload["goalName"] ?? "Your goal"
            let pct = event.payload["progress"] ?? "?"
            return "\"\(name)\" reached \(pct)%!"

        case .subscriptionRenewal:
            guard event.type == .subscriptionRenewing else { return nil }
            let name = event.payload["subscriptionName"] ?? "A subscription"
            let days = event.payload["daysUntil"] ?? "?"
            return "\(name) renews in \(days) day(s)"

        case .unusualExpense:
            guard event.type == .transactionAdded,
                  event.payload["transactionType"] == "expense" else { return nil }
            let amount = Int(event.payload["amount"] ?? "0") ?? 0
            let avgStr = event.payload["categoryAverage"] ?? "0"
            let avg = Int(avgStr) ?? 0
            if let mult = rule.condition.multiplier, avg > 0, Double(amount) > Double(avg) * mult {
                return "Unusual expense: \(formatCents(amount)) is \(amount / max(avg, 1))x your average"
            }
            return nil
        }
    }

    func clearAlerts() {
        triggeredAlerts.removeAll()
    }

    // MARK: - Periodic Checks

    /// Run daily check — call from app lifecycle or background task.
    func runDailyCheck(store: Store) {
        let today = Date()
        let todayExpenses = store.transactions.filter {
            $0.type == .expense && Calendar.current.isDateInToday($0.date)
        }
        let dailySpent = todayExpenses.reduce(0) { $0 + $1.amount }

        post(AIEvent(type: .dailyCheck, payload: [
            "dailySpent": "\(dailySpent)",
            "transactionCount": "\(todayExpenses.count)"
        ]))

        // Check budget thresholds
        let monthKey = Store.monthKey(today)
        let budget = store.budgetsByMonth[monthKey] ?? 0
        if budget > 0 {
            let spent = store.spent(for: today)
            let ratio = Double(spent) / Double(budget)
            postBudgetThreshold(ratio: ratio, spent: spent, budget: budget)
        }
    }

    /// Run weekly check — call on Sunday or from background task.
    func runWeeklyCheck(store: Store) {
        let calendar = Calendar.current
        let now = Date()
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return }

        let weekExpenses = store.transactions.filter {
            $0.type == .expense && $0.date >= weekAgo && $0.date <= now
        }
        let weeklySpent = weekExpenses.reduce(0) { $0 + $1.amount }

        post(AIEvent(type: .weeklyCheck, payload: [
            "weeklySpent": "\(weeklySpent)",
            "transactionCount": "\(weekExpenses.count)"
        ]))
    }

    // MARK: - Persistence

    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: rulesKey),
           let saved = try? JSONDecoder().decode([AIWatchRule].self, from: data) {
            watchRules = saved
        }
    }

    private func saveRules() {
        if let data = try? JSONEncoder().encode(watchRules) {
            UserDefaults.standard.set(data, forKey: rulesKey)
        }
    }

    // MARK: - Helpers

    private func formatCents(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100.0)
    }
}
