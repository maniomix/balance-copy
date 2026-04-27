import Foundation

// ============================================================
// MARK: - AI Trust Policy (Phase 2: Trust & Approval System)
// ============================================================
//
// Core types for the trust layer:
//   • TrustLevel — auto / confirm / neverAuto
//   • RiskScore  — 0.0–1.0 continuous risk assessment
//   • TrustDecision — the full result of evaluating one action
//   • RiskAssessment — financial risk signals for an action
//   • AIUserTrustPreferences — user-configurable trust settings
//
// These types feed into AITrustManager, which is the single
// source of truth for whether an action can proceed.
//
// ============================================================

// MARK: - Trust Level

/// Three-tier trust classification for any AI action.
enum AITrustLevel: String, Codable, CaseIterable, Identifiable {
    case auto      = "auto"        // execute immediately
    case confirm   = "confirm"     // show action card, wait for user
    case neverAuto = "neverAuto"   // block and explain

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:      return "Auto-execute"
        case .confirm:   return "Ask first"
        case .neverAuto: return "Block"
        }
    }

    var labelFarsi: String {
        switch self {
        case .auto:      return "اجرای خودکار"
        case .confirm:   return "تأیید بگیر"
        case .neverAuto: return "مسدود"
        }
    }

    var icon: String {
        switch self {
        case .auto:      return "bolt.fill"
        case .confirm:   return "hand.raised.fill"
        case .neverAuto: return "xmark.shield.fill"
        }
    }

    /// Severity ordering: neverAuto > confirm > auto.
    var severity: Int {
        switch self {
        case .auto:      return 0
        case .confirm:   return 1
        case .neverAuto: return 2
        }
    }

    /// Take the more conservative of two levels.
    func stricter(than other: AITrustLevel) -> AITrustLevel {
        self.severity >= other.severity ? self : other
    }
}

// MARK: - Risk Score

/// Continuous risk value: 0.0 = no risk, 1.0 = maximum risk.
/// Thresholds are defined in AITrustManager.
struct RiskScore: Comparable, Equatable {
    let value: Double
    let factors: [RiskFactor]

    static func == (lhs: RiskScore, rhs: RiskScore) -> Bool {
        lhs.value == rhs.value
    }

    static func < (lhs: RiskScore, rhs: RiskScore) -> Bool {
        lhs.value < rhs.value
    }

    static let zero = RiskScore(value: 0, factors: [])

    /// Human-readable risk level derived from score.
    var level: RiskLevel {
        switch value {
        case ..<0.15:    return .none
        case ..<0.35:    return .low
        case ..<0.60:    return .medium
        case ..<0.80:    return .high
        default:         return .critical
        }
    }

    enum RiskLevel: String, Codable, Comparable {
        case none     = "none"
        case low      = "low"
        case medium   = "medium"
        case high     = "high"
        case critical = "critical"

        static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
            lhs.order < rhs.order
        }

        private var order: Int {
            switch self {
            case .none: return 0
            case .low: return 1
            case .medium: return 2
            case .high: return 3
            case .critical: return 4
            }
        }
    }
}

/// A named factor that contributed to a risk score.
struct RiskFactor: Codable {
    let name: String       // e.g. "large_amount", "destructive", "multi_record"
    let weight: Double     // how much it contributed (0.0–1.0)
    let description: String
}

// MARK: - Trust Decision

/// The full result of evaluating one action through the trust policy.
/// This is what the trust manager returns for each proposed AI action.
struct TrustDecision: Identifiable {
    let id: UUID                 // matches the action id
    let actionType: AIAction.ActionType
    let level: AITrustLevel
    let reason: String           // human-readable explanation
    let riskScore: RiskScore
    let confidenceUsed: Double   // model/intent confidence at decision time
    let preferenceInfluenced: Bool // was the decision changed by user prefs?
    let blockMessage: String?    // explanation if neverAuto

    /// Summary for audit/debug.
    var summary: String {
        let prefix = level == .neverAuto ? "🛑" : level == .confirm ? "⚠️" : "✅"
        return "\(prefix) \(actionType.rawValue): \(level.rawValue) — \(reason)"
    }
}

// MARK: - Risk Assessment

/// Financial risk signals extracted from one action's payload.
/// Built by the trust manager before scoring.
struct RiskAssessment {
    let amountCents: Int?
    let isDestructive: Bool
    let affectsBalance: Bool
    let affectsMultipleRecords: Bool
    let affectsLongTermPlanning: Bool
    let isRecurringChange: Bool
    let isHighValueTarget: Bool   // e.g. account deletion, data wipe

    /// Amount in dollars for threshold comparison.
    var amountDollars: Double? {
        guard let cents = amountCents else { return nil }
        return Double(cents) / 100.0
    }

    static let empty = RiskAssessment(
        amountCents: nil,
        isDestructive: false,
        affectsBalance: false,
        affectsMultipleRecords: false,
        affectsLongTermPlanning: false,
        isRecurringChange: false,
        isHighValueTarget: false
    )
}

// MARK: - Classified Actions

/// The output of running trust evaluation on a batch of actions.
struct TrustClassifiedActions {
    let auto: [(AIAction, TrustDecision)]
    let confirm: [(AIAction, TrustDecision)]
    let blocked: [(AIAction, TrustDecision)]

    /// All decisions in one list.
    var allDecisions: [TrustDecision] {
        auto.map(\.1) + confirm.map(\.1) + blocked.map(\.1)
    }
}

// MARK: - Action Group

/// Groups related action types for trust configuration.
/// Users set trust per group, not per individual action type.
enum AIActionGroup: String, Codable, CaseIterable, Identifiable {
    case transactions  = "transactions"
    case budgets       = "budgets"
    case goals         = "goals"
    case subscriptions = "subscriptions"
    case accounts      = "accounts"
    case analysis      = "analysis"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .transactions:  return "Transactions"
        case .budgets:       return "Budgets"
        case .goals:         return "Goals"
        case .subscriptions: return "Subscriptions"
        case .accounts:      return "Accounts"
        case .analysis:      return "Analysis"
        }
    }

    var icon: String {
        switch self {
        case .transactions:  return "arrow.left.arrow.right"
        case .budgets:       return "chart.pie.fill"
        case .goals:         return "target"
        case .subscriptions: return "repeat"
        case .accounts:      return "banknote.fill"
        case .analysis:      return "chart.bar.fill"
        }
    }

    /// Default trust level — safe defaults: analysis auto, everything else confirm.
    var defaultTrust: AITrustLevel {
        switch self {
        case .analysis: return .auto
        default:        return .confirm
        }
    }

    /// Which action types belong to this group.
    var actionTypes: [AIAction.ActionType] {
        switch self {
        case .transactions:
            return [.addTransaction, .editTransaction, .deleteTransaction,
                    .splitTransaction, .transfer,
                    .addRecurring, .editRecurring, .cancelRecurring]
        case .budgets:
            return [.setBudget, .adjustBudget, .setCategoryBudget]
        case .goals:
            return [.createGoal, .addContribution, .updateGoal,
                    .pauseGoal, .archiveGoal, .withdrawFromGoal]
        case .subscriptions:
            return [.addSubscription, .cancelSubscription]
        case .accounts:
            return [.updateBalance]
        case .analysis:
            return [.analyze, .compare, .forecast, .advice]
        }
    }

    /// Find the group for a given action type.
    static func group(for actionType: AIAction.ActionType) -> AIActionGroup {
        for group in AIActionGroup.allCases {
            if group.actionTypes.contains(actionType) { return group }
        }
        return .analysis
    }
}

// MARK: - User Trust Preferences

/// User-configurable settings that feed into trust decisions.
/// Persisted to UserDefaults.
struct AIUserTrustPreferences: Codable, Equatable {

    // ── Auto-allow toggles ──
    /// Allow auto-categorization of transactions.
    var allowAutoCategorizaton: Bool = true

    /// Allow auto-tagging (notes, labels).
    var allowAutoTagging: Bool = true

    /// Allow auto-execution of merchant normalization (rename to canonical name).
    var allowAutoMerchantCleanup: Bool = true

    // ── Confirm-require toggles ──
    /// Always require confirmation for budget changes, even if mode says auto.
    var requireConfirmBudgetChanges: Bool = true

    /// Always require confirmation for recurring setup/edit.
    var requireConfirmRecurringSetup: Bool = true

    /// Always require confirmation for goal changes.
    var requireConfirmGoalChanges: Bool = false

    // ── Safety toggles ──
    /// Never auto-apply destructive actions (delete, cancel, wipe).
    var neverAutoDestructive: Bool = true

    /// Never auto-apply actions above the large-amount threshold.
    var neverAutoLargeAmounts: Bool = true

    // ── Thresholds ──
    /// Amount (in dollars) above which an action is considered "large".
    /// Default $200 — triggers extra caution.
    var largeAmountThreshold: Double = 200.0

    /// Amount (in dollars) above which an action is very large.
    /// Default $1000 — forces confirmation even in CFO mode.
    var veryLargeAmountThreshold: Double = 1000.0

    /// Minimum model confidence to allow auto-execution.
    /// Below this, action always requires confirmation.
    var minAutoConfidence: Double = 0.7

    // MARK: - Persistence

    private static let storageKey = "ai.userTrustPreferences"

    static func load() -> AIUserTrustPreferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let prefs = try? JSONDecoder().decode(AIUserTrustPreferences.self, from: data)
        else { return AIUserTrustPreferences() }
        return prefs
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AIUserTrustPreferences.storageKey)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
