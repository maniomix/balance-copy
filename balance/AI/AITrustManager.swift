import Foundation
import Combine

// ============================================================
// MARK: - AI Trust Manager (Phase 2: Trust & Approval System)
// ============================================================
//
// The single source of truth for AI action approval policy.
//
// Evaluates each proposed action against:
//   1. Base action risk rules (action type → default level)
//   2. Financial risk assessment (amount, destructive, balance, multi-record)
//   3. User trust preferences (toggles, thresholds)
//   4. Assistant mode (advisor/assistant/autopilot/cfo)
//   5. Model/intent confidence
//
// Returns a TrustDecision per action with:
//   • trust level (auto / confirm / neverAuto)
//   • reason (human-readable)
//   • risk score (0.0–1.0)
//   • whether user preferences influenced the decision
//
// Must be called BEFORE execution — sits between parser and executor.
//
// ============================================================

@MainActor
class AITrustManager: ObservableObject {
    static let shared = AITrustManager()

    @Published var preferences: AIUserTrustPreferences {
        didSet { preferences.save() }
    }

    private init() {
        self.preferences = AIUserTrustPreferences.load()
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Public API
    // ══════════════════════════════════════════════════════════

    /// Evaluate a batch of actions through the full trust pipeline.
    ///
    /// - Parameters:
    ///   - actions: parsed candidate actions from the model
    ///   - classification: the intent classification for this message
    ///   - mode: current assistant mode
    /// - Returns: actions split into auto/confirm/blocked with full decisions
    func classify(
        _ actions: [AIAction],
        classification: IntentClassification? = nil,
        mode: AssistantMode = .assistant
    ) -> TrustClassifiedActions {
        let confidence = classification?.confidence ?? 0.5

        var auto: [(AIAction, TrustDecision)] = []
        var confirm: [(AIAction, TrustDecision)] = []
        var blocked: [(AIAction, TrustDecision)] = []

        for action in actions {
            let decision = evaluate(
                action: action,
                confidence: confidence,
                mode: mode
            )

            switch decision.level {
            case .auto:      auto.append((action, decision))
            case .confirm:   confirm.append((action, decision))
            case .neverAuto: blocked.append((action, decision))
            }
        }

        return TrustClassifiedActions(auto: auto, confirm: confirm, blocked: blocked)
    }

    /// Evaluate a single action. Useful for re-evaluating after preference changes.
    func evaluate(
        action: AIAction,
        confidence: Double = 0.5,
        mode: AssistantMode = .assistant
    ) -> TrustDecision {
        // Step 1: Assess financial risk
        let risk = assessRisk(action: action)

        // Step 2: Compute risk score
        let riskScore = computeRiskScore(action: action, risk: risk)

        // Step 3: Determine base level from action type rules
        let baseLevel = baseActionRule(for: action.type)

        // Step 4: Apply mode adjustments
        let modeLevel = applyMode(base: baseLevel, action: action, mode: mode)

        // Step 5: Apply financial risk escalation
        let riskLevel = applyRiskEscalation(base: modeLevel, risk: risk, riskScore: riskScore)

        // Step 6: Apply confidence gate
        let confLevel = applyConfidenceGate(base: riskLevel, confidence: confidence)

        // Step 7: Apply user preferences (final override)
        let (prefLevel, prefInfluenced) = applyUserPreferences(
            base: confLevel, action: action, risk: risk
        )

        // HARD RULE: every mutating action requires explicit user confirmation.
        // Analyses (analyze/compare/forecast/advice) are the only auto-allowed types.
        // This supersedes mode/preference upgrades.
        let finalLevel: AITrustLevel = {
            if prefLevel == .auto && action.type.isMutation {
                return .confirm
            }
            return prefLevel
        }()

        // Build reason
        let reason = buildReason(
            action: action,
            finalLevel: finalLevel,
            baseLevel: baseLevel,
            riskScore: riskScore,
            risk: risk,
            confidence: confidence,
            prefInfluenced: prefInfluenced,
            mode: mode
        )

        // Build block message if needed
        let blockMessage: String?
        if finalLevel == .neverAuto {
            blockMessage = buildBlockMessage(action: action, risk: risk)
        } else {
            blockMessage = nil
        }

        return TrustDecision(
            id: action.id,
            actionType: action.type,
            level: finalLevel,
            reason: reason,
            riskScore: riskScore,
            confidenceUsed: confidence,
            preferenceInfluenced: prefInfluenced,
            blockMessage: blockMessage
        )
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Preference Management
    // ══════════════════════════════════════════════════════════

    func updatePreferences(_ prefs: AIUserTrustPreferences) {
        preferences = prefs
    }

    func resetPreferences() {
        preferences = AIUserTrustPreferences()
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Step 1: Risk Assessment
    // ══════════════════════════════════════════════════════════

    /// Extract financial risk signals from the action's payload.
    private func assessRisk(action: AIAction) -> RiskAssessment {
        let p = action.params

        // Determine the relevant amount in cents
        let amountCents = p.amount ?? p.budgetAmount ?? p.goalTarget ??
                          p.subscriptionAmount ?? p.contributionAmount ??
                          p.accountBalance

        // Destructive: permanent data removal
        // Note: cancelSubscription/cancelRecurring are "soft destructive" —
        // they disable but don't erase data, so they are NOT flagged here.
        // They still get risk weight from the recurring factor below.
        let isDestructive: Bool = {
            switch action.type {
            case .deleteTransaction:
                return true
            default:
                return false
            }
        }()

        // Affects account balance directly
        let affectsBalance: Bool = {
            switch action.type {
            case .updateBalance, .transfer:
                return true
            default:
                return false
            }
        }()

        // Could affect multiple records (split, batch-like)
        let affectsMultiple = action.type == .splitTransaction

        // Long-term planning: budgets, goals, recurring
        let affectsLongTerm: Bool = {
            switch action.type {
            case .setBudget, .adjustBudget, .setCategoryBudget,
                 .createGoal, .updateGoal,
                 .addRecurring, .editRecurring:
                return true
            default:
                return false
            }
        }()

        // Recurring change
        let isRecurring: Bool = {
            switch action.type {
            case .addRecurring, .editRecurring, .cancelRecurring,
                 .addSubscription, .cancelSubscription, .pauseSubscription:
                return true
            default:
                return false
            }
        }()

        // High-value target (account-level operations)
        let isHighValue = action.type == .updateBalance

        return RiskAssessment(
            amountCents: amountCents,
            isDestructive: isDestructive,
            affectsBalance: affectsBalance,
            affectsMultipleRecords: affectsMultiple,
            affectsLongTermPlanning: affectsLongTerm,
            isRecurringChange: isRecurring,
            isHighValueTarget: isHighValue
        )
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Step 2: Risk Score
    // ══════════════════════════════════════════════════════════

    /// Compute a 0.0–1.0 risk score with named contributing factors.
    private func computeRiskScore(action: AIAction, risk: RiskAssessment) -> RiskScore {
        var score: Double = 0
        var factors: [RiskFactor] = []

        // Base action-type risk
        let baseRisk: Double = {
            switch action.type.riskLevel {
            case .none:   return 0.0
            case .low:    return 0.15
            case .medium: return 0.35
            case .high:   return 0.60
            }
        }()
        if baseRisk > 0 {
            factors.append(RiskFactor(
                name: "action_type",
                weight: baseRisk,
                description: "Base risk for \(action.type.rawValue)"
            ))
        }
        score += baseRisk

        // Amount factor
        if let dollars = risk.amountDollars {
            let amountFactor: Double
            if dollars >= preferences.veryLargeAmountThreshold {
                amountFactor = 0.30
            } else if dollars >= preferences.largeAmountThreshold {
                amountFactor = 0.20
            } else if dollars >= 50 {
                amountFactor = 0.05
            } else {
                amountFactor = 0.0
            }
            if amountFactor > 0 {
                factors.append(RiskFactor(
                    name: "large_amount",
                    weight: amountFactor,
                    description: String(format: "Amount $%.2f", dollars)
                ))
                score += amountFactor
            }
        }

        // Destructive
        if risk.isDestructive {
            let w = 0.25
            factors.append(RiskFactor(name: "destructive", weight: w, description: "Destructive action"))
            score += w
        }

        // Affects balance
        if risk.affectsBalance {
            let w = 0.15
            factors.append(RiskFactor(name: "balance_impact", weight: w, description: "Directly affects account balance"))
            score += w
        }

        // Multi-record
        if risk.affectsMultipleRecords {
            let w = 0.10
            factors.append(RiskFactor(name: "multi_record", weight: w, description: "Affects multiple records"))
            score += w
        }

        // Long-term planning
        if risk.affectsLongTermPlanning {
            let w = 0.10
            factors.append(RiskFactor(name: "long_term", weight: w, description: "Affects long-term planning state"))
            score += w
        }

        // Recurring
        if risk.isRecurringChange {
            let w = 0.10
            factors.append(RiskFactor(name: "recurring", weight: w, description: "Modifies recurring rules"))
            score += w
        }

        // High-value target
        if risk.isHighValueTarget {
            let w = 0.15
            factors.append(RiskFactor(name: "high_value_target", weight: w, description: "High-value target (account)"))
            score += w
        }

        return RiskScore(value: min(score, 1.0), factors: factors)
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Step 3: Base Action Rules
    // ══════════════════════════════════════════════════════════

    /// Default trust level based purely on the action type.
    /// This is the starting point before mode/risk/preference adjustments.
    private func baseActionRule(for type: AIAction.ActionType) -> AITrustLevel {
        switch type {

        // ── Likely auto ──
        // Analysis: read-only, no mutation
        case .analyze, .compare, .forecast, .advice:
            return .auto

        // ── Confirm ──
        // Add data
        case .addTransaction, .splitTransaction:
            return .confirm
        case .transfer:
            return .confirm

        // Edit data
        case .editTransaction, .editRecurring:
            return .confirm

        // Budget changes
        case .setBudget, .adjustBudget, .setCategoryBudget:
            return .confirm

        // Goal changes
        case .createGoal, .addContribution, .updateGoal,
             .pauseGoal, .archiveGoal:
            return .confirm

        // Withdraw is destructive — never auto-execute even at low amounts.
        case .withdrawFromGoal:
            return .neverAuto

        // Subscription + recurring
        case .addSubscription, .addRecurring:
            return .confirm

        // Account balance
        case .updateBalance:
            return .confirm

        // ── NeverAuto ──
        // Destructive operations default to neverAuto
        case .deleteTransaction:
            return .neverAuto
        case .cancelSubscription, .cancelRecurring:
            return .confirm  // destructive but reversible-ish — confirm default
        case .pauseSubscription:
            return .confirm  // softer than cancel; user can Resume from detail

        // Goal lifecycle ops added by Goals Rebuild — pause/archive are
        // confirmable, withdraw is destructive enough to require neverAuto.
        default:
            return .confirm
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Step 4: Mode Adjustments
    // ══════════════════════════════════════════════════════════

    /// Adjust trust level based on the current assistant mode.
    private func applyMode(
        base: AITrustLevel,
        action: AIAction,
        mode: AssistantMode
    ) -> AITrustLevel {
        let risk = action.type.riskLevel

        switch mode {
        case .advisor:
            // Advisor: nothing auto except analysis
            if base == .auto && risk != .none { return .confirm }
            return base

        case .assistant:
            // Assistant: auto for safe (low-risk) non-mutation, confirm rest
            // Does NOT upgrade confirm → auto for mutations
            return base

        case .autopilot:
            // Autopilot: auto for low+medium risk, confirm high
            if base == .confirm {
                switch risk {
                case .none, .low:    return .auto
                case .medium:        return .auto
                case .high:          return .confirm
                }
            }
            return base

        case .cfo:
            // CFO: auto for everything except neverAuto
            if base == .confirm { return .auto }
            return base
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Step 5: Risk Escalation
    // ══════════════════════════════════════════════════════════

    /// Escalate trust level if financial risk is high.
    private func applyRiskEscalation(
        base: AITrustLevel,
        risk: RiskAssessment,
        riskScore: RiskScore
    ) -> AITrustLevel {
        // If risk score is critical (0.8+), force neverAuto
        if riskScore.level == .critical && base != .neverAuto {
            return .neverAuto
        }

        // If risk score is high (0.6+), at least confirm
        if riskScore.level >= .high && base == .auto {
            return .confirm
        }

        // Large amounts: escalate auto → confirm
        if let dollars = risk.amountDollars {
            if dollars >= preferences.veryLargeAmountThreshold && base == .auto {
                return .confirm
            }
            if dollars >= preferences.largeAmountThreshold && base == .auto {
                return .confirm
            }
        }

        // Balance-affecting + large amount: escalate to confirm
        if risk.affectsBalance, let dollars = risk.amountDollars,
           dollars >= preferences.largeAmountThreshold, base == .auto {
            return .confirm
        }

        return base
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Step 6: Confidence Gate
    // ══════════════════════════════════════════════════════════

    /// If model/intent confidence is too low, don't auto-execute.
    private func applyConfidenceGate(base: AITrustLevel, confidence: Double) -> AITrustLevel {
        if base == .auto && confidence < preferences.minAutoConfidence {
            return .confirm
        }
        return base
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Step 7: User Preferences
    // ══════════════════════════════════════════════════════════

    /// Apply user-configurable overrides. Returns (level, wasInfluenced).
    private func applyUserPreferences(
        base: AITrustLevel,
        action: AIAction,
        risk: RiskAssessment
    ) -> (AITrustLevel, Bool) {
        var level = base
        var influenced = false

        // ── Safety overrides (escalate) ──

        // Never auto destructive (permanent deletion only)
        if preferences.neverAutoDestructive && risk.isDestructive && level != .neverAuto {
            level = .neverAuto
            influenced = true
        }

        // Never auto large amounts
        if preferences.neverAutoLargeAmounts,
           let dollars = risk.amountDollars,
           dollars >= preferences.veryLargeAmountThreshold,
           level == .auto {
            level = .confirm
            influenced = true
        }

        // ── Confirm-require overrides (escalate auto → confirm) ──

        // Require confirm for budget changes
        if preferences.requireConfirmBudgetChanges {
            switch action.type {
            case .setBudget, .adjustBudget, .setCategoryBudget:
                if level == .auto {
                    level = .confirm
                    influenced = true
                }
            default: break
            }
        }

        // Require confirm for recurring setup
        if preferences.requireConfirmRecurringSetup {
            switch action.type {
            case .addRecurring, .editRecurring, .cancelRecurring,
                 .addSubscription, .cancelSubscription, .pauseSubscription:
                if level == .auto {
                    level = .confirm
                    influenced = true
                }
            default: break
            }
        }

        // Require confirm for goal changes
        if preferences.requireConfirmGoalChanges {
            switch action.type {
            case .createGoal, .addContribution, .updateGoal,
                 .pauseGoal, .archiveGoal, .withdrawFromGoal:
                if level == .auto {
                    level = .confirm
                    influenced = true
                }
            default: break
            }
        }

        // ── Auto-allow overrides (can relax confirm → auto for low-risk ops) ──
        // These only apply to low-risk edit actions where the model is confident.
        // They never promote neverAuto or escalate — they can only relax confirm → auto.

        if level == .confirm && action.type == .editTransaction {
            let p = action.params

            // Auto-categorize: allow if the edit only changes the category field
            let isCategoryOnly = p.category != nil
                && p.amount == nil && p.note == nil
                && p.date == nil && p.transactionType == nil
            if isCategoryOnly && preferences.allowAutoCategorizaton {
                level = .auto
                influenced = true
            }

            // Auto-tag: allow if the edit only changes note/tag
            let isTagOnly = p.note != nil
                && p.amount == nil && p.category == nil
                && p.date == nil && p.transactionType == nil
            if isTagOnly && preferences.allowAutoTagging {
                level = .auto
                influenced = true
            }
        }

        // Auto-merchant cleanup: allow merchant normalization edits
        // (edit transaction where only the note is cleaned up, no amount/category change)
        if level == .confirm && action.type == .editTransaction && preferences.allowAutoMerchantCleanup {
            let p = action.params
            let isMerchantCleanup = p.note != nil
                && p.amount == nil && p.category == nil
                && p.date == nil && p.transactionType == nil
            if isMerchantCleanup {
                level = .auto
                influenced = true
            }
        }

        return (level, influenced)
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Reason Builder
    // ══════════════════════════════════════════════════════════

    private func buildReason(
        action: AIAction,
        finalLevel: AITrustLevel,
        baseLevel: AITrustLevel,
        riskScore: RiskScore,
        risk: RiskAssessment,
        confidence: Double,
        prefInfluenced: Bool,
        mode: AssistantMode
    ) -> String {
        var parts: [String] = []

        // Start with the action type
        parts.append("Action: \(action.type.rawValue)")

        // Risk level
        parts.append("Risk: \(riskScore.level.rawValue) (\(String(format: "%.2f", riskScore.value)))")

        // Why this level?
        if finalLevel == .auto {
            if action.type.riskLevel == .none {
                parts.append("Read-only action, safe to auto-execute")
            } else if prefInfluenced && baseLevel == .confirm {
                parts.append("User preference allows auto for this low-risk edit")
            } else {
                parts.append("Mode '\(mode.rawValue)' allows auto for this risk level")
            }
        } else if finalLevel == .confirm {
            if prefInfluenced {
                parts.append("User preference requires confirmation")
            } else if confidence < preferences.minAutoConfidence {
                parts.append("Confidence \(String(format: "%.0f%%", confidence * 100)) below threshold")
            } else if risk.amountDollars.map({ $0 >= preferences.largeAmountThreshold }) == true {
                parts.append("Large amount requires confirmation")
            } else {
                parts.append("Mutation action requires confirmation")
            }
        } else { // neverAuto
            if risk.isDestructive {
                parts.append("Destructive action blocked by safety policy")
            } else if riskScore.level == .critical {
                parts.append("Critical risk score blocked action")
            } else {
                parts.append("Action blocked by trust policy")
            }
        }

        return parts.joined(separator: " · ")
    }

    private func buildBlockMessage(action: AIAction, risk: RiskAssessment) -> String {
        if risk.isDestructive {
            return "This action (\(action.type.rawValue)) is destructive and cannot be auto-executed. Please perform it manually from the app."
        }
        if risk.isHighValueTarget {
            return "This action affects your account directly. For safety, it requires manual action."
        }
        return "This action was blocked by your trust policy. You can adjust trust settings if needed."
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Convenience: Legacy API
    // ══════════════════════════════════════════════════════════

    /// Get the trust level for a specific action type (quick check without full evaluation).
    func trustLevel(for actionType: AIAction.ActionType) -> AITrustLevel {
        baseActionRule(for: actionType)
    }
}
