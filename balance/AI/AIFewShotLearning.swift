import Foundation

// ============================================================
// MARK: - AI Few-Shot Learning
// ============================================================
//
// Learns from successful user interactions and builds dynamic
// few-shot examples that are injected into the system prompt.
//
// The model can't be fine-tuned on-device, but we can make it
// smarter by showing it real examples of what worked before.
//
// Data flow:
//   User interaction → recordSuccess() → examples stored
//   Next prompt → contextExamples() → injected into system prompt
//   Model sees real user patterns → better responses
//
// ============================================================

@MainActor
class AIFewShotLearning {
    static let shared = AIFewShotLearning()

    // MARK: - Storage

    private var examples: [FewShotExample] {
        didSet { save() }
    }

    /// Tracks which user messages have been seen to avoid duplicate examples.
    private var seenMessages: Set<String> = []

    private let storageKey = "ai.fewShotExamples"
    private let maxExamples = 30

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([FewShotExample].self, from: data) {
            self.examples = saved
            self.seenMessages = Set(saved.map { $0.normalizedInput })
        } else {
            self.examples = []
        }
    }

    // MARK: - Few-Shot Example Model

    struct FewShotExample: Codable, Identifiable {
        let id: UUID
        let userMessage: String        // what the user said
        let normalizedInput: String    // lowercased, trimmed — for dedup
        let actionType: String         // e.g. "add_transaction"
        let category: String?          // resolved category
        let amount: Int?               // cents
        let note: String?              // transaction note
        let wasAutoExecuted: Bool      // true if trust system auto-ran it
        let satisfactionScore: Int     // 1=undone, 2=corrected, 3=kept, 4=positive signal
        let recordedAt: Date
        let useCount: Int              // how many times similar input was seen

        /// Compact representation for prompt injection.
        var promptLine: String {
            var parts: [String] = []
            parts.append("\"\(userMessage)\"")
            parts.append("→ \(actionType)")
            if let cat = category { parts.append("[\(cat)]") }
            if let amt = amount {
                let dollars = Double(amt) / 100.0
                parts.append(String(format: "$%.2f", dollars))
            }
            if let n = note, !n.isEmpty { parts.append("(\(n))") }
            return parts.joined(separator: " ")
        }
    }

    // MARK: - Record Successful Interaction

    /// Called when an action is successfully executed (not undone, not rejected).
    func recordSuccess(
        userMessage: String,
        action: AIAction,
        wasAutoExecuted: Bool = false
    ) {
        let normalized = userMessage.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip very short or generic messages
        guard normalized.count >= 3 else { return }

        // Skip analysis-only actions (not learnable patterns)
        guard action.type.isMutation else { return }

        // Check if we already have a similar example
        if let idx = examples.firstIndex(where: { $0.normalizedInput == normalized }) {
            // Bump use count and satisfaction
            var updated = examples[idx]
            examples[idx] = FewShotExample(
                id: updated.id,
                userMessage: updated.userMessage,
                normalizedInput: updated.normalizedInput,
                actionType: updated.actionType,
                category: action.params.category ?? updated.category,
                amount: action.params.amount ?? updated.amount,
                note: action.params.note ?? updated.note,
                wasAutoExecuted: wasAutoExecuted,
                satisfactionScore: max(updated.satisfactionScore, 3),
                recordedAt: updated.recordedAt,
                useCount: updated.useCount + 1
            )
            return
        }

        let example = FewShotExample(
            id: UUID(),
            userMessage: userMessage.trimmingCharacters(in: .whitespacesAndNewlines),
            normalizedInput: normalized,
            actionType: action.type.rawValue,
            category: action.params.category,
            amount: action.params.amount,
            note: action.params.note,
            wasAutoExecuted: wasAutoExecuted,
            satisfactionScore: 3, // kept = good
            recordedAt: Date(),
            useCount: 1
        )

        examples.append(example)
        seenMessages.insert(normalized)

        // Prune old/low-quality examples
        pruneIfNeeded()
    }

    /// Called when user undoes an action — marks the example as bad.
    func recordUndo(userMessage: String) {
        let normalized = userMessage.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let idx = examples.firstIndex(where: { $0.normalizedInput == normalized }) {
            // Lower satisfaction score — if it drops to 0, remove it
            let current = examples[idx]
            if current.satisfactionScore <= 1 {
                examples.remove(at: idx)
                seenMessages.remove(normalized)
            } else {
                examples[idx] = FewShotExample(
                    id: current.id,
                    userMessage: current.userMessage,
                    normalizedInput: current.normalizedInput,
                    actionType: current.actionType,
                    category: current.category,
                    amount: current.amount,
                    note: current.note,
                    wasAutoExecuted: current.wasAutoExecuted,
                    satisfactionScore: current.satisfactionScore - 2,
                    recordedAt: current.recordedAt,
                    useCount: current.useCount
                )
            }
        }
    }

    /// Called when a correction happens — record what the user ACTUALLY wanted.
    func recordCorrection(
        userMessage: String,
        originalAction: AIAction,
        correctedCategory: String
    ) {
        let normalized = userMessage.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove the wrong example
        examples.removeAll { $0.normalizedInput == normalized }

        // Add the corrected version
        let corrected = FewShotExample(
            id: UUID(),
            userMessage: userMessage.trimmingCharacters(in: .whitespacesAndNewlines),
            normalizedInput: normalized,
            actionType: originalAction.type.rawValue,
            category: correctedCategory,
            amount: originalAction.params.amount,
            note: originalAction.params.note,
            wasAutoExecuted: false,
            satisfactionScore: 4, // correction = high confidence in new value
            recordedAt: Date(),
            useCount: 1
        )
        examples.append(corrected)
        seenMessages.insert(normalized)
    }

    // MARK: - Context Generation for System Prompt

    /// Generate few-shot examples block for the system prompt.
    /// Returns the best examples sorted by quality (satisfaction × useCount).
    func contextExamples(limit: Int = 8) -> String {
        let best = examples
            .filter { $0.satisfactionScore >= 2 }
            .sorted { score($0) > score($1) }
            .prefix(limit)

        guard !best.isEmpty else { return "" }

        var lines = ["LEARNED PATTERNS (from your past interactions):"]
        for ex in best {
            lines.append("  \(ex.promptLine)")
        }
        return lines.joined(separator: "\n")
    }

    /// Generate category preference summary — what categories the user uses most.
    func categoryPreferences() -> String {
        var catCounts: [String: Int] = [:]
        for ex in examples where ex.satisfactionScore >= 2 {
            if let cat = ex.category {
                catCounts[cat, default: 0] += ex.useCount
            }
        }

        let sorted = catCounts.sorted { $0.value > $1.value }
        guard !sorted.isEmpty else { return "" }

        let top = sorted.prefix(5).map { "\($0.key)(\($0.value)x)" }
        return "USER'S CATEGORY USAGE: \(top.joined(separator: ", "))"
    }

    /// Generate amount patterns — typical amounts per category.
    func amountPatterns() -> String {
        var catAmounts: [String: [Int]] = [:]
        for ex in examples where ex.satisfactionScore >= 2 {
            if let cat = ex.category, let amt = ex.amount, amt > 0 {
                catAmounts[cat, default: []].append(amt)
            }
        }

        guard !catAmounts.isEmpty else { return "" }

        var lines = ["TYPICAL AMOUNTS:"]
        for (cat, amounts) in catAmounts.sorted(by: { $0.key < $1.key }) {
            guard amounts.count >= 2 else { continue }
            let avg = amounts.reduce(0, +) / amounts.count
            let dollars = Double(avg) / 100.0
            lines.append("  \(cat): ~\(String(format: "$%.0f", dollars)) avg (\(amounts.count) transactions)")
        }
        return lines.count > 1 ? lines.joined(separator: "\n") : ""
    }

    // MARK: - Quality Score

    private func score(_ ex: FewShotExample) -> Double {
        let satisfaction = Double(ex.satisfactionScore)
        let frequency = Double(min(ex.useCount, 10))
        let recency = max(0, 30 - Date().timeIntervalSince(ex.recordedAt) / 86400) / 30.0
        return satisfaction * 2.0 + frequency * 1.5 + recency
    }

    // MARK: - Pruning

    private func pruneIfNeeded() {
        guard examples.count > maxExamples else { return }

        // Remove lowest-quality examples first
        examples.sort { score($0) > score($1) }
        examples = Array(examples.prefix(maxExamples))
        seenMessages = Set(examples.map { $0.normalizedInput })
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(examples) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Number of stored examples (for UI/debug).
    var exampleCount: Int { examples.count }

    /// Clear all learned examples.
    func reset() {
        examples = []
        seenMessages = []
    }
}
