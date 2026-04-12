import Foundation
import Combine

// ============================================================
// MARK: - AI Prompt Versioning & Graceful Degradation (Phase 8)
// ============================================================
//
// Tracks system prompt versions for A/B testing and rollback.
// Provides graceful degradation when the model is unavailable,
// warming up, or returns malformed output.
//
// Also includes fallback UX templates for common scenarios
// so the app remains functional even without LLM inference.
//
// ============================================================

// MARK: - Prompt Versioning

struct PromptVersion: Codable, Identifiable {
    let id: UUID
    let version: String          // e.g. "2.1.0"
    let timestamp: Date
    let changelog: String
    let promptHash: String       // SHA256 of full prompt text

    init(version: String, changelog: String, promptHash: String) {
        self.id = UUID()
        self.version = version
        self.timestamp = Date()
        self.changelog = changelog
        self.promptHash = promptHash
    }
}

/// Tracks which prompt version is active and performance metrics per version.
struct PromptPerformance: Codable {
    let version: String
    var totalRequests: Int = 0
    var successfulParses: Int = 0     // Actions parsed successfully
    var parseFailures: Int = 0        // Malformed output
    var clarificationsTriggered: Int = 0
    var averageResponseLength: Int = 0
    var userSatisfactionSignals: Int = 0  // e.g., user didn't correct/undo

    var parseSuccessRate: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(successfulParses) / Double(totalRequests)
    }

    var clarificationRate: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(clarificationsTriggered) / Double(totalRequests)
    }
}

// MARK: - Model Status for Degradation

/// Extended model health status for degradation decisions.
enum AIModelHealth {
    case healthy                // Model loaded, responding normally
    case warming                // Model loading, not yet ready
    case degraded(String)       // Partially functional (e.g., slow responses)
    case unavailable(String)    // Model not loaded or errored
    case malformedOutput        // Model responding but output unparseable

    var canAttemptInference: Bool {
        switch self {
        case .healthy, .degraded: return true
        default: return false
        }
    }

    var shouldUseFallback: Bool {
        switch self {
        case .warming, .unavailable, .malformedOutput: return true
        default: return false
        }
    }
}

// MARK: - Fallback Templates

/// Pre-built response templates for when the LLM is unavailable.
enum AIFallbackTemplates {

    /// Fallback response for a given intent type when LLM is unavailable.
    static func response(for intentType: IntentType, language: String = "en") -> String {
        let isFarsi = language == "fa"

        switch intentType {
        case .addData:
            return isFarsi
                ? "مدل هوش مصنوعی در حال بارگذاری است. لطفاً مبلغ و دسته‌بندی را مستقیماً وارد کنید."
                : "AI model is loading. Please enter the data manually for now."

        case .editData:
            return isFarsi
                ? "مدل در دسترس نیست. ویرایش را مستقیماً از لیست انجام دهید."
                : "Model unavailable. You can edit directly from the list."

        case .deleteData:
            return isFarsi
                ? "مدل در دسترس نیست. حذف را مستقیماً از لیست انجام دهید."
                : "Model unavailable. You can delete directly from the list."

        case .analyze, .askQuestion:
            return isFarsi
                ? "تحلیل هوشمند فعلاً در دسترس نیست. لطفاً چند لحظه دیگر امتحان کنید."
                : "Smart analysis is temporarily unavailable. Please try again in a moment."

        case .forecast, .compare:
            return isFarsi
                ? "تحلیل هوشمند فعلاً در دسترس نیست. لطفاً چند لحظه دیگر امتحان کنید."
                : "Smart analysis is temporarily unavailable. Please try again in a moment."

        case .plan:
            return isFarsi
                ? "مدل در حال آماده‌سازی است. بودجه را از تنظیمات تغییر دهید."
                : "Model is warming up. You can set your budget from Settings in the meantime."

        case .automate:
            return isFarsi
                ? "مدل هوش مصنوعی فعلاً در دسترس نیست. لطفاً بعداً امتحان کنید."
                : "AI model is temporarily unavailable. Please try again shortly."

        case .correctPreviousAction:
            return isFarsi
                ? "مدل هوش مصنوعی فعلاً در دسترس نیست. لطفاً بعداً امتحان کنید."
                : "AI model is temporarily unavailable. Please try again shortly."

        case .reviewItems, .monthlyClose:
            return isFarsi
                ? "مدل هوش مصنوعی فعلاً در دسترس نیست. لطفاً بعداً امتحان کنید."
                : "AI model is temporarily unavailable. Please try again shortly."

        case .onboarding:
            return isFarsi
                ? "سلام! مدل در حال آماده‌سازی است. تا چند لحظه دیگر آماده میشم."
                : "Hi! The AI model is warming up. I'll be ready in just a moment."

        case .clarify:
            return isFarsi
                ? "مدل هوش مصنوعی فعلاً در دسترس نیست. لطفاً بعداً امتحان کنید."
                : "AI model is temporarily unavailable. Please try again shortly."
        }
    }

    /// Fallback response for malformed model output.
    static func malformedOutputResponse(language: String = "en") -> String {
        language == "fa"
            ? "پاسخ مدل قابل پردازش نبود. لطفاً دوباره امتحان کنید یا سؤالتان را ساده‌تر بپرسید."
            : "I had trouble processing that response. Could you try rephrasing your request?"
    }

    /// Fallback response for model timeout.
    static func timeoutResponse(language: String = "en") -> String {
        language == "fa"
            ? "پاسخ خیلی طول کشید. لطفاً دوباره امتحان کنید."
            : "The response took too long. Please try again."
    }

    /// Quick-action suggestions to show when model is unavailable.
    static func quickActions(language: String = "en") -> [(title: String, icon: String)] {
        if language == "fa" {
            return [
                ("افزودن هزینه", "plus.circle"),
                ("مشاهده بودجه", "chart.pie"),
                ("اهداف من", "target"),
                ("اشتراک‌ها", "repeat")
            ]
        }
        return [
            ("Add expense", "plus.circle"),
            ("View budget", "chart.pie"),
            ("My goals", "target"),
            ("Subscriptions", "repeat")
        ]
    }
}

// MARK: - Prompt Version Manager

@MainActor
class AIPromptVersionManager: ObservableObject {
    static let shared = AIPromptVersionManager()

    @Published private(set) var currentVersion: String
    @Published private(set) var performance: PromptPerformance
    @Published private(set) var modelHealth: AIModelHealth = .unavailable("Not initialized")

    private var versionHistory: [PromptVersion] = []
    private var consecutiveMalformed: Int = 0
    private let maxMalformedBeforeDegradation = 3

    private let versionKey = "ai.promptVersion"
    private let performanceKey = "ai.promptPerformance"
    private let historyKey = "ai.promptHistory"

    static let CURRENT_VERSION = "3.0.0"

    private init() {
        let savedVersion = UserDefaults.standard.string(forKey: versionKey) ?? Self.CURRENT_VERSION
        self.currentVersion = savedVersion

        if let data = UserDefaults.standard.data(forKey: performanceKey),
           let saved = try? JSONDecoder().decode(PromptPerformance.self, from: data) {
            self.performance = saved
        } else {
            self.performance = PromptPerformance(version: savedVersion)
        }

        loadHistory()
    }

    // MARK: - Health Monitoring

    /// Update model health based on AIManager status.
    func updateHealth(from status: AIModelStatus) {
        switch status {
        case .ready:
            modelHealth = .healthy
            consecutiveMalformed = 0
        case .loading:
            modelHealth = .warming
        case .notLoaded:
            modelHealth = .unavailable("Model not loaded")
        case .error(let msg):
            modelHealth = .unavailable(msg)
        case .generating:
            modelHealth = .healthy
        case .downloading(let progress, _):
            modelHealth = .warming
            _ = progress // Acknowledge download progress
        }
    }

    /// Record a successful parse.
    func recordSuccess(responseLength: Int) {
        performance.totalRequests += 1
        performance.successfulParses += 1
        performance.averageResponseLength =
            (performance.averageResponseLength * (performance.totalRequests - 1) + responseLength) / performance.totalRequests
        consecutiveMalformed = 0

        if modelHealth.shouldUseFallback {
            modelHealth = .healthy
        }

        savePerformance()
    }

    /// Record a parse failure (malformed output).
    func recordParseFailure() {
        performance.totalRequests += 1
        performance.parseFailures += 1
        consecutiveMalformed += 1

        if consecutiveMalformed >= maxMalformedBeforeDegradation {
            modelHealth = .malformedOutput
        }

        savePerformance()
    }

    /// Record a clarification triggered.
    func recordClarification() {
        performance.clarificationsTriggered += 1
        savePerformance()
    }

    /// Record positive signal (user didn't undo/correct).
    func recordSatisfaction() {
        performance.userSatisfactionSignals += 1
        savePerformance()
    }

    // MARK: - Fallback Decision

    /// Whether to use fallback templates instead of LLM.
    func shouldUseFallback() -> Bool {
        modelHealth.shouldUseFallback
    }

    /// Get fallback response for current state.
    func fallbackResponse(intentType: IntentType) -> String? {
        guard shouldUseFallback() else { return nil }
        let lang = AIUserPreferences.shared.preferredLanguage
        return AIFallbackTemplates.response(for: intentType, language: lang)
    }

    // MARK: - Version Management

    /// Register current prompt version with changelog.
    func registerVersion(changelog: String) {
        let hash = hashPrompt(AISystemPrompt.build())
        let version = PromptVersion(
            version: currentVersion,
            changelog: changelog,
            promptHash: hash
        )
        versionHistory.append(version)
        saveHistory()
    }

    /// Check if prompt has changed since last registered version.
    func hasPromptChanged() -> Bool {
        guard let last = versionHistory.last else { return true }
        let currentHash = hashPrompt(AISystemPrompt.build())
        return currentHash != last.promptHash
    }

    /// Get performance comparison between versions.
    func versionComparison() -> String {
        guard performance.totalRequests > 0 else { return "No data yet" }
        return """
            Prompt v\(currentVersion):
              Requests: \(performance.totalRequests)
              Parse success: \(Int(performance.parseSuccessRate * 100))%
              Clarification rate: \(Int(performance.clarificationRate * 100))%
              Avg response length: \(performance.averageResponseLength) chars
            """
    }

    // MARK: - Retry Logic

    /// Get retry strategy for current health state.
    func retryStrategy() -> RetryStrategy {
        switch modelHealth {
        case .healthy:
            return .none
        case .warming:
            return .waitAndRetry(seconds: 3)
        case .degraded:
            return .retryOnce
        case .unavailable:
            return .fallback
        case .malformedOutput:
            return .retryWithSimplifiedPrompt
        }
    }

    enum RetryStrategy {
        case none
        case retryOnce
        case waitAndRetry(seconds: Int)
        case retryWithSimplifiedPrompt
        case fallback
    }

    // MARK: - Persistence

    private func savePerformance() {
        if let data = try? JSONEncoder().encode(performance) {
            UserDefaults.standard.set(data, forKey: performanceKey)
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let saved = try? JSONDecoder().decode([PromptVersion].self, from: data) {
            versionHistory = saved
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(versionHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func hashPrompt(_ prompt: String) -> String {
        // Simple hash — sufficient for change detection
        var hash: UInt64 = 5381
        for char in prompt.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(char)
        }
        return String(hash, radix: 16)
    }
}
