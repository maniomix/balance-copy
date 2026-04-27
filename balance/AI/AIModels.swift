import Foundation
import Combine

// ============================================================
// MARK: - AI Data Models
// ============================================================
//
// Shared types for the AI layer: messages, actions, insights.
// These flow between AIManager → AIActionParser → AIActionExecutor.
//
// ============================================================

// MARK: - Chat Message

struct AIMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    /// Parsed actions attached to an assistant message (nil for user messages).
    var actions: [AIAction]?

    enum Role: String, Codable, Equatable {
        case user
        case assistant
        case system
    }

    init(role: Role, content: String, actions: [AIAction]? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.actions = actions
    }
}

// MARK: - AI Action

/// A single actionable operation parsed from the AI response.
/// The AI returns JSON with an array of these; `AIActionParser` decodes them.
struct AIAction: Identifiable, Equatable, Codable {
    let id: UUID
    let type: ActionType
    var params: ActionParams
    /// User confirmation state — actions start as `.pending`.
    var status: ConfirmationStatus = .pending

    init(type: ActionType, params: ActionParams) {
        self.id = UUID()
        self.type = type
        self.params = params
    }

    enum ConfirmationStatus: String, Codable, Equatable {
        case pending
        case confirmed
        case rejected
        case executed
    }

    // ── Action Types ──

    enum ActionType: String, Codable, Equatable {
        // Transactions
        case addTransaction = "add_transaction"
        case editTransaction = "edit_transaction"
        case deleteTransaction = "delete_transaction"
        case splitTransaction = "split_transaction"

        // Transfers
        case transfer = "transfer"

        // Recurring
        case addRecurring = "add_recurring"
        case editRecurring = "edit_recurring"
        case cancelRecurring = "cancel_recurring"

        // Budget
        case setBudget = "set_budget"
        case adjustBudget = "adjust_budget"
        case setCategoryBudget = "set_category_budget"

        // Goals
        case createGoal = "create_goal"
        case addContribution = "add_contribution"
        case updateGoal = "update_goal"
        case pauseGoal = "pause_goal"
        case archiveGoal = "archive_goal"
        case withdrawFromGoal = "withdraw_from_goal"

        // Subscriptions
        case addSubscription = "add_subscription"
        case cancelSubscription = "cancel_subscription"
        case pauseSubscription = "pause_subscription"

        // Accounts
        case updateBalance = "update_balance"
        case addAccount = "add_account"
        case archiveAccount = "archive_account"
        case reconcileBalance = "reconcile_balance"

        // Analysis (no mutation — text-only response)
        case analyze = "analyze"
        case compare = "compare"
        case forecast = "forecast"
        case advice = "advice"

        /// Whether this action type mutates data.
        var isMutation: Bool {
            switch self {
            case .analyze, .compare, .forecast, .advice:
                return false
            default:
                return true
            }
        }

        /// Risk level for trust classification.
        var riskLevel: RiskLevel {
            switch self {
            case .analyze, .compare, .forecast, .advice:
                return .none
            case .addTransaction, .splitTransaction, .addRecurring, .addSubscription,
                 .addContribution, .createGoal, .transfer, .addAccount:
                return .low
            case .setBudget, .adjustBudget, .setCategoryBudget,
                 .updateGoal, .updateBalance, .editTransaction, .editRecurring,
                 .pauseGoal, .archiveGoal, .reconcileBalance,
                 .pauseSubscription:
                return .medium
            case .deleteTransaction, .cancelSubscription, .cancelRecurring,
                 .withdrawFromGoal, .archiveAccount:
                return .high
            }
        }

        enum RiskLevel: Int, Comparable {
            case none = 0
            case low = 1
            case medium = 2
            case high = 3

            static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }
    }

    // ── Action Parameters ──
    //
    // A flat struct that carries all possible parameters.
    // Each action type only uses the fields relevant to it;
    // the rest are nil. This avoids a complex enum-with-associated-values
    // that would be painful to decode from LLM JSON output.

    struct ActionParams: Codable, Equatable {
        // Transaction fields
        var amount: Int?               // cents
        var category: String?          // e.g. "dining", "shopping", "custom:Coffee"
        var note: String?
        var date: String?              // ISO 8601 or "yesterday", "today"
        var transactionType: String?   // "expense" or "income"
        var transactionId: String?     // UUID string (for edit/delete)

        // Split fields
        var splitWith: String?         // household member name
        var splitRatio: Double?        // 0.0–1.0, my share (default 0.5)

        // Budget fields
        var budgetAmount: Int?         // cents
        var budgetMonth: String?       // "2026-04" or "this_month"
        var budgetCategory: String?    // category key for category budget

        // Goal fields
        var goalName: String?
        var goalTarget: Int?           // cents
        var goalDeadline: String?      // ISO date
        var contributionAmount: Int?   // cents
        var goalPriority: Int?         // 0–10 (used by update_goal)
        var goalPause: Bool?           // pause_goal: true = pause, false = resume; nil → toggle
        var goalArchive: Bool?         // archive_goal: true = archive, false = unarchive; nil → toggle

        // Subscription fields
        var subscriptionName: String?
        var subscriptionAmount: Int?   // cents per period
        var subscriptionFrequency: String? // "monthly", "yearly"

        // Account fields
        var accountName: String?
        var accountBalance: Int?       // cents
        /// Account type for add_account: "cash" | "bank" | "credit_card" | "savings" | "investment" | "loan"
        var accountType: String?
        /// ISO currency code (e.g. "EUR"). Optional — falls back to app currency when nil.
        var accountCurrency: String?

        // Transfer fields
        var fromAccount: String?       // source account name
        var toAccount: String?         // destination account name

        // Recurring fields
        var recurringName: String?
        var recurringFrequency: String?  // "daily", "weekly", "monthly", "yearly"
        var recurringEndDate: String?    // ISO date or nil for indefinite

        // Analysis fields
        var analysisText: String?      // AI's textual response for analysis actions
    }
}

// MARK: - AI Insight

/// An auto-generated insight shown proactively (dashboard banner, briefing, etc.).
struct AIInsight: Identifiable, Equatable {
    let id: UUID
    let type: InsightType
    let title: String
    let body: String
    let severity: Severity
    let timestamp: Date
    /// Optional action the user can take (e.g. "Set category budget")
    var suggestedAction: AIAction?

    // MARK: - Phase 2 enrichment fields (ported from macOS)

    /// Actionable suggestion line — short, directive ("Pause dining out until Friday").
    /// Populated by detectors; optionally rewritten by `InsightEnricher` via LLM.
    var advice: String?
    /// Quantitative explanation of why the insight fired ("$412 over a 30-day average of $210").
    var cause: String?
    /// Auto-dismiss timestamp — refresh drops expired insights.
    var expiresAt: Date?
    /// Stable key for deduping across refreshes and gating dismissals.
    /// Format: `domain:subtype[:entity]` (e.g. "subscription:unused:netflix").
    var dedupeKey: String?
    /// Where to route the user when they tap the insight.
    var deeplink: Deeplink?

    enum InsightType: String, Equatable {
        case budgetWarning        // "budget pace ahead"
        case spendingAnomaly      // "unusual transaction"
        case savingsOpportunity   // "you could save X by..."
        case recurringDetected    // "this looks like a subscription"
        case weeklyReport         // "your week in review"
        case goalProgress         // "you're 80% to your goal"
        case patternDetected      // "you spend most on Tuesdays"
        case morningBriefing      // daily summary
        // Phase 2 additions
        case cashflowRisk         // runway / income drop
        case duplicateDetected    // duplicate transaction
        case subscriptionAlert    // unused / hiked / duplicate subscription
        case householdAlert       // household imbalance / unpaid share
        case netWorthMilestone    // big drop, liability down, milestone crossed
        case reviewQueueAlert     // backlog / blockers
    }

    enum Severity: String, Equatable, Comparable {
        case info
        case warning
        case critical
        case positive

        private var sortRank: Int {
            switch self {
            case .critical: return 0
            case .warning:  return 1
            case .info:     return 2
            case .positive: return 3
            }
        }

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.sortRank < rhs.sortRank
        }
    }

    /// Where a tap on the insight banner should take the user.
    enum Deeplink: String, Equatable {
        case cashflow
        case subscriptions
        case recurring
        case transactions
        case budgets
        case goals
        case household
        case netWorth
        case reviewQueue
    }

    init(type: InsightType, title: String, body: String,
         severity: Severity = .info, suggestedAction: AIAction? = nil,
         advice: String? = nil, cause: String? = nil,
         expiresAt: Date? = nil, dedupeKey: String? = nil, deeplink: Deeplink? = nil) {
        self.id = UUID()
        self.type = type
        self.title = title
        self.body = body
        self.severity = severity
        self.timestamp = Date()
        self.suggestedAction = suggestedAction
        self.advice = advice
        self.cause = cause
        self.expiresAt = expiresAt
        self.dedupeKey = dedupeKey
        self.deeplink = deeplink
    }

    /// macOS-compat alias — detectors emit `warning:` naming; maps to `body`.
    var warning: String { body }

    /// Copy with advice swapped — used by `InsightEnricher` to upgrade the
    /// heuristic line without rebuilding the struct at every detector site.
    func withAdvice(_ newAdvice: String) -> AIInsight {
        var copy = self
        copy.advice = newAdvice
        return copy
    }

    /// Stable group ID for telemetry (first two segments of dedupeKey).
    var detectorID: String {
        guard let key = dedupeKey, !key.isEmpty else { return type.rawValue }
        let parts = key.split(separator: ":", omittingEmptySubsequences: true)
        if parts.count >= 2 { return "\(parts[0]):\(parts[1])" }
        return key
    }
}

// MARK: - AI Conversation

/// Holds the full chat history for a session.
class AIConversation: ObservableObject {
    @Published var messages: [AIMessage] = []
    @Published var pendingActions: [AIAction] = []

    func addUserMessage(_ text: String) {
        messages.append(AIMessage(role: .user, content: text))
    }

    func addAssistantMessage(_ text: String, actions: [AIAction]? = nil) {
        // If new actions arrive, auto-reject any old pending actions
        // so the user only sees the latest action card with buttons
        if let actions, !actions.isEmpty {
            for old in pendingActions where old.status == .pending {
                updateActionStatus(old.id, to: .rejected)
            }
        }
        messages.append(AIMessage(role: .assistant, content: text, actions: actions))
        if let actions {
            pendingActions = actions.filter { $0.status == .pending }
        }
    }

    func confirmAction(_ id: UUID) {
        updateActionStatus(id, to: .confirmed)
    }

    func rejectAction(_ id: UUID) {
        updateActionStatus(id, to: .rejected)
    }

    func markExecuted(_ id: UUID) {
        updateActionStatus(id, to: .executed)
    }

    func confirmAll() {
        for i in pendingActions.indices {
            if pendingActions[i].status == .pending {
                pendingActions[i].status = .confirmed
            }
        }
        syncActionsToMessages()
    }

    /// Update action status in both pendingActions and message history.
    private func updateActionStatus(_ id: UUID, to status: AIAction.ConfirmationStatus) {
        if let i = pendingActions.firstIndex(where: { $0.id == id }) {
            pendingActions[i].status = status
        }
        syncActionsToMessages()
    }

    /// Keep message.actions in sync with pendingActions so the UI reflects status changes.
    private func syncActionsToMessages() {
        for mi in messages.indices {
            guard var actions = messages[mi].actions else { continue }
            var changed = false
            for ai in actions.indices {
                if let pending = pendingActions.first(where: { $0.id == actions[ai].id }),
                   pending.status != actions[ai].status {
                    actions[ai].status = pending.status
                    changed = true
                }
            }
            if changed {
                messages[mi].actions = actions
            }
        }
    }

    func clear() {
        messages.removeAll()
        pendingActions.removeAll()
    }
}
