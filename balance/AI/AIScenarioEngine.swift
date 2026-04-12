import Foundation
import Combine

// ============================================================
// MARK: - AI Scenario Engine
// ============================================================
//
// "What if" simulation engine. Takes hypothetical changes
// and projects their impact on budget, goals, and savings.
//
// Pure math — no LLM needed.
//
// ============================================================

/// A scenario simulation result.
struct ScenarioResult: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let description: String
    let impacts: [Impact]
    let recommendation: String

    struct Impact: Identifiable, Equatable {
        let id = UUID()
        let area: String          // "Budget", "Goal: Vacation", etc.
        let currentValue: String
        let projectedValue: String
        let isPositive: Bool
    }
}

@MainActor
class AIScenarioEngine: ObservableObject {
    static let shared = AIScenarioEngine()

    @Published var lastResult: ScenarioResult?

    private init() {}

    // MARK: - Scenarios

    /// "What if I save X more per month?"
    func simulateSaveMore(amount: Int, store: Store) -> ScenarioResult {
        let month = Date()
        let monthKey = Store.monthKey(month)
        let budget = store.budgetsByMonth[monthKey] ?? 0
        let spent = store.spent(for: month)
        let remaining = max(0, budget - spent)

        var impacts: [ScenarioResult.Impact] = []

        // Budget impact
        if budget > 0 {
            let newRemaining = remaining - amount
            impacts.append(ScenarioResult.Impact(
                area: "Monthly Budget",
                currentValue: "\(fmt(remaining)) remaining",
                projectedValue: "\(fmt(newRemaining)) remaining",
                isPositive: newRemaining >= 0
            ))
        }

        // Goal impact — how much faster goals complete
        let goals = GoalManager.shared.goals.filter { !$0.isCompleted }
        for goal in goals {
            let leftToSave = goal.targetAmount - goal.currentAmount
            guard leftToSave > 0 else { continue }

            let currentMonthly = goal.requiredMonthlySaving ?? leftToSave
            let newMonthly = currentMonthly + amount

            let currentMonths = currentMonthly > 0 ? leftToSave / currentMonthly : 999
            let newMonths = newMonthly > 0 ? leftToSave / newMonthly : 999

            if newMonths < currentMonths {
                impacts.append(ScenarioResult.Impact(
                    area: "Goal: \(goal.name)",
                    currentValue: "\(currentMonths) months to complete",
                    projectedValue: "\(newMonths) months to complete",
                    isPositive: true
                ))
            }
        }

        // Yearly savings impact
        let yearlySavings = amount * 12
        impacts.append(ScenarioResult.Impact(
            area: "Annual Savings",
            currentValue: "Current pace",
            projectedValue: "+\(fmt(yearlySavings))/year extra",
            isPositive: true
        ))

        let recommendation: String
        if budget > 0 && remaining - amount < 0 {
            recommendation = "This would exceed your current budget. Consider increasing your budget or finding areas to cut."
        } else if !goals.isEmpty {
            let fastestGoal = goals.min(by: { ($0.targetAmount - $0.currentAmount) < ($1.targetAmount - $1.currentAmount) })
            recommendation = "Great plan! This would help you reach \"\(fastestGoal?.name ?? "your goal")\" faster."
        } else {
            recommendation = "Saving \(fmt(amount)) more monthly adds up to \(fmt(yearlySavings)) per year. Consider creating a savings goal!"
        }

        let result = ScenarioResult(
            title: "Save \(fmt(amount)) More",
            description: "Impact of saving an additional \(fmt(amount)) per month",
            impacts: impacts,
            recommendation: recommendation
        )
        lastResult = result
        return result
    }

    /// "What if I cut spending on X category by Y%?"
    func simulateCutCategory(category: String, percentCut: Int, store: Store) -> ScenarioResult {
        let month = Date()
        let expenses = store.transactions.filter {
            $0.type == .expense &&
            $0.category.title.lowercased() == category.lowercased() &&
            Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
        }
        let currentSpend = expenses.reduce(0) { $0 + $1.amount }
        let savings = currentSpend * percentCut / 100
        let newSpend = currentSpend - savings

        var impacts: [ScenarioResult.Impact] = []

        impacts.append(ScenarioResult.Impact(
            area: "\(category) Spending",
            currentValue: fmt(currentSpend),
            projectedValue: fmt(newSpend),
            isPositive: true
        ))

        // Budget impact
        let monthKey = Store.monthKey(month)
        let budget = store.budgetsByMonth[monthKey] ?? 0
        if budget > 0 {
            let spent = store.spent(for: month)
            let newSpent = spent - savings
            impacts.append(ScenarioResult.Impact(
                area: "Total Budget Used",
                currentValue: "\(Int(Double(spent) / Double(budget) * 100))%",
                projectedValue: "\(Int(Double(newSpent) / Double(budget) * 100))%",
                isPositive: true
            ))
        }

        // Yearly projection
        impacts.append(ScenarioResult.Impact(
            area: "Annual Savings",
            currentValue: "Current pace",
            projectedValue: "+\(fmt(savings * 12))/year",
            isPositive: true
        ))

        let result = ScenarioResult(
            title: "Cut \(category) by \(percentCut)%",
            description: "Impact of reducing \(category) spending by \(percentCut)%",
            impacts: impacts,
            recommendation: "Cutting \(category) by \(percentCut)% saves \(fmt(savings))/month. That's \(fmt(savings * 12)) per year."
        )
        lastResult = result
        return result
    }

    /// "What if I increase my budget to X?"
    func simulateBudgetChange(newBudget: Int, store: Store) -> ScenarioResult {
        let month = Date()
        let monthKey = Store.monthKey(month)
        let currentBudget = store.budgetsByMonth[monthKey] ?? 0
        let spent = store.spent(for: month)

        var impacts: [ScenarioResult.Impact] = []

        impacts.append(ScenarioResult.Impact(
            area: "Monthly Budget",
            currentValue: fmt(currentBudget),
            projectedValue: fmt(newBudget),
            isPositive: newBudget > currentBudget
        ))

        let currentRemaining = max(0, currentBudget - spent)
        let newRemaining = max(0, newBudget - spent)
        impacts.append(ScenarioResult.Impact(
            area: "Remaining This Month",
            currentValue: fmt(currentRemaining),
            projectedValue: fmt(newRemaining),
            isPositive: newRemaining > currentRemaining
        ))

        let diff = newBudget - currentBudget
        let recommendation: String
        if diff > 0 {
            recommendation = "Increasing budget by \(fmt(diff)) gives more breathing room but reduces potential savings."
        } else if diff < 0 {
            recommendation = "Reducing budget by \(fmt(-diff)) is ambitious. Make sure it's realistic based on your spending patterns."
        } else {
            recommendation = "No change from current budget."
        }

        let result = ScenarioResult(
            title: "Budget to \(fmt(newBudget))",
            description: "Impact of changing your monthly budget",
            impacts: impacts,
            recommendation: recommendation
        )
        lastResult = result
        return result
    }

    private func fmt(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100.0)
    }
}
