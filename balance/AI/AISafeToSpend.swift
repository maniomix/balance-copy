import Foundation
import Combine

// ============================================================
// MARK: - AI Safe-to-Spend Engine
// ============================================================
//
// Phase 7 deliverable: calculates how much the user can safely
// spend today/this week without exceeding their budget or
// jeopardizing their goals.
//
// Pure math — no LLM needed. Used by:
//   - System prompt context (gives AI accurate safe-to-spend data)
//   - Dashboard widgets
//   - Proactive alerts
//
// ============================================================

struct SafeToSpendResult {
    let dailyAllowance: Int        // cents — what you can spend today
    let weeklyAllowance: Int       // cents — what you can spend this week
    let remainingBudget: Int       // cents — total remaining for the month
    let daysLeftInMonth: Int
    let burnRate: Double           // avg daily spend this month so far
    let projectedMonthEnd: Int     // cents — projected total spend at current pace
    let isOnTrack: Bool            // true if projected spend ≤ budget
    let survivalDays: Int          // days until budget runs out at current pace
    let goalReserve: Int           // cents — amount reserved for active goal contributions
    let trueAllowance: Int         // dailyAllowance minus daily goal reserve

    /// Formatted summary for AI context or display.
    func summary(currency: String = "$") -> String {
        var lines: [String] = []
        lines.append("Safe to spend today: \(format(trueAllowance, currency))")
        lines.append("This week: \(format(weeklyAllowance, currency))")
        lines.append("Budget remaining: \(format(remainingBudget, currency)) (\(daysLeftInMonth) days left)")
        lines.append("Daily burn rate: \(format(Int(burnRate), currency))/day")

        if !isOnTrack {
            lines.append("⚠️ At current pace, you'll overspend by \(format(projectedMonthEnd - (remainingBudget + spent()), currency))")
        }
        if survivalDays < daysLeftInMonth {
            lines.append("⚠️ Budget runs out in ~\(survivalDays) days")
        }
        if goalReserve > 0 {
            lines.append("Goal savings reserved: \(format(goalReserve, currency))/month")
        }
        return lines.joined(separator: "\n")
    }

    private func spent() -> Int { 0 } // placeholder, actual spent is external

    private func format(_ cents: Int, _ currency: String) -> String {
        let val = Double(max(0, cents)) / 100.0
        return String(format: "\(currency)%.2f", val)
    }
}

@MainActor
class AISafeToSpend {
    static let shared = AISafeToSpend()

    private init() {}

    /// Calculate safe-to-spend based on current financial state.
    func calculate(store: Store) -> SafeToSpendResult {
        let now = Date()
        let cal = Calendar.current

        // Month boundaries
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let daysElapsed = max(1, cal.dateComponents([.day], from: monthStart, to: now).day ?? 1)
        let monthRange = cal.range(of: .day, in: .month, for: now)!
        let totalDaysInMonth = monthRange.count
        let daysLeft = max(1, totalDaysInMonth - daysElapsed)

        // Budget & spending
        let monthKey = monthKeyFor(now)
        let budget = store.budgetsByMonth[monthKey] ?? 0
        let spent = store.spent(for: now)
        let remaining = max(0, budget - spent)

        // Burn rate (daily average so far)
        let burnRate = Double(spent) / Double(daysElapsed)

        // Projected month-end spend
        let projectedTotal = Int(burnRate * Double(totalDaysInMonth))
        let isOnTrack = budget > 0 ? projectedTotal <= budget : true

        // Survival days
        let survivalDays: Int
        if burnRate > 0 {
            survivalDays = Int(Double(remaining) / burnRate)
        } else {
            survivalDays = daysLeft
        }

        // Goal reserves — estimate monthly contribution needed
        let goalReserve = calculateGoalReserve()

        // Daily and weekly allowances
        let dailyAllowance = daysLeft > 0 ? remaining / daysLeft : remaining
        let weeklyAllowance = min(remaining, dailyAllowance * min(7, daysLeft))

        // True allowance = daily budget minus daily goal reserve
        let dailyGoalReserve = goalReserve / max(1, totalDaysInMonth)
        let trueAllowance = max(0, dailyAllowance - dailyGoalReserve)

        return SafeToSpendResult(
            dailyAllowance: dailyAllowance,
            weeklyAllowance: weeklyAllowance,
            remainingBudget: remaining,
            daysLeftInMonth: daysLeft,
            burnRate: burnRate,
            projectedMonthEnd: projectedTotal,
            isOnTrack: isOnTrack,
            survivalDays: survivalDays,
            goalReserve: goalReserve,
            trueAllowance: trueAllowance
        )
    }

    /// Affordability check: can the user afford a specific purchase?
    func canAfford(amount: Int, store: Store) -> AffordabilityResult {
        let sts = calculate(store: store)
        let remaining = sts.remainingBudget

        if amount <= sts.trueAllowance {
            return AffordabilityResult(
                canAfford: true,
                impact: .minimal,
                message: "Yes, that's within your daily allowance.",
                remainingAfter: remaining - amount
            )
        } else if amount <= remaining {
            let daysOfBudget = sts.burnRate > 0 ? Int(Double(amount) / sts.burnRate) : 0
            return AffordabilityResult(
                canAfford: true,
                impact: .moderate,
                message: "You can afford it, but it uses ~\(daysOfBudget) days of budget.",
                remainingAfter: remaining - amount
            )
        } else {
            let shortfall = amount - remaining
            return AffordabilityResult(
                canAfford: false,
                impact: .severe,
                message: "That would put you \(formatCents(shortfall)) over budget.",
                remainingAfter: remaining - amount
            )
        }
    }

    // MARK: - Helpers

    private func calculateGoalReserve() -> Int {
        let goals = GoalManager.shared.goals.filter { !$0.isCompleted }
        var monthlyReserve = 0
        for goal in goals {
            if let monthly = goal.requiredMonthlySaving {
                monthlyReserve += monthly
            }
        }
        return monthlyReserve
    }

    private func monthKeyFor(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }

    private func formatCents(_ cents: Int) -> String {
        String(format: "$%.2f", Double(abs(cents)) / 100.0)
    }
}

struct AffordabilityResult {
    let canAfford: Bool
    let impact: Impact
    let message: String
    let remainingAfter: Int  // can be negative

    enum Impact {
        case minimal   // Within daily allowance
        case moderate  // Within budget but significant
        case severe    // Exceeds budget
    }
}
