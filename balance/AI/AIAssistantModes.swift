import Foundation
import Combine

// ============================================================
// MARK: - AI Assistant Modes (Phase 6 + Phase 9 Enhancement)
// ============================================================
//
// Configurable assistant behavior modes that change how the AI
// interacts with the user — from cautious advisor to full
// autonomous CFO.
//
// Modes affect: trust defaults, proactivity, verbosity,
// auto-execution, confidence thresholds, optimization emphasis,
// proactive intensity, tone, and clarification behavior.
//
// Phase 9 additions:
//   • ProactiveIntensity — controls volume of proactive items
//   • OptimizationEmphasis — controls optimization framing
//   • Richer behavior descriptions for mode selection UI
//   • Integration hooks for AIProactive, AIOptimizer,
//     AIClarificationEngine, AISystemPrompt
//
// ============================================================

// ══════════════════════════════════════════════════════════════
// MARK: - Mode Behavior Sub-Types
// ══════════════════════════════════════════════════════════════

/// How aggressively the AI generates proactive items.
enum ProactiveIntensity: String, Codable, CaseIterable {
    case none     = "none"      // No proactive items at all
    case light    = "light"     // Only critical/warning items
    case moderate = "moderate"  // Normal — all items shown
    case high     = "high"      // Extra items + lower thresholds

    var title: String {
        switch self {
        case .none:     return "Off"
        case .light:    return "Light"
        case .moderate: return "Moderate"
        case .high:     return "High"
        }
    }

    /// Minimum severity to show. Items with severity > this are filtered out.
    var minimumSeverity: Int {
        switch self {
        case .none:     return -1    // Nothing passes
        case .light:    return 1     // .critical (0) and .warning (1) only
        case .moderate: return 3     // Everything passes
        case .high:     return 3     // Everything + lower thresholds
        }
    }

    /// Whether to include info/positive severity items.
    var includesInfoItems: Bool {
        switch self {
        case .none, .light: return false
        case .moderate, .high: return true
        }
    }
}

/// How strongly the optimizer frames recommendations.
enum OptimizationEmphasis: String, Codable, CaseIterable {
    case optional   = "optional"    // Soft suggestions, "you could..."
    case moderate   = "moderate"    // Balanced recommendations
    case strong     = "strong"      // Urgent/imperative tone, "you should..."

    var title: String {
        switch self {
        case .optional: return "Optional"
        case .moderate: return "Moderate"
        case .strong:   return "Strong"
        }
    }

    /// Prefix for recommendation titles.
    var prefix: String {
        switch self {
        case .optional: return "Consider:"
        case .moderate: return ""
        case .strong:   return "Action needed:"
        }
    }
}

/// The assistant's operating mode, chosen by the user.
enum AssistantMode: String, Codable, CaseIterable, Identifiable {
    case advisor    = "advisor"
    case assistant  = "assistant"
    case autopilot  = "autopilot"
    case cfo        = "cfo"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .advisor:   return "Advisor"
        case .assistant:  return "Assistant"
        case .autopilot:  return "Autopilot"
        case .cfo:        return "CFO"
        }
    }

    var titleFarsi: String {
        switch self {
        case .advisor:   return "مشاور"
        case .assistant:  return "دستیار"
        case .autopilot:  return "خودکار"
        case .cfo:        return "مدیرمالی"
        }
    }

    var icon: String {
        switch self {
        case .advisor:   return "lightbulb.fill"
        case .assistant:  return "person.fill"
        case .autopilot:  return "bolt.fill"
        case .cfo:        return "briefcase.fill"
        }
    }

    var description: String {
        switch self {
        case .advisor:
            return "Suggests actions but never executes. Always asks for confirmation. Best for learning and careful control."
        case .assistant:
            return "Executes safe actions automatically (add transactions, analyze). Confirms risky actions (delete, large amounts)."
        case .autopilot:
            return "Executes most actions automatically. Only confirms destructive operations. Best for power users."
        case .cfo:
            return "Full autonomy. Proactively manages budgets, detects issues, suggests optimizations. Minimal interruptions."
        }
    }

    var descriptionFarsi: String {
        switch self {
        case .advisor:
            return "فقط پیشنهاد میده، هیچ‌وقت خودش اجرا نمیکنه. همیشه تأیید میگیره."
        case .assistant:
            return "کارهای امن رو خودکار انجام میده. برای کارهای حساس تأیید میگیره."
        case .autopilot:
            return "بیشتر کارها رو خودکار انجام میده. فقط برای حذف تأیید میگیره."
        case .cfo:
            return "استقلال کامل. خودش بودجه مدیریت میکنه و مشکلات رو شناسایی میکنه."
        }
    }

    // MARK: - Phase 9: Detailed Behavior Descriptions (for UI)

    /// Short tagline for mode selection cards.
    var tagline: String {
        switch self {
        case .advisor:   return "You decide everything"
        case .assistant:  return "Safe actions auto-run"
        case .autopilot:  return "Minimal interruptions"
        case .cfo:        return "Full financial autopilot"
        }
    }

    /// Bullet-point behavior differences for the mode picker.
    var behaviorBullets: [String] {
        switch self {
        case .advisor:
            return [
                "Always asks before acting",
                "Detailed explanations",
                "No proactive alerts",
                "Gentle optimization suggestions"
            ]
        case .assistant:
            return [
                "Auto-runs safe actions (add, analyze)",
                "Asks for risky actions (delete, large amounts)",
                "Light proactive alerts",
                "Balanced recommendations"
            ]
        case .autopilot:
            return [
                "Auto-runs most actions",
                "Only asks for destructive ops",
                "Active proactive monitoring",
                "Direct, action-oriented"
            ]
        case .cfo:
            return [
                "Full autonomous execution",
                "Proactive issue detection",
                "Strong optimization emphasis",
                "Brief status updates only"
            ]
        }
    }

    // MARK: - Behavior Configuration

    /// Minimum confidence to skip clarification (lower = more permissive).
    var clarificationThreshold: Double {
        switch self {
        case .advisor:   return 0.7
        case .assistant:  return 0.5
        case .autopilot:  return 0.3
        case .cfo:        return 0.2
        }
    }

    /// Whether to auto-execute non-destructive actions.
    var autoExecuteSafe: Bool {
        switch self {
        case .advisor:   return false
        case .assistant:  return true
        case .autopilot:  return true
        case .cfo:        return true
        }
    }

    /// Whether to auto-execute medium-risk actions.
    var autoExecuteMedium: Bool {
        switch self {
        case .advisor:   return false
        case .assistant:  return false
        case .autopilot:  return true
        case .cfo:        return true
        }
    }

    /// Whether to auto-execute high-risk (destructive) actions.
    var autoExecuteHigh: Bool {
        switch self {
        case .advisor:   return false
        case .assistant:  return false
        case .autopilot:  return false
        case .cfo:        return true
        }
    }

    /// Whether the AI proactively generates insights.
    var proactiveInsights: Bool {
        switch self {
        case .advisor:   return false
        case .assistant:  return true
        case .autopilot:  return true
        case .cfo:        return true
        }
    }

    /// Whether to show detailed explanations in responses.
    var verboseResponses: Bool {
        switch self {
        case .advisor:   return true
        case .assistant:  return true
        case .autopilot:  return false
        case .cfo:        return false
        }
    }

    /// Large amount threshold multiplier (higher = less cautious).
    var largeAmountMultiplier: Double {
        switch self {
        case .advisor:   return 1.0    // Default sensitivity
        case .assistant:  return 1.5
        case .autopilot:  return 3.0
        case .cfo:        return 5.0
        }
    }

    // MARK: - Phase 9: Extended Behavior Properties

    /// Proactive item intensity per mode.
    var proactiveIntensity: ProactiveIntensity {
        switch self {
        case .advisor:   return .none
        case .assistant:  return .light
        case .autopilot:  return .moderate
        case .cfo:        return .high
        }
    }

    /// How strongly optimization recommendations are framed.
    var optimizationEmphasis: OptimizationEmphasis {
        switch self {
        case .advisor:   return .optional
        case .assistant:  return .moderate
        case .autopilot:  return .moderate
        case .cfo:        return .strong
        }
    }

    /// Whether to auto-show optimization results without user request.
    var autoShowOptimizations: Bool {
        switch self {
        case .advisor, .assistant:  return false
        case .autopilot, .cfo:      return true
        }
    }

    /// Max number of recommendations to show in compact/card views.
    var maxCompactRecommendations: Int {
        switch self {
        case .advisor:   return 3   // Show more detail
        case .assistant:  return 2
        case .autopilot:  return 2
        case .cfo:        return 1   // Brief — just top priority
        }
    }

    /// Whether the mode should skip clarification for medium-confidence intents.
    /// Works alongside clarificationThreshold for finer control.
    var skipsMediumClarification: Bool {
        switch self {
        case .advisor:   return false
        case .assistant:  return false
        case .autopilot:  return true
        case .cfo:        return true
        }
    }

    /// System prompt modifier for this mode.
    var promptModifier: String {
        switch self {
        case .advisor:
            return """
                MODE: Advisor — You are a cautious financial advisor. \
                NEVER auto-execute actions. Always present options and ask for confirmation. \
                Explain your reasoning thoroughly. Use phrases like "I suggest..." and "Would you like me to...?" \
                Provide detailed analysis with every recommendation. Be educational and transparent.
                """
        case .assistant:
            return """
                MODE: Assistant — You are a helpful finance assistant. \
                Execute safe actions (adding transactions, analyzing data) directly. \
                For budget changes, deletions, or large amounts, ask for confirmation first. \
                Be concise but friendly. Give clear explanations when asked.
                """
        case .autopilot:
            return """
                MODE: Autopilot — You are an efficient finance manager. \
                Execute actions quickly with minimal conversation. \
                Only pause for destructive operations (delete, cancel). \
                Skip pleasantries, be direct and action-oriented. \
                Focus on getting things done fast.
                """
        case .cfo:
            return """
                MODE: CFO — You are the user's personal Chief Financial Officer. \
                Take full ownership of their finances. Execute all actions autonomously. \
                Proactively identify issues, suggest optimizations, and implement improvements. \
                Communicate in brief status updates. Think strategically about their financial health. \
                Flag risks early, act on opportunities immediately.
                """
        }
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: - Mode Manager
// ══════════════════════════════════════════════════════════════

@MainActor
class AIAssistantModeManager: ObservableObject {
    static let shared = AIAssistantModeManager()

    @Published var currentMode: AssistantMode {
        didSet {
            UserDefaults.standard.set(currentMode.rawValue, forKey: modeKey)
            // Notify other systems of mode change
            NotificationCenter.default.post(name: .aiModeDidChange, object: currentMode)
        }
    }

    private let modeKey = "ai.assistantMode"

    private init() {
        let saved = UserDefaults.standard.string(forKey: modeKey) ?? ""
        self.currentMode = AssistantMode(rawValue: saved) ?? .assistant
    }

    /// Whether clarification should be skipped at given confidence.
    func shouldSkipClarification(confidence: Double) -> Bool {
        confidence >= currentMode.clarificationThreshold
    }

    /// Get prompt modifier for system prompt injection.
    var promptModifier: String {
        currentMode.promptModifier
    }

    // MARK: - Phase 9: Convenience Accessors

    /// Current proactive intensity.
    var proactiveIntensity: ProactiveIntensity {
        currentMode.proactiveIntensity
    }

    /// Current optimization emphasis.
    var optimizationEmphasis: OptimizationEmphasis {
        currentMode.optimizationEmphasis
    }

    /// Whether proactive items should be generated at all.
    var isProactiveEnabled: Bool {
        currentMode.proactiveInsights
    }

    /// Short display label for mode indicator in chat.
    var modeIndicatorLabel: String {
        "\(currentMode.icon) \(currentMode.title)"
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: - Notification
// ══════════════════════════════════════════════════════════════

extension Notification.Name {
    static let aiModeDidChange = Notification.Name("aiModeDidChange")
}
