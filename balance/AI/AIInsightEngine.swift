import Foundation
import Combine
@preconcurrency import UserNotifications

// ============================================================
// MARK: - AI Insight Engine
// ============================================================
//
// Generates proactive insights from the user's financial data
// without requiring a chat interaction. These appear as banners
// on the dashboard, in the morning briefing, etc.
//
// Pure heuristic analysis — no LLM call needed for most insights.
// For complex pattern descriptions, optionally uses AIManager.
//
// ============================================================

@MainActor
class AIInsightEngine: ObservableObject {

    static let shared = AIInsightEngine()

    @Published var insights: [AIInsight] = []
    @Published var morningBriefing: AIInsight?

    private init() {}

    // MARK: - Generate All Insights

    /// Refreshes insights based on current app state. Call on app launch and after data changes.
    func refresh(store: Store) {
        var new: [AIInsight] = []

        new.append(contentsOf: budgetInsights(store: store))
        new.append(contentsOf: spendingInsights(store: store))
        new.append(contentsOf: goalInsights())
        new.append(contentsOf: subscriptionInsights())
        new.append(contentsOf: householdInsights())
        new.append(contentsOf: duplicateInsights(store: store))
        new.append(contentsOf: recurringInsights(store: store))

        // Phase 2: Store-based detector pack (cashflow runway, income drop,
        // recurring overdue, day spike, new merchant, duplicate transactions).
        new.append(contentsOf: AIInsightDetectorsPack.all(store: store))

        // Drop any insights past their expiresAt.
        let now = Date()
        new.removeAll { ($0.expiresAt.map { $0 < now }) ?? false }

        // Dedupe by dedupeKey (first-write wins). Insights without a
        // dedupeKey are preserved as-is — they're ad-hoc event insights.
        new = dedupeByKey(new)

        // Filter out auto-muted detectors.
        new.removeAll { insight in
            guard insight.dedupeKey != nil else { return false }
            return InsightTelemetry.shared.isMuted(insight.detectorID)
        }

        // Sort by severity (critical first), then recency
        new.sort { a, b in
            if a.severity != b.severity { return severityOrder(a.severity) < severityOrder(b.severity) }
            return a.timestamp > b.timestamp
        }

        insights = new

        // Record a "shown" per surviving detector-ID.
        for insight in new where insight.dedupeKey != nil {
            InsightTelemetry.shared.recordShown(detectorID: insight.detectorID)
        }

        // Phase 7: optional LLM enrichment of the top few items' advice.
        Task { [weak self] in
            let enriched = await InsightEnricher.enrich(new)
            await MainActor.run { self?.insights = enriched }
        }
        morningBriefing = buildMorningBriefing(store: store)

        // Phase 5: Run event bus daily check
        AIEventBus.shared.runDailyCheck(store: store)

        // Update scheduled notification if enabled
        if isMorningNotificationEnabled {
            scheduleMorningNotification()
        }
    }

    // MARK: - Event-Driven Insights

    /// Called when a transaction is added. Generates instant, contextual insights.
    @Published var eventInsight: AIInsight?

    /// React to a newly added transaction.
    func onTransactionAdded(_ txn: Transaction, store: Store) {
        let month = Date()
        let monthKey = Store.monthKey(month)
        let budget = store.budgetsByMonth[monthKey] ?? 0

        // Check if this transaction pushes over budget
        if budget > 0 {
            let spent = store.spent(for: month)
            let ratio = Double(spent) / Double(budget)

            if ratio >= 1.0 && ratio - (Double(txn.amount) / Double(budget)) < 1.0 {
                // This transaction just pushed us over
                eventInsight = AIInsight(
                    type: .budgetWarning,
                    title: "Budget just exceeded!",
                    body: "This \(fmt(txn.amount)) \(txn.category.title) expense pushed you over your \(fmt(budget)) budget.",
                    severity: .critical
                )
                return
            }

            if ratio >= 0.8 && ratio - (Double(txn.amount) / Double(budget)) < 0.8 {
                // This transaction crossed 80% threshold
                let left = budget - spent
                eventInsight = AIInsight(
                    type: .budgetWarning,
                    title: "80% of budget used",
                    body: "Only \(fmt(left)) remaining this month. Consider slowing down spending.",
                    severity: .warning
                )
                return
            }
        }

        // Check for spending anomaly — is this transaction much larger than average?
        let recentExpenses = store.transactions.filter {
            $0.type == .expense && $0.category == txn.category &&
            Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) &&
            $0.id != txn.id
        }
        if !recentExpenses.isEmpty {
            let avg = recentExpenses.reduce(0) { $0 + $1.amount } / recentExpenses.count
            if txn.amount > avg * 3 && txn.amount > 1000 { // > 3x average and > $10
                eventInsight = AIInsight(
                    type: .spendingAnomaly,
                    title: "Unusually large expense",
                    body: "This \(fmt(txn.amount)) in \(txn.category.title) is \(txn.amount / max(avg, 1))x your average for this category.",
                    severity: .warning
                )
                return
            }
        }

        // Check category budget
        if let catBudgets = store.categoryBudgetsByMonth[monthKey],
           let catBudget = catBudgets[txn.category.storageKey], catBudget > 0 {
            let catSpent = store.transactions.filter {
                $0.type == .expense && $0.category == txn.category &&
                Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
            }.reduce(0) { $0 + $1.amount }

            if catSpent > catBudget {
                eventInsight = AIInsight(
                    type: .budgetWarning,
                    title: "\(txn.category.title) budget exceeded",
                    body: "You've spent \(fmt(catSpent)) of your \(fmt(catBudget)) \(txn.category.title) budget.",
                    severity: .warning
                )
                return
            }
        }

        // Positive: first transaction of the day — acknowledge streak
        let todayTxns = store.transactions.filter {
            Calendar.current.isDateInToday($0.date) && $0.id != txn.id
        }
        if todayTxns.isEmpty && txn.type == .expense {
            eventInsight = AIInsight(
                type: .patternDetected,
                title: "Expense logged",
                body: "Good habit! Tracking your spending helps you stay in control.",
                severity: .positive
            )
        }
    }

    /// Clear the event insight after it's been shown.
    func clearEventInsight() {
        eventInsight = nil
    }

    // MARK: - Budget Insights

    private func budgetInsights(store: Store) -> [AIInsight] {
        var results: [AIInsight] = []
        let month = Date()
        let monthKey = Store.monthKey(month)
        let budget = store.budgetsByMonth[monthKey] ?? 0
        guard budget > 0 else { return [] }

        let spent = store.spent(for: month)
        let ratio = Double(spent) / Double(budget)
        let dayOfMonth = Calendar.current.component(.day, from: month)
        let daysInMonth = Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 30
        let expectedRatio = Double(dayOfMonth) / Double(daysInMonth)

        // Over budget
        if ratio >= 1.0 {
            results.append(AIInsight(
                type: .budgetWarning,
                title: "Budget exceeded",
                body: "You've spent \(fmt(spent)) of your \(fmt(budget)) budget this month.",
                severity: .critical
            ))
        }
        // Pace ahead — spending faster than calendar pace
        else if ratio > expectedRatio + 0.15 && ratio > 0.5 {
            let pacePercent = Int(ratio * 100)
            let calPercent = Int(expectedRatio * 100)
            results.append(AIInsight(
                type: .budgetWarning,
                title: "Spending pace ahead",
                body: "You've used \(pacePercent)% of your budget but only \(calPercent)% of the month has passed.",
                severity: .warning
            ))
        }
        // Under budget with good margin — positive reinforcement
        else if ratio < expectedRatio - 0.1 && dayOfMonth > 10 {
            results.append(AIInsight(
                type: .budgetWarning,
                title: "On track",
                body: "You're under budget — \(fmt(budget - spent)) remaining with \(daysInMonth - dayOfMonth) days left.",
                severity: .positive
            ))
        }

        // Category budget warnings
        if let catBudgets = store.categoryBudgetsByMonth[monthKey] {
            let expenses = store.transactions.filter {
                $0.type == .expense &&
                Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
            }
            var catSpent: [String: Int] = [:]
            for t in expenses { catSpent[t.category.storageKey, default: 0] += t.amount }

            for (cat, catBudget) in catBudgets where catBudget > 0 {
                let spent = catSpent[cat] ?? 0
                if spent > catBudget {
                    let catName = Category(storageKey: cat)?.title ?? cat
                    results.append(AIInsight(
                        type: .budgetWarning,
                        title: "\(catName) over budget",
                        body: "\(catName): \(fmt(spent)) spent of \(fmt(catBudget)) budget.",
                        severity: .warning
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Spending Insights

    private func spendingInsights(store: Store) -> [AIInsight] {
        var results: [AIInsight] = []
        let month = Date()

        // Find anomalously large transactions (> 3x average for category)
        let monthExpenses = store.transactions.filter {
            $0.type == .expense &&
            Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
        }

        var catTotals: [String: [Int]] = [:]
        for t in monthExpenses {
            catTotals[t.category.storageKey, default: []].append(t.amount)
        }

        for (cat, amounts) in catTotals where amounts.count >= 3 {
            let avg = amounts.reduce(0, +) / amounts.count
            if let max = amounts.max(), max > avg * 3, max > 1000 { // > $10 minimum
                let catName = Category(storageKey: cat)?.title ?? cat
                results.append(AIInsight(
                    type: .spendingAnomaly,
                    title: "Unusual \(catName) expense",
                    body: "A \(fmt(max)) \(catName) transaction is \(max / avg)x your average.",
                    severity: .warning
                ))
            }
        }

        // Top spending category
        if let top = catTotals.max(by: { $0.value.reduce(0, +) < $1.value.reduce(0, +) }) {
            let total = top.value.reduce(0, +)
            let catName = Category(storageKey: top.key)?.title ?? top.key
            results.append(AIInsight(
                type: .patternDetected,
                title: "Top category: \(catName)",
                body: "You've spent \(fmt(total)) on \(catName) this month (\(top.value.count) transactions).",
                severity: .info
            ))
        }

        return results
    }

    // MARK: - Goal Insights

    private func goalInsights() -> [AIInsight] {
        var results: [AIInsight] = []
        let goals = GoalManager.shared.goals.filter { !$0.isCompleted }

        for goal in goals {
            // Nearly complete
            if goal.progress >= 0.8 && goal.progress < 1.0 {
                results.append(AIInsight(
                    type: .goalProgress,
                    title: "Almost there!",
                    body: "\"\(goal.name)\" is \(goal.progressPercent)% complete — \(fmt(goal.remainingAmount)) to go.",
                    severity: .positive,
                    suggestedAction: AIAction(
                        type: .addContribution,
                        params: AIAction.ActionParams(goalName: goal.name, contributionAmount: goal.remainingAmount)
                    )
                ))
            }
            // Overdue
            else if goal.isOverdue {
                results.append(AIInsight(
                    type: .goalProgress,
                    title: "Goal overdue",
                    body: "\"\(goal.name)\" deadline has passed — \(fmt(goal.remainingAmount)) remaining.",
                    severity: .warning
                ))
            }
            // Behind pace
            else if goal.trackingStatus == .behind {
                if let monthly = goal.requiredMonthlySaving {
                    results.append(AIInsight(
                        type: .goalProgress,
                        title: "Goal behind schedule",
                        body: "\"\(goal.name)\" needs \(fmt(monthly))/month to stay on track.",
                        severity: .warning
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Subscription Insights

    private func subscriptionInsights() -> [AIInsight] {
        var results: [AIInsight] = []
        let engine = SubscriptionEngine.shared

        // Upcoming renewals (within 3 days)
        let upcoming = engine.renewingWithin(days: 3)
        for sub in upcoming {
            results.append(AIInsight(
                type: .recurringDetected,
                title: "\(sub.merchantName) renewing soon",
                body: "\(fmt(sub.expectedAmount)) charge in \(sub.daysUntilRenewal ?? 0) day(s).",
                severity: .info
            ))
        }

        // Price increases
        for sub in engine.subscriptions where sub.hasPriceIncrease {
            if let pct = sub.priceChangePercent {
                results.append(AIInsight(
                    type: .recurringDetected,
                    title: "\(sub.merchantName) price increase",
                    body: "Up \(String(format: "%.0f", pct))% from previous charge.",
                    severity: .warning
                ))
            }
        }

        // Likely unused
        for sub in engine.subscriptions where sub.isLikelyUnused {
            results.append(AIInsight(
                type: .savingsOpportunity,
                title: "Unused subscription?",
                body: "\(sub.merchantName) (\(fmt(sub.monthlyCost))/mo) — no recent activity detected.",
                severity: .info,
                suggestedAction: AIAction(
                    type: .cancelSubscription,
                    params: AIAction.ActionParams(subscriptionName: sub.merchantName)
                )
            ))
        }

        return results
    }

    // MARK: - Household Insights

    private func householdInsights() -> [AIInsight] {
        let manager = HouseholdManager.shared
        guard manager.household != nil else { return [] }

        let uid = SupabaseManager.shared.currentUserId ?? ""
        let monthKey = Store.monthKey(Date())
        let snapshot = manager.dashboardSnapshot(monthKey: monthKey, currentUserId: uid)

        var results: [AIInsight] = []

        if snapshot.unsettledCount > 0 {
            results.append(AIInsight(
                type: .patternDetected,
                title: "Unsettled splits",
                body: "\(snapshot.unsettledCount) unsettled expense(s) totaling \(fmt(snapshot.unsettledAmount)).",
                severity: snapshot.unsettledAmount > 10000 ? .warning : .info
            ))
        }

        if snapshot.isOverBudget {
            results.append(AIInsight(
                type: .budgetWarning,
                title: "Shared budget exceeded",
                body: "Household spending has exceeded the shared budget this month.",
                severity: .warning
            ))
        }

        return results
    }

    // MARK: - Morning Briefing

    private func buildMorningBriefing(store: Store) -> AIInsight? {
        let month = Date()
        let budget = store.budgetsByMonth[Store.monthKey(month)] ?? 0
        let spent = store.spent(for: month)
        let income = store.income(for: month)
        let dayOfMonth = Calendar.current.component(.day, from: month)
        let daysInMonth = Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 30
        let remaining = daysInMonth - dayOfMonth

        var parts: [String] = []

        if budget > 0 {
            let left = budget - spent
            parts.append("Budget: \(fmt(left)) remaining (\(remaining) days left)")
        }
        if spent > 0 { parts.append("Spent \(fmt(spent)) this month") }
        if income > 0 { parts.append("Income: \(fmt(income))") }

        // Active goals progress
        let goals = GoalManager.shared.goals.filter { !$0.isCompleted }
        if !goals.isEmpty {
            let total = goals.reduce(0) { $0 + $1.progressPercent }
            let avg = total / goals.count
            parts.append("\(goals.count) active goal(s) — avg \(avg)% complete")
        }

        // Critical insights count
        let critCount = insights.filter { $0.severity == .critical || $0.severity == .warning }.count
        if critCount > 0 {
            parts.append("\(critCount) item(s) need attention")
        }

        guard !parts.isEmpty else { return nil }

        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String = {
            switch hour {
            case 5..<12:  return "Good morning"
            case 12..<17: return "Good afternoon"
            case 17..<22: return "Good evening"
            default:      return "Late night check-in"
            }
        }()

        return AIInsight(
            type: .morningBriefing,
            title: greeting,
            body: parts.joined(separator: "\n"),
            severity: .info
        )
    }

    // MARK: - Duplicate Insights (Phase 3)

    private func duplicateInsights(store: Store) -> [AIInsight] {
        let dupes = AIDuplicateDetector.shared.detectDuplicates(in: store.transactions, month: Date())
        guard !dupes.isEmpty else { return [] }

        return [AIInsight(
            type: .patternDetected,
            title: "\(dupes.count) potential duplicate(s)",
            body: "Found \(dupes.count) possible duplicate transaction group(s) this month. Tap to review.",
            severity: dupes.count > 3 ? .warning : .info
        )]
    }

    // MARK: - Recurring Detection Insights (Phase 3)

    private func recurringInsights(store: Store) -> [AIInsight] {
        let detected = AIRecurringDetector.shared.detect(
            transactions: store.transactions,
            existingRecurring: store.recurringTransactions
        )
        guard !detected.isEmpty else { return [] }

        var results: [AIInsight] = []
        for d in detected.prefix(3) where d.confidence >= 0.7 {
            let amt = String(format: "$%.2f", Double(d.amount) / 100.0)
            results.append(AIInsight(
                type: .recurringDetected,
                title: "Recurring: \(d.merchantName)",
                body: "\(d.merchantName) looks like a \(d.frequency.rawValue) payment (~\(amt)). Set up as recurring?",
                severity: .info,
                suggestedAction: AIAction(
                    type: .addRecurring,
                    params: AIAction.ActionParams(
                        amount: d.amount,
                        category: d.suggestedCategory,
                        recurringName: d.merchantName,
                        recurringFrequency: d.frequency.rawValue
                    )
                )
            ))
        }
        return results
    }

    // MARK: - Helpers

    private func fmt(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }

    private func severityOrder(_ s: AIInsight.Severity) -> Int {
        switch s {
        case .critical: return 0
        case .warning: return 1
        case .info: return 2
        case .positive: return 3
        }
    }

    // MARK: - Phase 2: Dedupe & Enrichment

    /// First-write wins for each `dedupeKey`. Insights without a dedupeKey
    /// pass through unchanged — they're ad-hoc/event insights.
    private func dedupeByKey(_ insights: [AIInsight]) -> [AIInsight] {
        var seen = Set<String>()
        var out: [AIInsight] = []
        out.reserveCapacity(insights.count)
        for insight in insights {
            guard let key = insight.dedupeKey else { out.append(insight); continue }
            if seen.insert(key).inserted { out.append(insight) }
        }
        return out
    }

    /// User-facing opt-in for LLM advice rewrites. Off by default — heuristic
    /// advice is already actionable; enrichment is a polish layer.
    @Published var isInsightEnrichmentEnabled: Bool =
        UserDefaults.standard.bool(forKey: "ai.insightEnrichment") {
        didSet { UserDefaults.standard.set(isInsightEnrichmentEnabled, forKey: "ai.insightEnrichment") }
    }

    // MARK: - Morning Briefing Push Notification

    private nonisolated static let morningNotificationId = "ai.morning.briefing"

    /// Schedule (or update) the daily morning briefing notification.
    /// Call after each refresh so the content stays current.
    func scheduleMorningNotification() {
        guard let briefing = morningBriefing else {
            cancelMorningNotification()
            return
        }

        let center = UNUserNotificationCenter.current()

        // Request permission if not yet granted
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = briefing.title
            content.body = briefing.body
            content.sound = .default
            content.categoryIdentifier = "AI_MORNING_BRIEFING"

            // Schedule for 8:00 AM daily
            var dateComponents = DateComponents()
            dateComponents.hour = 8
            dateComponents.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: Self.morningNotificationId,
                content: content,
                trigger: trigger
            )

            center.removePendingNotificationRequests(withIdentifiers: [Self.morningNotificationId])
            center.add(request) { error in
                if let error {
                    SecureLogger.error("Morning notification error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Cancel scheduled morning notification.
    func cancelMorningNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.morningNotificationId])
    }

    /// Whether morning notifications are enabled. Persisted in UserDefaults.
    @Published var isMorningNotificationEnabled: Bool = UserDefaults.standard.bool(forKey: "ai.morningNotification") {
        didSet {
            UserDefaults.standard.set(isMorningNotificationEnabled, forKey: "ai.morningNotification")
            if isMorningNotificationEnabled {
                scheduleMorningNotification()
            } else {
                cancelMorningNotification()
            }
        }
    }

    // MARK: - Weekly Review Notification

    private nonisolated static let weeklyNotificationId = "ai.weekly.review"

    /// Whether weekly review notifications are enabled.
    @Published var isWeeklyReviewEnabled: Bool = UserDefaults.standard.bool(forKey: "ai.weeklyReview") {
        didSet {
            UserDefaults.standard.set(isWeeklyReviewEnabled, forKey: "ai.weeklyReview")
            if isWeeklyReviewEnabled {
                scheduleWeeklyReview()
            } else {
                cancelWeeklyReview()
            }
        }
    }

    /// Build a weekly review summary from the last 7 days.
    func buildWeeklyReview(store: Store) -> String? {
        let calendar = Calendar.current
        let now = Date()
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }

        let weekTxns = store.transactions.filter { $0.date >= weekAgo && $0.date <= now }
        guard !weekTxns.isEmpty else { return nil }

        let expenses = weekTxns.filter { $0.type == .expense }
        let income = weekTxns.filter { $0.type == .income }
        let totalSpent = expenses.reduce(0) { $0 + $1.amount }
        let totalIncome = income.reduce(0) { $0 + $1.amount }

        var parts: [String] = []
        parts.append("This week: \(expenses.count) expenses totaling \(fmt(totalSpent))")
        if totalIncome > 0 {
            parts.append("Income: \(fmt(totalIncome))")
        }

        // Top category this week
        var catTotals: [String: Int] = [:]
        for t in expenses {
            catTotals[t.category.title, default: 0] += t.amount
        }
        if let top = catTotals.max(by: { $0.value < $1.value }) {
            parts.append("Top category: \(top.key) (\(fmt(top.value)))")
        }

        // Budget status
        let monthKey = Store.monthKey(now)
        let budget = store.budgetsByMonth[monthKey] ?? 0
        if budget > 0 {
            let monthSpent = store.spent(for: now)
            let remaining = budget - monthSpent
            parts.append("Budget remaining: \(fmt(remaining))")
        }

        return parts.joined(separator: "\n")
    }

    /// Schedule weekly review notification for Sunday at 7 PM.
    func scheduleWeeklyReview() {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Your Week in Review"
            content.body = "Tap to see your weekly spending summary."
            content.sound = .default
            content.categoryIdentifier = "AI_WEEKLY_REVIEW"

            // Every Sunday at 19:00
            var dateComponents = DateComponents()
            dateComponents.weekday = 1  // Sunday
            dateComponents.hour = 19
            dateComponents.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: Self.weeklyNotificationId,
                content: content,
                trigger: trigger
            )

            center.removePendingNotificationRequests(withIdentifiers: [Self.weeklyNotificationId])
            center.add(request) { error in
                if let error {
                    SecureLogger.error("Weekly review notification error: \(error.localizedDescription)")
                }
            }
        }
    }

    func cancelWeeklyReview() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.weeklyNotificationId])
    }
}
