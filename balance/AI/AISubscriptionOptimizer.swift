import Foundation

// ============================================================
// MARK: - AI Subscription Optimizer
// ============================================================
//
// Phase 7 deliverable: analyzes active subscriptions to find
// savings opportunities — cancellation candidates, overlaps,
// downgrades, and price increases.
//
// Pure heuristic — no LLM needed.
//
// ============================================================

struct SubscriptionOptimizationResult {
    let totalMonthlyCost: Int          // cents
    let totalYearlyCost: Int           // cents
    let recommendations: [Recommendation]
    let potentialSavings: Int          // cents/month

    struct Recommendation: Identifiable {
        let id = UUID()
        let type: RecommendationType
        let subscriptionName: String
        let reason: String
        let potentialSaving: Int       // cents/month
        let confidence: Double         // 0–1

        enum RecommendationType {
            case cancel          // Unused or rarely used
            case downgrade       // Could switch to cheaper plan
            case overlap         // Similar to another subscription
            case priceIncrease   // Price went up since initial add
            case freeAlternative // Free alternative exists
        }
    }

    /// Summary for AI context.
    func summary() -> String {
        var lines: [String] = []
        lines.append("Total subscriptions: \(formatCents(totalMonthlyCost))/month (\(formatCents(totalYearlyCost))/year)")

        if recommendations.isEmpty {
            lines.append("No optimization opportunities found.")
        } else {
            lines.append("Found \(recommendations.count) optimization opportunities:")
            for rec in recommendations {
                lines.append("  • \(rec.subscriptionName): \(rec.reason) (save \(formatCents(rec.potentialSaving))/mo)")
            }
            lines.append("Potential monthly savings: \(formatCents(potentialSavings))")
        }
        return lines.joined(separator: "\n")
    }

    private func formatCents(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100.0)
    }
}

@MainActor
class AISubscriptionOptimizer {
    static let shared = AISubscriptionOptimizer()

    private init() {}

    /// Analyze all subscriptions and return optimization recommendations.
    func analyze() -> SubscriptionOptimizationResult {
        let subs = SubscriptionEngine.shared.subscriptions.filter { $0.status == .active }

        let totalMonthly = subs.reduce(0) { $0 + $1.monthlyCost }
        let totalYearly = totalMonthly * 12

        var recommendations: [SubscriptionOptimizationResult.Recommendation] = []

        // ── 1. Overlap detection ──
        recommendations.append(contentsOf: detectOverlaps(subs))

        // ── 2. High-cost subscriptions ──
        recommendations.append(contentsOf: detectHighCost(subs, totalMonthly: totalMonthly))

        // ── 3. Unused/low-value detection (based on age without activity) ──
        recommendations.append(contentsOf: detectPotentiallyUnused(subs))

        // ── 4. Free alternative suggestions ──
        recommendations.append(contentsOf: suggestFreeAlternatives(subs))

        let potentialSavings = recommendations.reduce(0) { $0 + $1.potentialSaving }

        return SubscriptionOptimizationResult(
            totalMonthlyCost: totalMonthly,
            totalYearlyCost: totalYearly,
            recommendations: recommendations.sorted { $0.potentialSaving > $1.potentialSaving },
            potentialSavings: potentialSavings
        )
    }

    // MARK: - Detection Methods

    /// Detect overlapping services (e.g., multiple music or video streaming).
    private func detectOverlaps(_ subs: [DetectedSubscription]) -> [SubscriptionOptimizationResult.Recommendation] {
        var recs: [SubscriptionOptimizationResult.Recommendation] = []

        // Category groups that often overlap
        let overlapGroups: [String: [String]] = [
            "Music Streaming": ["spotify", "apple music", "youtube music", "tidal", "deezer", "amazon music"],
            "Video Streaming": ["netflix", "hulu", "disney+", "disney plus", "hbo", "paramount+", "peacock",
                                "apple tv", "prime video", "amazon prime"],
            "Cloud Storage": ["icloud", "google one", "dropbox", "onedrive"],
            "News": ["nyt", "new york times", "wsj", "wall street journal", "washington post", "apple news"],
            "Fitness": ["peloton", "fitbit", "strava", "nike run", "myfitnesspal"]
        ]

        for (groupName, keywords) in overlapGroups {
            let matching = subs.filter { sub in
                keywords.contains { sub.merchantName.lowercased().contains($0) }
            }
            if matching.count > 1 {
                // Keep the cheapest, recommend canceling others
                let sorted = matching.sorted { $0.monthlyCost < $1.monthlyCost }
                for sub in sorted.dropFirst() {
                    recs.append(.init(
                        type: .overlap,
                        subscriptionName: sub.merchantName,
                        reason: "Overlaps with other \(groupName) services",
                        potentialSaving: sub.monthlyCost,
                        confidence: 0.7
                    ))
                }
            }
        }

        return recs
    }

    /// Detect high-cost subscriptions (>25% of total).
    private func detectHighCost(_ subs: [DetectedSubscription], totalMonthly: Int) -> [SubscriptionOptimizationResult.Recommendation] {
        guard totalMonthly > 0 else { return [] }
        var recs: [SubscriptionOptimizationResult.Recommendation] = []

        for sub in subs {
            let share = Double(sub.monthlyCost) / Double(totalMonthly)
            if share > 0.25 && subs.count > 2 {
                recs.append(.init(
                    type: .downgrade,
                    subscriptionName: sub.merchantName,
                    reason: "Takes \(Int(share * 100))% of your subscription budget — consider a cheaper plan",
                    potentialSaving: sub.monthlyCost / 3, // Assume 1/3 saving from downgrade
                    confidence: 0.5
                ))
            }
        }

        return recs
    }

    /// Detect subscriptions that might be unused (>6 months old, could review).
    private func detectPotentiallyUnused(_ subs: [DetectedSubscription]) -> [SubscriptionOptimizationResult.Recommendation] {
        var recs: [SubscriptionOptimizationResult.Recommendation] = []

        for sub in subs {
            if sub.createdAt < Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date() {
                // Old subscription — suggest review
                recs.append(.init(
                    type: .cancel,
                    subscriptionName: sub.merchantName,
                    reason: "Active for 6+ months — worth reviewing if still needed",
                    potentialSaving: sub.monthlyCost,
                    confidence: 0.3
                ))
            }
        }

        return recs
    }

    /// Suggest free alternatives for known paid services.
    private func suggestFreeAlternatives(_ subs: [DetectedSubscription]) -> [SubscriptionOptimizationResult.Recommendation] {
        var recs: [SubscriptionOptimizationResult.Recommendation] = []

        let freeAlts: [String: String] = [
            "lastpass": "Bitwarden (free)",
            "1password": "Bitwarden (free)",
            "grammarly": "LanguageTool (free tier)",
            "canva": "Canva has a generous free tier",
            "zoom": "Google Meet (free)",
            "slack": "Discord (free)"
        ]

        for sub in subs {
            let lower = sub.merchantName.lowercased()
            for (keyword, alternative) in freeAlts {
                if lower.contains(keyword) {
                    recs.append(.init(
                        type: .freeAlternative,
                        subscriptionName: sub.merchantName,
                        reason: "Consider \(alternative)",
                        potentialSaving: sub.monthlyCost,
                        confidence: 0.4
                    ))
                }
            }
        }

        return recs
    }
}
