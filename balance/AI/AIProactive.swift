import Foundation
import Combine

// ============================================================
// MARK: - AI Proactive Engine (Phase 6)
// ============================================================
//
// Generates timely, structured, dismissable proactive items
// that surface finance guidance without waiting for user to ask.
//
// Builds on top of AIInsightEngine, AISafeToSpend,
// SubscriptionEngine, GoalManager, and workflow system.
//
// Features:
//   • morning briefing (structured, multi-section)
//   • weekly review
//   • monthly close prompt
//   • budget risk alerts
//   • upcoming bill warnings
//   • unusual spending alerts
//   • goal off-track nudges
//   • uncategorized / cleanup reminders
//   • dismiss / actedOn lifecycle
//   • anti-spam deduplication
//
// ============================================================

// ══════════════════════════════════════════════════════════════
// MARK: - Proactive Item Model
// ══════════════════════════════════════════════════════════════

/// The kind of proactive output.
enum ProactiveItemType: String, Codable, CaseIterable {
    case morningBriefing          = "morning_briefing"
    case weeklyReview             = "weekly_review"
    case monthlyClosePrompt       = "monthly_close_prompt"
    case budgetRisk               = "budget_risk"
    case upcomingBill             = "upcoming_bill"
    case unusualSpending          = "unusual_spending"
    case goalOffTrack             = "goal_off_track"
    case uncategorizedReminder    = "uncategorized_reminder"
    case duplicateChargeWarning   = "duplicate_charge_warning"
    case subscriptionReviewPrompt = "subscription_review_prompt"

    var icon: String {
        switch self {
        case .morningBriefing:          return "sun.max.fill"
        case .weeklyReview:             return "calendar.badge.clock"
        case .monthlyClosePrompt:       return "calendar.badge.checkmark"
        case .budgetRisk:               return "exclamationmark.triangle.fill"
        case .upcomingBill:             return "clock.badge.exclamationmark.fill"
        case .unusualSpending:          return "exclamationmark.circle.fill"
        case .goalOffTrack:             return "target"
        case .uncategorizedReminder:    return "tag.fill"
        case .duplicateChargeWarning:   return "doc.on.doc.fill"
        case .subscriptionReviewPrompt: return "repeat"
        }
    }

    var sortPriority: Int {
        switch self {
        case .budgetRisk:               return 0
        case .unusualSpending:          return 1
        case .duplicateChargeWarning:   return 2
        case .upcomingBill:             return 3
        case .goalOffTrack:             return 4
        case .monthlyClosePrompt:       return 5
        case .uncategorizedReminder:    return 6
        case .subscriptionReviewPrompt: return 7
        case .morningBriefing:          return 8
        case .weeklyReview:             return 9
        }
    }
}

/// Severity of a proactive item.
enum ProactiveSeverity: String, Codable, Comparable {
    case critical
    case warning
    case info
    case positive

    private var order: Int {
        switch self {
        case .critical: return 0
        case .warning:  return 1
        case .info:     return 2
        case .positive: return 3
        }
    }

    static func < (lhs: ProactiveSeverity, rhs: ProactiveSeverity) -> Bool {
        lhs.order < rhs.order
    }
}

/// Recommended action the user can take from a proactive item.
struct ProactiveAction: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let kind: ActionKind

    enum ActionKind {
        case startWorkflow(WorkflowType)
        case openChat
        case openIngestion
        case dismissOnly
    }

    var isDismissOnly: Bool {
        if case .dismissOnly = kind { return true }
        return false
    }
}

/// A single proactive AI output with full lifecycle.
struct ProactiveItem: Identifiable {
    let id: UUID
    let type: ProactiveItemType
    let severity: ProactiveSeverity
    let title: String
    let summary: String
    var detail: String?
    let signals: [String]             // what triggered this item
    let createdAt: Date
    var updatedAt: Date
    var isDismissed: Bool = false
    var dismissedAt: Date?
    var isActedOn: Bool = false
    var actedOnAt: Date?
    let action: ProactiveAction?

    // ── Deduplication key ──
    // Two items with the same dedup key won't coexist.
    let dedupKey: String

    // ── Structured sections (for briefings/reviews) ──
    var sections: [ProactiveBriefingSection] = []
}

/// A section inside a briefing or review item.
struct ProactiveBriefingSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let lines: [String]
    var severity: ProactiveSeverity = .info
}

// ══════════════════════════════════════════════════════════════
// MARK: - Proactive Engine
// ══════════════════════════════════════════════════════════════

@MainActor
class AIProactiveEngine: ObservableObject {
    static let shared = AIProactiveEngine()

    /// All active (non-dismissed) proactive items, sorted by priority.
    @Published private(set) var items: [ProactiveItem] = []

    /// High-priority items for dashboard banner (max 3).
    var topItems: [ProactiveItem] {
        Array(items.filter { !$0.isDismissed && $0.severity <= .warning }.prefix(3))
    }

    /// The morning briefing item, if generated.
    var morningBriefing: ProactiveItem? {
        items.first { $0.type == .morningBriefing && !$0.isDismissed }
    }

    /// The weekly review item, if generated.
    var weeklyReview: ProactiveItem? {
        items.first { $0.type == .weeklyReview && !$0.isDismissed }
    }

    // ── Dismissed dedup keys (persisted) ──
    private var dismissedKeys: Set<String> = []
    private let dismissedKeysStorageKey = "ai.proactive.dismissedKeys"

    private init() {
        loadDismissedKeys()
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Public API
    // ══════════════════════════════════════════════════════════

    /// Refresh all proactive items from current app state.
    func refresh(store: Store) {
        // Phase 9: Check if proactive items are enabled for current mode
        let modeManager = AIAssistantModeManager.shared
        let intensity = modeManager.proactiveIntensity

        guard intensity != .none else {
            items = []
            return
        }

        var generated: [ProactiveItem] = []

        generated.append(contentsOf: generateBudgetRiskItems(store: store))
        generated.append(contentsOf: generateUpcomingBillItems())
        generated.append(contentsOf: generateUnusualSpendingItems(store: store))
        generated.append(contentsOf: generateGoalItems())
        generated.append(contentsOf: generateUncategorizedReminder(store: store))
        generated.append(contentsOf: generateDuplicateWarnings(store: store))
        generated.append(contentsOf: generateSubscriptionReview())
        generated.append(contentsOf: generateMonthlyClosePrompt(store: store))

        // Add briefings (always regenerated)
        if let briefing = generateMorningBriefing(store: store) {
            generated.append(briefing)
        }
        if let review = generateWeeklyReview(store: store) {
            generated.append(review)
        }

        // Filter out dismissed items (by dedup key)
        generated = generated.filter { !dismissedKeys.contains($0.dedupKey) }

        // Phase 9: Filter by proactive intensity
        generated = applyIntensityFilter(generated, intensity: intensity)

        // Sort: severity first, then type priority
        generated.sort { a, b in
            if a.severity != b.severity { return a.severity < b.severity }
            return a.type.sortPriority < b.type.sortPriority
        }

        items = generated
    }

    /// Phase 9: Filter proactive items based on mode's proactive intensity.
    private func applyIntensityFilter(_ items: [ProactiveItem], intensity: ProactiveIntensity) -> [ProactiveItem] {
        switch intensity {
        case .none:
            return []
        case .light:
            // Only critical and warning severity items
            return items.filter { $0.severity == .critical || $0.severity == .warning }
        case .moderate:
            // All items pass through
            return items
        case .high:
            // All items pass + we could lower thresholds in generators,
            // but for now just pass everything through
            return items
        }
    }

    /// Dismiss an item. Won't reappear until the dedup key changes.
    func dismiss(_ itemId: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[idx].isDismissed = true
        items[idx].dismissedAt = Date()
        dismissedKeys.insert(items[idx].dedupKey)
        items.remove(at: idx)
        saveDismissedKeys()
    }

    /// Mark an item as acted on.
    func markActedOn(_ itemId: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[idx].isActedOn = true
        items[idx].actedOnAt = Date()
    }

    /// Clear expired dismissed keys (older items whose conditions may have changed).
    /// Called periodically — e.g. once per day or on month change.
    func clearStaleDismissals() {
        // Remove all dismissed keys — they'll only reappear if the signal still fires.
        // This is a simple approach: dismiss lasts until the next day's refresh.
        let today = Calendar.current.startOfDay(for: Date())
        let key = "ai.proactive.lastClear"
        let lastClear = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        if lastClear < today {
            dismissedKeys.removeAll()
            saveDismissedKeys()
            UserDefaults.standard.set(Date(), forKey: key)
        }
    }

    /// Active (non-dismissed) item count.
    var activeCount: Int { items.count }

    // ══════════════════════════════════════════════════════════
    // MARK: - Budget Risk
    // ══════════════════════════════════════════════════════════

    private func generateBudgetRiskItems(store: Store) -> [ProactiveItem] {
        var results: [ProactiveItem] = []
        let month = Date()
        let monthKey = Store.monthKey(month)
        let budget = store.budgetsByMonth[monthKey] ?? 0
        guard budget > 0 else { return [] }

        let spent = store.spent(for: month)
        let ratio = Double(spent) / Double(budget)
        let cal = Calendar.current
        let dayOfMonth = cal.component(.day, from: month)
        let daysInMonth = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let expectedRatio = Double(dayOfMonth) / Double(daysInMonth)
        let remaining = budget - spent
        let daysLeft = daysInMonth - dayOfMonth

        // Over budget
        if ratio >= 1.0 {
            results.append(ProactiveItem(
                id: UUID(), type: .budgetRisk, severity: .critical,
                title: "Budget Exceeded",
                summary: "You've spent \(fmtCents(spent)) of your \(fmtCents(budget)) budget — \(fmtCents(abs(remaining))) over.",
                signals: ["ratio:\(String(format: "%.0f", ratio * 100))%"],
                createdAt: Date(), updatedAt: Date(),
                action: ProactiveAction(label: "Budget Rescue", icon: "lifepreserver.fill",
                                        kind: .startWorkflow(.budgetRescue)),
                dedupKey: "budget_exceeded_\(monthKey)"
            ))
        }
        // Pace ahead — spending faster than calendar pace by 15%+
        else if ratio > expectedRatio + 0.15 && ratio > 0.5 {
            let dailyAllowance = daysLeft > 0 ? remaining / daysLeft : 0
            results.append(ProactiveItem(
                id: UUID(), type: .budgetRisk, severity: .warning,
                title: "Spending Pace Ahead",
                summary: "\(Int(ratio * 100))% used with \(daysLeft) days left. Safe daily spend: \(fmtCents(dailyAllowance)).",
                signals: ["paceAhead", "ratio:\(Int(ratio * 100))%", "expected:\(Int(expectedRatio * 100))%"],
                createdAt: Date(), updatedAt: Date(),
                action: ProactiveAction(label: "Review Budget", icon: "chart.bar.fill",
                                        kind: .startWorkflow(.budgetRescue)),
                dedupKey: "budget_pace_\(monthKey)_\(Int(ratio * 10))"
            ))
        }

        // Category budget warnings
        if let catBudgets = store.categoryBudgetsByMonth[monthKey] {
            let expenses = store.transactions.filter {
                $0.type == .expense && !$0.isTransfer && cal.isDate($0.date, equalTo: month, toGranularity: .month)
            }
            var catSpent: [String: Int] = [:]
            for t in expenses { catSpent[t.category.storageKey, default: 0] += t.amount }

            for (catKey, catBudget) in catBudgets where catBudget > 0 {
                let s = catSpent[catKey] ?? 0
                if s > catBudget {
                    let catName = Category(storageKey: catKey)?.title ?? catKey
                    results.append(ProactiveItem(
                        id: UUID(), type: .budgetRisk, severity: .warning,
                        title: "\(catName) Over Budget",
                        summary: "\(fmtCents(s)) spent of \(fmtCents(catBudget)) \(catName) budget.",
                        signals: ["category:\(catKey)", "overBy:\(fmtCents(s - catBudget))"],
                        createdAt: Date(), updatedAt: Date(),
                        action: nil,
                        dedupKey: "cat_budget_\(catKey)_\(monthKey)"
                    ))
                }
            }
        }

        return results
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Upcoming Bills
    // ══════════════════════════════════════════════════════════

    private func generateUpcomingBillItems() -> [ProactiveItem] {
        var results: [ProactiveItem] = []
        let engine = SubscriptionEngine.shared

        // Bills due within 3 days
        let upcoming = engine.renewingWithin(days: 3)
        for sub in upcoming {
            let days = sub.daysUntilRenewal ?? 0
            let dayLabel = days == 0 ? "today" : (days == 1 ? "tomorrow" : "in \(days) days")

            results.append(ProactiveItem(
                id: UUID(), type: .upcomingBill, severity: days == 0 ? .warning : .info,
                title: "\(sub.merchantName) Due \(dayLabel.capitalized)",
                summary: "\(fmtCents(sub.expectedAmount)) \(sub.billingCycle.rawValue) charge \(dayLabel).",
                signals: ["merchant:\(sub.merchantName)", "days:\(days)"],
                createdAt: Date(), updatedAt: Date(),
                action: nil,
                dedupKey: "bill_\(sub.merchantName.lowercased())_\(days)"
            ))
        }

        // Missed charges (overdue subscriptions)
        for sub in engine.missedChargeSubs {
            let overdueDays = sub.daysSinceLastCharge ?? 0
            results.append(ProactiveItem(
                id: UUID(), type: .upcomingBill, severity: .warning,
                title: "\(sub.merchantName) Charge Missed?",
                summary: "Last charge was \(overdueDays) days ago — expected \(sub.billingCycle.rawValue).",
                signals: ["merchant:\(sub.merchantName)", "missed"],
                createdAt: Date(), updatedAt: Date(),
                action: nil,
                dedupKey: "missed_\(sub.merchantName.lowercased())"
            ))
        }

        return results
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Unusual Spending
    // ══════════════════════════════════════════════════════════

    private func generateUnusualSpendingItems(store: Store) -> [ProactiveItem] {
        var results: [ProactiveItem] = []
        let cal = Calendar.current
        let month = Date()

        let monthExpenses = store.transactions.filter {
            $0.type == .expense && !$0.isTransfer && cal.isDate($0.date, equalTo: month, toGranularity: .month)
        }

        // Group by category and find anomalies
        var catAmounts: [String: [Transaction]] = [:]
        for t in monthExpenses {
            catAmounts[t.category.storageKey, default: []].append(t)
        }

        for (catKey, txns) in catAmounts where txns.count >= 3 {
            let amounts = txns.map(\.amount)
            let avg = amounts.reduce(0, +) / amounts.count

            for txn in txns {
                if txn.amount > avg * 3 && txn.amount > 1000 { // > 3x avg and > $10
                    let catName = Category(storageKey: catKey)?.title ?? catKey
                    results.append(ProactiveItem(
                        id: UUID(), type: .unusualSpending, severity: .warning,
                        title: "Unusual \(catName) Charge",
                        summary: "\(fmtCents(txn.amount)) is \(txn.amount / max(avg, 1))x your \(catName) average.",
                        detail: "Transaction: \(txn.note.isEmpty ? "Unknown" : txn.note) on \(fmtDate(txn.date))",
                        signals: ["amount:\(txn.amount)", "avg:\(avg)", "category:\(catKey)"],
                        createdAt: Date(), updatedAt: Date(),
                        action: nil,
                        dedupKey: "unusual_\(txn.id.uuidString.prefix(8))"
                    ))
                    break // one per category is enough
                }
            }
        }

        return results
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Goal Off-Track
    // ══════════════════════════════════════════════════════════

    private func generateGoalItems() -> [ProactiveItem] {
        var results: [ProactiveItem] = []
        let goals = GoalManager.shared.goals.filter { !$0.isCompleted }

        for goal in goals {
            if goal.isOverdue {
                results.append(ProactiveItem(
                    id: UUID(), type: .goalOffTrack, severity: .warning,
                    title: "\"\(goal.name)\" Overdue",
                    summary: "\(fmtCents(goal.remainingAmount)) still needed. Deadline has passed.",
                    signals: ["goal:\(goal.name)", "overdue"],
                    createdAt: Date(), updatedAt: Date(),
                    action: ProactiveAction(label: "Contribute", icon: "plus.circle.fill",
                                            kind: .openChat),
                    dedupKey: "goal_overdue_\(goal.id.uuidString.prefix(8))"
                ))
            } else if goal.trackingStatus == .behind {
                let monthly = goal.requiredMonthlySaving ?? 0
                results.append(ProactiveItem(
                    id: UUID(), type: .goalOffTrack, severity: .info,
                    title: "\"\(goal.name)\" Behind Pace",
                    summary: "Need \(fmtCents(monthly))/month to stay on track (\(goal.progressPercent)% done).",
                    signals: ["goal:\(goal.name)", "behind", "monthly:\(monthly)"],
                    createdAt: Date(), updatedAt: Date(),
                    action: ProactiveAction(label: "Contribute", icon: "plus.circle.fill",
                                            kind: .openChat),
                    dedupKey: "goal_behind_\(goal.id.uuidString.prefix(8))"
                ))
            }
        }

        return results
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Uncategorized Reminder
    // ══════════════════════════════════════════════════════════

    private func generateUncategorizedReminder(store: Store) -> [ProactiveItem] {
        let cal = Calendar.current
        let month = Date()
        let uncategorized = store.transactions.filter {
            $0.category == .other && cal.isDate($0.date, equalTo: month, toGranularity: .month)
        }

        guard uncategorized.count >= 3 else { return [] } // Only nudge if 3+

        return [ProactiveItem(
            id: UUID(), type: .uncategorizedReminder, severity: .info,
            title: "\(uncategorized.count) Uncategorized",
            summary: "\(uncategorized.count) transaction(s) this month need categories.",
            signals: ["count:\(uncategorized.count)"],
            createdAt: Date(), updatedAt: Date(),
            action: ProactiveAction(label: "Cleanup", icon: "tag.fill",
                                    kind: .startWorkflow(.cleanupUncategorized)),
            dedupKey: "uncategorized_\(Store.monthKey(month))_\(uncategorized.count / 3)" // changes every 3
        )]
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Duplicate Charge Warning
    // ══════════════════════════════════════════════════════════

    private func generateDuplicateWarnings(store: Store) -> [ProactiveItem] {
        let dupes = AIDuplicateDetector.shared.detectDuplicates(in: store.transactions, month: Date())
        guard !dupes.isEmpty else { return [] }

        let highConf = dupes.filter { $0.confidence >= 0.7 }
        guard !highConf.isEmpty else { return [] }

        return [ProactiveItem(
            id: UUID(), type: .duplicateChargeWarning,
            severity: highConf.count >= 3 ? .warning : .info,
            title: "\(highConf.count) Possible Duplicate(s)",
            summary: "Found \(highConf.count) likely duplicate transaction group(s) this month.",
            signals: ["groups:\(highConf.count)"],
            createdAt: Date(), updatedAt: Date(),
            action: ProactiveAction(label: "Review", icon: "doc.on.doc.fill",
                                    kind: .openChat),
            dedupKey: "dupes_\(Store.monthKey(Date()))_\(highConf.count)"
        )]
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Subscription Review Prompt
    // ══════════════════════════════════════════════════════════

    private func generateSubscriptionReview() -> [ProactiveItem] {
        let engine = SubscriptionEngine.shared
        let unused = engine.unusedSubs
        let priceUp = engine.priceIncreasedSubs

        guard unused.count + priceUp.count >= 2 else { return [] }

        var signals: [String] = []
        if !unused.isEmpty { signals.append("\(unused.count) possibly unused") }
        if !priceUp.isEmpty { signals.append("\(priceUp.count) price increase(s)") }

        let savings = engine.potentialMonthlySavings
        let summaryText = savings > 0
            ? "Could save \(fmtCents(savings))/month by reviewing \(unused.count + priceUp.count) subscription(s)."
            : "\(unused.count + priceUp.count) subscription(s) may need attention."

        return [ProactiveItem(
            id: UUID(), type: .subscriptionReviewPrompt, severity: .info,
            title: "Review Subscriptions",
            summary: summaryText,
            signals: signals,
            createdAt: Date(), updatedAt: Date(),
            action: ProactiveAction(label: "Review", icon: "repeat",
                                    kind: .startWorkflow(.subscriptionReview)),
            dedupKey: "sub_review_\(unused.count)_\(priceUp.count)"
        )]
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Monthly Close Prompt
    // ══════════════════════════════════════════════════════════

    private func generateMonthlyClosePrompt(store: Store) -> [ProactiveItem] {
        let cal = Calendar.current
        let now = Date()
        let dayOfMonth = cal.component(.day, from: now)
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30

        // Only show in the last 5 days of the month
        guard dayOfMonth >= daysInMonth - 4 else { return [] }

        let monthKey = Store.monthKey(now)
        let budget = store.budgetsByMonth[monthKey] ?? 0
        let spent = store.spent(for: now)
        let uncategorized = store.transactions.filter {
            $0.category == .other && cal.isDate($0.date, equalTo: now, toGranularity: .month)
        }.count

        var signals: [String] = ["endOfMonth"]
        var detailLines: [String] = []
        var severity: ProactiveSeverity = .info

        if budget > 0 {
            let pct = spent * 100 / max(budget, 1)
            detailLines.append("Budget: \(pct)% used (\(fmtCents(spent)) / \(fmtCents(budget)))")
            if spent > budget { severity = .warning; signals.append("overBudget") }
        }
        if uncategorized > 0 {
            detailLines.append("\(uncategorized) uncategorized transaction(s)")
            signals.append("uncategorized:\(uncategorized)")
        }

        let daysLeft = daysInMonth - dayOfMonth
        let summaryText = "Month ends in \(daysLeft) day(s). " +
            (uncategorized > 0 ? "\(uncategorized) items need cleanup." : "Ready for review.")

        return [ProactiveItem(
            id: UUID(), type: .monthlyClosePrompt, severity: severity,
            title: "Time to Close the Month",
            summary: summaryText,
            detail: detailLines.isEmpty ? nil : detailLines.joined(separator: "\n"),
            signals: signals,
            createdAt: Date(), updatedAt: Date(),
            action: ProactiveAction(label: "Start Monthly Close", icon: "calendar.badge.checkmark",
                                    kind: .startWorkflow(.monthlyClose)),
            dedupKey: "monthly_close_\(monthKey)"
        )]
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Morning Briefing
    // ══════════════════════════════════════════════════════════

    private func generateMorningBriefing(store: Store) -> ProactiveItem? {
        let cal = Calendar.current
        let now = Date()
        let month = now
        let monthKey = Store.monthKey(month)
        let budget = store.budgetsByMonth[monthKey] ?? 0
        let spent = store.spent(for: month)
        let income = store.income(for: month)
        let dayOfMonth = cal.component(.day, from: month)
        let daysInMonth = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let daysLeft = daysInMonth - dayOfMonth

        var sections: [ProactiveBriefingSection] = []
        var topActions: [String] = []

        // ── Budget status ──
        if budget > 0 {
            let remaining = budget - spent
            let pct = spent * 100 / max(budget, 1)
            let dailyAllowance = daysLeft > 0 ? max(0, remaining) / daysLeft : 0
            var lines = [
                "Budget: \(fmtCents(budget)) | Spent: \(fmtCents(spent)) (\(pct)%)",
                "Remaining: \(fmtCents(remaining)) (\(daysLeft) days left)",
            ]
            if remaining > 0 {
                lines.append("Safe to spend: \(fmtCents(dailyAllowance))/day")
            }

            let sev: ProactiveSeverity = remaining < 0 ? .critical : (pct > 80 ? .warning : .info)
            sections.append(ProactiveBriefingSection(title: "Budget", icon: "chart.bar.fill", lines: lines, severity: sev))

            if remaining < 0 { topActions.append("Consider Budget Rescue workflow") }
        } else {
            sections.append(ProactiveBriefingSection(
                title: "Budget", icon: "chart.bar.fill",
                lines: ["No budget set. Total spending: \(fmtCents(spent))"]
            ))
        }

        // ── Upcoming bills ──
        let upcomingBills = SubscriptionEngine.shared.renewingWithin(days: 3)
        if !upcomingBills.isEmpty {
            let lines = upcomingBills.prefix(3).map { sub in
                let days = sub.daysUntilRenewal ?? 0
                let when = days == 0 ? "today" : (days == 1 ? "tomorrow" : "in \(days) days")
                return "\(sub.merchantName): \(fmtCents(sub.expectedAmount)) \(when)"
            }
            sections.append(ProactiveBriefingSection(title: "Upcoming Bills", icon: "clock.badge.exclamationmark.fill",
                                            lines: lines, severity: .info))
        }

        // ── Uncategorized ──
        let uncatCount = store.transactions.filter {
            $0.category == .other && cal.isDate($0.date, equalTo: month, toGranularity: .month)
        }.count
        if uncatCount > 0 {
            sections.append(ProactiveBriefingSection(
                title: "Needs Attention", icon: "tag.fill",
                lines: ["\(uncatCount) uncategorized transaction(s) this month"],
                severity: uncatCount >= 5 ? .warning : .info
            ))
            if uncatCount >= 3 { topActions.append("Run Cleanup Uncategorized workflow") }
        }

        // ── Goals ──
        let goals = GoalManager.shared.goals.filter { !$0.isCompleted }
        if !goals.isEmpty {
            let lines = goals.prefix(3).map { g in
                var line = "\(g.name): \(g.progressPercent)%"
                if g.trackingStatus == .behind { line += " (behind)" }
                else if g.trackingStatus == .ahead { line += " (ahead)" }
                return line
            }
            let anybehind = goals.contains { $0.trackingStatus == .behind }
            sections.append(ProactiveBriefingSection(
                title: "Goals", icon: "target",
                lines: lines,
                severity: anybehind ? .warning : .positive
            ))
        }

        // ── Recommended actions ──
        if !topActions.isEmpty {
            sections.append(ProactiveBriefingSection(
                title: "Recommended", icon: "lightbulb.fill",
                lines: topActions,
                severity: .info
            ))
        }

        guard !sections.isEmpty else { return nil }

        let overallSeverity = sections.map(\.severity).min() ?? .info

        let hour = cal.component(.hour, from: now)
        let greetingTitle: String = {
            switch hour {
            case 5..<12:  return "Good Morning"
            case 12..<17: return "Good Afternoon"
            case 17..<22: return "Good Evening"
            default:      return "Late Night Check-in"
            }
        }()

        var item = ProactiveItem(
            id: UUID(), type: .morningBriefing, severity: overallSeverity,
            title: greetingTitle,
            summary: budget > 0
                ? "\(fmtCents(budget - spent)) remaining this month"
                : "\(fmtCents(spent)) spent this month",
            signals: ["daily"],
            createdAt: Date(), updatedAt: Date(),
            action: nil,
            dedupKey: "briefing_\(cal.component(.day, from: now))"
        )
        item.sections = sections
        return item
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Weekly Review
    // ══════════════════════════════════════════════════════════

    private func generateWeeklyReview(store: Store) -> ProactiveItem? {
        let cal = Calendar.current
        let now = Date()

        // Only generate on weekends (Sat/Sun) or if explicitly requested
        let weekday = cal.component(.weekday, from: now)
        guard weekday == 1 || weekday == 7 else { return nil } // Sun=1, Sat=7

        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: now) else { return nil }
        let weekTxns = store.transactions.filter { $0.date >= weekAgo && $0.date <= now }
        guard !weekTxns.isEmpty else { return nil }

        let expenses = weekTxns.filter { $0.type == .expense && !$0.isTransfer }
        let totalSpent = expenses.reduce(0) { $0 + $1.amount }

        var sections: [ProactiveBriefingSection] = []

        // ── Spending this week ──
        var catTotals: [String: Int] = [:]
        for t in expenses { catTotals[t.category.title, default: 0] += t.amount }
        let sorted = catTotals.sorted { $0.value > $1.value }

        var spendLines = ["\(expenses.count) expenses totaling \(fmtCents(totalSpent))"]
        for (cat, amount) in sorted.prefix(3) {
            spendLines.append("  \(cat): \(fmtCents(amount))")
        }
        sections.append(ProactiveBriefingSection(title: "This Week", icon: "calendar", lines: spendLines))

        // ── Compare to previous week ──
        if let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: now) {
            let prevWeekExpenses = store.transactions.filter {
                $0.date >= twoWeeksAgo && $0.date < weekAgo && $0.type == .expense && !$0.isTransfer
            }
            let prevTotal = prevWeekExpenses.reduce(0) { $0 + $1.amount }
            if prevTotal > 0 {
                let diff = totalSpent - prevTotal
                let pctChange = diff * 100 / prevTotal
                let direction = diff > 0 ? "up" : "down"
                sections.append(ProactiveBriefingSection(
                    title: "vs Last Week", icon: "arrow.up.arrow.down",
                    lines: ["\(fmtCents(abs(diff))) \(direction) (\(abs(pctChange))%)"],
                    severity: diff > 0 ? .warning : .positive
                ))
            }
        }

        // ── Budget status ──
        let monthKey = Store.monthKey(now)
        let budget = store.budgetsByMonth[monthKey] ?? 0
        if budget > 0 {
            let monthSpent = store.spent(for: now)
            let remaining = budget - monthSpent
            sections.append(ProactiveBriefingSection(
                title: "Month Budget", icon: "chart.bar.fill",
                lines: ["\(fmtCents(remaining)) remaining of \(fmtCents(budget))"],
                severity: remaining < 0 ? .critical : .info
            ))
        }

        // ── Recommendations ──
        var recs: [String] = []
        if let topCat = sorted.first, topCat.value > totalSpent / 2 {
            recs.append("\(topCat.key) is over half your weekly spending")
        }
        let uncatCount = expenses.filter { $0.category == .other }.count
        if uncatCount > 0 { recs.append("\(uncatCount) uncategorized this week") }
        if !recs.isEmpty {
            sections.append(ProactiveBriefingSection(title: "Recommendations", icon: "lightbulb.fill",
                                            lines: recs, severity: .info))
        }

        let weekNum = cal.component(.weekOfYear, from: now)
        var item = ProactiveItem(
            id: UUID(), type: .weeklyReview, severity: .info,
            title: "Week in Review",
            summary: "\(fmtCents(totalSpent)) spent across \(expenses.count) transactions",
            signals: ["weekly"],
            createdAt: Date(), updatedAt: Date(),
            action: nil,
            dedupKey: "weekly_\(cal.component(.year, from: now))_\(weekNum)"
        )
        item.sections = sections
        return item
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Persistence
    // ══════════════════════════════════════════════════════════

    private func loadDismissedKeys() {
        if let saved = UserDefaults.standard.stringArray(forKey: dismissedKeysStorageKey) {
            dismissedKeys = Set(saved)
        }
    }

    private func saveDismissedKeys() {
        UserDefaults.standard.set(Array(dismissedKeys), forKey: dismissedKeysStorageKey)
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Helpers
    // ══════════════════════════════════════════════════════════

    private func fmtCents(_ cents: Int) -> String {
        let isNeg = cents < 0
        let str = String(format: "$%.2f", Double(abs(cents)) / 100.0)
        return isNeg ? "-\(str)" : str
    }

    private func fmtDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }
}
