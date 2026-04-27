import Foundation
import Combine

// ============================================================
// MARK: - AI Audit Log
// ============================================================
//
// Phase 4 deliverable: records the full lifecycle of every AI
// interaction: prompt → intent → actions → confirmation → execution → outcome.
//
// Provides transparency, debugging, and trust-building.
// Persisted to disk so it survives app restarts.
//
// ============================================================

/// A single audit entry capturing one complete AI interaction.
struct AIAuditEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date

    // ── Input ──
    let userMessage: String
    let detectedIntent: String
    let intentConfidence: Double
    let isMultiIntent: Bool

    // ── Processing ──
    let contextHint: String            // "full", "budgetOnly", etc.
    let clarificationNeeded: Bool
    let clarificationReason: String?

    // ── Output ──
    let aiResponseText: String
    let proposedActions: [AuditAction]

    // ── Trust & Confirmation ──
    let trustDecisions: [AuditTrustDecision]

    // ── Execution ──
    var executionResults: [AuditExecutionResult]
    var completedAt: Date?

    // ── Error ──
    var errorDescription: String?

    init(
        userMessage: String,
        detectedIntent: String,
        intentConfidence: Double,
        isMultiIntent: Bool = false,
        contextHint: String,
        clarificationNeeded: Bool = false,
        clarificationReason: String? = nil,
        aiResponseText: String = "",
        proposedActions: [AuditAction] = [],
        trustDecisions: [AuditTrustDecision] = [],
        executionResults: [AuditExecutionResult] = [],
        errorDescription: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.userMessage = userMessage
        self.detectedIntent = detectedIntent
        self.intentConfidence = intentConfidence
        self.isMultiIntent = isMultiIntent
        self.contextHint = contextHint
        self.clarificationNeeded = clarificationNeeded
        self.clarificationReason = clarificationReason
        self.aiResponseText = aiResponseText
        self.proposedActions = proposedActions
        self.trustDecisions = trustDecisions
        self.executionResults = executionResults
        self.completedAt = nil
        self.errorDescription = errorDescription
    }
}

/// Lightweight action representation for audit (no heavy data).
struct AuditAction: Codable {
    let type: String           // "add_transaction", "set_budget", etc.
    let summary: String        // "Add $50 dining expense"
    let amountCents: Int?

    init(from action: AIAction) {
        self.type = action.type.rawValue
        self.summary = AuditAction.describeParsedAction(action)
        self.amountCents = action.params.amount ?? action.params.budgetAmount ??
                           action.params.goalTarget ?? action.params.subscriptionAmount ??
                           action.params.contributionAmount
    }

    private static func describeParsedAction(_ action: AIAction) -> String {
        let p = action.params
        switch action.type {
        case .addTransaction:
            let amount = p.amount.map { formatCents($0) } ?? "?"
            return "Add \(p.transactionType ?? "expense"): \(amount) [\(p.category ?? "?")]"
        case .editTransaction:
            return "Edit transaction \(p.transactionId?.prefix(8) ?? "?")"
        case .deleteTransaction:
            return "Delete transaction \(p.transactionId?.prefix(8) ?? "?")"
        case .splitTransaction:
            let amount = p.amount.map { formatCents($0) } ?? "?"
            return "Split \(amount) with \(p.splitWith ?? "?")"
        case .setBudget, .adjustBudget:
            let amount = p.budgetAmount.map { formatCents($0) } ?? "?"
            return "Set budget to \(amount)"
        case .setCategoryBudget:
            let amount = p.budgetAmount.map { formatCents($0) } ?? "?"
            return "Set \(p.budgetCategory ?? "?") budget to \(amount)"
        case .createGoal:
            return "Create goal: \(p.goalName ?? "?")"
        case .addContribution:
            let amount = p.contributionAmount.map { formatCents($0) } ?? "?"
            return "Add \(amount) to \(p.goalName ?? "?")"
        case .updateGoal:
            return "Update goal: \(p.goalName ?? "?")"
        case .pauseGoal:
            let verb = (p.goalPause ?? true) ? "Pause" : "Resume"
            return "\(verb) goal: \(p.goalName ?? "?")"
        case .archiveGoal:
            let verb = (p.goalArchive ?? true) ? "Archive" : "Unarchive"
            return "\(verb) goal: \(p.goalName ?? "?")"
        case .withdrawFromGoal:
            let amount = p.contributionAmount.map { formatCents($0) } ?? "?"
            return "Withdraw \(amount) from \(p.goalName ?? "?")"
        case .addSubscription:
            return "Add subscription: \(p.subscriptionName ?? "?")"
        case .cancelSubscription:
            return "Cancel: \(p.subscriptionName ?? "?")"
        case .pauseSubscription:
            return "Pause: \(p.subscriptionName ?? "?")"
        case .updateBalance:
            return "Update balance: \(p.accountName ?? "?")"
        case .transfer:
            let amount = p.amount.map { formatCents($0) } ?? "?"
            return "Transfer \(amount) from \(p.fromAccount ?? "?") to \(p.toAccount ?? "?")"
        case .addRecurring:
            return "Add recurring: \(p.recurringName ?? "?")"
        case .editRecurring:
            return "Edit recurring: \(p.recurringName ?? "?")"
        case .cancelRecurring:
            return "Cancel recurring: \(p.recurringName ?? "?")"
        case .analyze, .compare, .forecast, .advice:
            return "Analysis: \(action.type.rawValue)"
        default:
            // Goal lifecycle (.pauseGoal/.archiveGoal/.withdrawFromGoal) and
            // future action types fall back to the raw enum tag.
            return action.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}

/// Trust decision for a single action (Phase 2: enriched with risk data).
struct AuditTrustDecision: Codable {
    let actionType: String
    let trustLevel: String          // "auto", "confirm", "neverAuto"
    let riskScore: Double           // 0.0–1.0
    let riskLevel: String           // "none", "low", "medium", "high", "critical"
    let reason: String              // human-readable explanation
    let confidenceUsed: Double      // model/intent confidence at decision time
    let preferenceInfluenced: Bool  // was a user preference the deciding factor?
    let userDecision: String?       // "confirmed", "rejected", nil (auto)

    /// Backward-compatible initializer for minimal usage.
    init(
        actionType: String,
        trustLevel: String,
        riskScore: Double = 0,
        riskLevel: String = "none",
        reason: String = "",
        confidenceUsed: Double = 0,
        preferenceInfluenced: Bool = false,
        userDecision: String? = nil
    ) {
        self.actionType = actionType
        self.trustLevel = trustLevel
        self.riskScore = riskScore
        self.riskLevel = riskLevel
        self.reason = reason
        self.confidenceUsed = confidenceUsed
        self.preferenceInfluenced = preferenceInfluenced
        self.userDecision = userDecision
    }
}

/// Result of executing a single action.
struct AuditExecutionResult: Codable {
    let actionType: String
    let success: Bool
    let summary: String
    let undoable: Bool
}

// MARK: - Audit Log Manager

@MainActor
class AIAuditLog: ObservableObject {
    static let shared = AIAuditLog()

    @Published private(set) var entries: [AIAuditEntry] = []

    private let maxEntries = 500
    private let storageKey = "ai.auditLog"

    private init() {
        load()
    }

    // MARK: - Recording

    /// Start a new audit entry when user sends a message.
    func beginEntry(
        userMessage: String,
        classification: IntentClassification,
        clarification: ClarificationResult? = nil
    ) -> UUID {
        let entry = AIAuditEntry(
            userMessage: userMessage,
            detectedIntent: classification.intentType.rawValue,
            intentConfidence: classification.confidence,
            isMultiIntent: classification.isMultiIntent,
            contextHint: classification.contextHint.rawValue,
            clarificationNeeded: clarification != nil,
            clarificationReason: clarification?.missingFields.first
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        return entry.id
    }

    /// Update entry with AI response and parsed actions.
    func recordResponse(entryId: UUID, responseText: String, actions: [AIAction]) {
        guard let idx = entries.firstIndex(where: { $0.id == entryId }) else { return }
        entries[idx] = AIAuditEntry(
            userMessage: entries[idx].userMessage,
            detectedIntent: entries[idx].detectedIntent,
            intentConfidence: entries[idx].intentConfidence,
            isMultiIntent: entries[idx].isMultiIntent,
            contextHint: entries[idx].contextHint,
            clarificationNeeded: entries[idx].clarificationNeeded,
            clarificationReason: entries[idx].clarificationReason,
            aiResponseText: responseText,
            proposedActions: actions.map { AuditAction(from: $0) },
            trustDecisions: entries[idx].trustDecisions,
            executionResults: entries[idx].executionResults,
            errorDescription: entries[idx].errorDescription
        )
    }

    /// Record trust decisions for actions.
    func recordTrustDecisions(entryId: UUID, decisions: [AuditTrustDecision]) {
        guard let idx = entries.firstIndex(where: { $0.id == entryId }) else { return }
        var entry = entries[idx]
        entry = AIAuditEntry(
            userMessage: entry.userMessage,
            detectedIntent: entry.detectedIntent,
            intentConfidence: entry.intentConfidence,
            isMultiIntent: entry.isMultiIntent,
            contextHint: entry.contextHint,
            clarificationNeeded: entry.clarificationNeeded,
            clarificationReason: entry.clarificationReason,
            aiResponseText: entry.aiResponseText,
            proposedActions: entry.proposedActions,
            trustDecisions: decisions,
            executionResults: entry.executionResults,
            errorDescription: entry.errorDescription
        )
        entries[idx] = entry
    }

    /// Record execution results.
    func recordExecution(entryId: UUID, results: [AuditExecutionResult]) {
        guard let idx = entries.firstIndex(where: { $0.id == entryId }) else { return }
        entries[idx].executionResults = results
        entries[idx].completedAt = Date()
        save()
    }

    /// Record an error.
    func recordError(entryId: UUID, error: String) {
        guard let idx = entries.firstIndex(where: { $0.id == entryId }) else { return }
        entries[idx].errorDescription = error
        entries[idx].completedAt = Date()
        save()
    }

    // MARK: - Queries

    /// Recent entries (last N).
    func recent(_ count: Int = 20) -> [AIAuditEntry] {
        Array(entries.prefix(count))
    }

    /// Entries with errors.
    var errorEntries: [AIAuditEntry] {
        entries.filter { $0.errorDescription != nil }
    }

    /// Success rate (last 100).
    var successRate: Double {
        let recent = Array(entries.prefix(100))
        guard !recent.isEmpty else { return 1.0 }
        let successful = recent.filter { $0.errorDescription == nil && !$0.executionResults.isEmpty }
        return Double(successful.count) / Double(recent.count)
    }

    /// Actions that were blocked by trust policy.
    var blockedActions: [AuditTrustDecision] {
        entries.flatMap { $0.trustDecisions }.filter { $0.trustLevel == "neverAuto" || $0.trustLevel == "never" }
    }

    /// Actions that were rejected by user.
    var rejectedActions: [AuditTrustDecision] {
        entries.flatMap { $0.trustDecisions }.filter { $0.userDecision == "rejected" }
    }

    /// Clear all logs.
    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let saved = try? decoder.decode([AIAuditEntry].self, from: data) {
            entries = saved
        }
    }
}
