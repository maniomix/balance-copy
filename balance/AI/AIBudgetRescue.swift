import Foundation
import Combine

// ============================================================
// MARK: - AI Budget Rescue Mode
// ============================================================
//
// Activates when the user has used >80% of their monthly budget.
// Provides:
//   • Daily spending limit suggestion
//   • Top spending category alerts
//   • Category-specific reduction targets
//   • Quick actions (reduce category budget, skip non-essentials)
//
// Pure heuristic — no LLM call needed.
//
// ============================================================

/// Rescue analysis result.
struct BudgetRescuePlan: Equatable {
    let isActive: Bool
    let budgetUsedPercent: Int
    let remainingBudget: Int               // cents
    let daysRemaining: Int
    let dailyLimit: Int                    // cents — suggested max per day
    let topCategory: String                // biggest spending category
    let topCategoryAmount: Int             // cents
    let reductionTargets: [ReductionTarget]
    let tips: [String]

    struct ReductionTarget: Equatable, Identifiable {
        let id = UUID()
        let category: String
        let currentSpend: Int              // cents
        let suggestedLimit: Int            // cents
        let savingsIfReduced: Int          // cents
    }
}

@MainActor
class AIBudgetRescue: ObservableObject {
    static let shared = AIBudgetRescue()

    @Published var plan: BudgetRescuePlan?

    /// Threshold to activate rescue mode (80%).
    private let threshold = 0.80

    private init() {}

    /// Evaluate whether rescue mode should activate.
    func evaluate(store: Store) {
        let month = Date()
        let monthKey = Store.monthKey(month)
        let budget = store.budgetsByMonth[monthKey] ?? 0

        guard budget > 0 else {
            plan = nil
            return
        }

        let spent = store.spent(for: month)
        let ratio = Double(spent) / Double(budget)

        guard ratio >= threshold else {
            plan = nil
            return
        }

        let remaining = max(0, budget - spent)
        let dayOfMonth = Calendar.current.component(.day, from: month)
        let daysInMonth = Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 30
        let daysRemaining = max(1, daysInMonth - dayOfMonth)
        let dailyLimit = remaining / daysRemaining

        // Category analysis
        let expenses = store.transactions.filter {
            $0.type == .expense &&
            Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
        }

        var catTotals: [String: Int] = [:]
        for t in expenses {
            catTotals[t.category.title, default: 0] += t.amount
        }

        let sortedCats = catTotals.sorted { $0.value > $1.value }
        let topCategory = sortedCats.first?.key ?? "Unknown"
        let topCategoryAmount = sortedCats.first?.value ?? 0

        // Reduction targets: suggest 20% reduction for top 3 non-essential categories
        let essentialCategories = ["Rent", "Bills", "Health"]
        let reductionTargets = sortedCats
            .filter { !essentialCategories.contains($0.key) }
            .prefix(3)
            .map { cat -> BudgetRescuePlan.ReductionTarget in
                let suggested = Int(Double(cat.value) * 0.8)
                let savings = cat.value - suggested
                return BudgetRescuePlan.ReductionTarget(
                    category: cat.key,
                    currentSpend: cat.value,
                    suggestedLimit: suggested,
                    savingsIfReduced: savings
                )
            }

        // Tips based on situation
        var tips: [String] = []

        if ratio >= 1.0 {
            tips.append("You've exceeded your budget. Focus on essential spending only.")
        } else if ratio >= 0.95 {
            tips.append("Almost at budget limit. Try to limit spending to \(formatCents(dailyLimit))/day.")
        } else {
            tips.append("Budget is \(Int(ratio * 100))% used. You can spend up to \(formatCents(dailyLimit))/day.")
        }

        if let topNonEssential = sortedCats.first(where: { !essentialCategories.contains($0.key) }) {
            tips.append("Your biggest discretionary spend is \(topNonEssential.key) at \(formatCents(topNonEssential.value)).")
        }

        let totalSavings = reductionTargets.reduce(0) { $0 + $1.savingsIfReduced }
        if totalSavings > 0 {
            tips.append("Reducing top categories by 20% could save \(formatCents(totalSavings)).")
        }

        plan = BudgetRescuePlan(
            isActive: true,
            budgetUsedPercent: Int(ratio * 100),
            remainingBudget: remaining,
            daysRemaining: daysRemaining,
            dailyLimit: dailyLimit,
            topCategory: topCategory,
            topCategoryAmount: topCategoryAmount,
            reductionTargets: reductionTargets,
            tips: tips
        )
    }

    private func formatCents(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100.0)
    }
}
