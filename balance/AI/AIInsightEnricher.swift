import Foundation

// ============================================================
// MARK: - Insight Enricher (Phase 2 — iOS port)
// ============================================================
//
// Optional LLM pass that rewrites the top few insights' advice lines
// in a punchier, more conversational tone. Gated on:
//
//   1. `AIInsightEngine.shared.isInsightEnrichmentEnabled` (off by default)
//   2. Model currently `.ready` (never force a cold load just to rewrite
//      advice — heuristic text is good enough)
//   3. AIManager not currently generating another response
//
// Runs out-of-band from `refresh`: detectors publish synchronous
// heuristic advice immediately, then this pass swaps in AI-written
// advice when it finishes. Cheap fallback if the model is busy or
// unloaded — the user still sees warnings + heuristic advice.
// ============================================================

@MainActor
enum InsightEnricher {

    /// How many insights to enrich per pass. LLM round-trips aren't free
    /// so we cap to the most urgent items.
    private static let enrichBudget = 3

    /// Minimum severity worth enriching. Info/positive get the default
    /// heuristic advice — they're informational and don't need polish.
    private static let minSeverity: AIInsight.Severity = .warning

    /// System prompt aligned with Centmond's persona conventions: no emoji,
    /// no hedging, no fluff, short concrete directives.
    private static let systemPrompt = """
    You are Centmond, a direct financial co-pilot. Rewrite the user's \
    advice line in one punchy sentence, under 80 characters. No emoji. \
    No hedging. No "consider", "maybe", "try to". Use concrete verbs. \
    Keep the specific numbers or names if present. Output only the \
    rewritten line — no preamble, no quotes.
    """

    /// Entry point from `AIInsightEngine.refresh`. Returns a new array with
    /// up to `enrichBudget` insights' `advice` strings replaced. Order and
    /// identity (`id`, `dedupeKey`) are preserved so downstream dedupe /
    /// dismissal behavior isn't affected.
    static func enrich(_ insights: [AIInsight]) async -> [AIInsight] {
        guard shouldRun() else { return insights }

        let candidates = insights
            .enumerated()
            .filter { _, insight in
                insight.severity <= minSeverity && (insight.advice?.isEmpty == false)
            }
            .prefix(enrichBudget)
        guard !candidates.isEmpty else { return insights }

        var result = insights
        for (index, insight) in candidates {
            guard let advice = insight.advice else { continue }
            let prompt = "Warning: \(insight.body)\nCurrent advice: \(advice)"
            let rewritten = await AIManager.shared.generate(prompt, systemPrompt: systemPrompt)

            let cleaned = rewritten
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            guard !cleaned.isEmpty, cleaned.count <= 140 else { continue }

            result[index] = insight.withAdvice(cleaned)
        }
        return result
    }

    // MARK: - Gating

    private static func shouldRun() -> Bool {
        guard AIInsightEngine.shared.isInsightEnrichmentEnabled else { return false }
        guard case .ready = AIManager.shared.status else { return false }
        guard !AIManager.shared.isGenerating else { return false }
        return true
    }
}
