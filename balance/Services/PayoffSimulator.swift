import Foundation

// ============================================================
// MARK: - Payoff Simulator (Phase 4a — iOS port)
// ============================================================
//
// Project liability payoff under three strategies:
//   .minimum   — pay only the minimum every month
//   .snowball  — minimum on all, attack the smallest balance first
//   .avalanche — minimum on all, attack the highest APR first
//
// Pure value-type math — no Store, no SwiftUI. Returns a `PayoffPlan`
// with a month-by-month timeline, final payoff date, and total
// interest paid.
//
// "Extra monthly" is the additional pool the user is willing to
// throw at debt above each card's minimum. Snowball and avalanche
// split that pool by their priority rules; minimum-only ignores it.
//
// Ported from macOS Centmond. Adapted to iOS Account shape:
//   - `Account.currentBalance: Double` (not Decimal)
//   - `Account.interestRate: Double?` (not `interestRatePercent`)
//   - iOS has no `minimumPaymentMonthly` → always fall back to
//     2% of balance with a $25 floor
// ============================================================

enum PayoffStrategy: String, CaseIterable, Identifiable {
    case minimum, snowball, avalanche
    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimum:   return "Minimum only"
        case .snowball:  return "Snowball"
        case .avalanche: return "Avalanche"
        }
    }

    var blurb: String {
        switch self {
        case .minimum:   return "Just the minimum every month — slowest, most interest."
        case .snowball:  return "Knock out the smallest balance first for momentum."
        case .avalanche: return "Attack the highest APR first — saves the most interest."
        }
    }
}

struct PayoffPlan {
    let strategy: PayoffStrategy
    let months: Int
    let totalPaid: Double
    let totalInterest: Double
    let payoffDate: Date?            // nil if the cap was hit before zero
    let timeline: [Double]           // remaining total balance per month, index 0 = now
    let didFinish: Bool
}

enum PayoffSimulator {

    /// Hard cap so a borderline-impossible scenario (interest > payment)
    /// doesn't loop forever. 50 years beyond any realistic horizon.
    private static let maxMonths = 600

    /// Default minimum payment when an account has none configured:
    /// 2% of balance, floored at $25. Matches typical US card-issuer math.
    private static let fallbackMinPercent: Double = 0.02
    private static let fallbackMinFloor: Double = 25

    static func simulate(
        accounts: [Account],
        strategy: PayoffStrategy,
        extraMonthly: Double = 0
    ) -> PayoffPlan {
        var debts = accounts
            .filter { $0.type.isLiability && abs($0.currentBalance) > 0 }
            .map { Debt(account: $0) }

        guard !debts.isEmpty else {
            return PayoffPlan(
                strategy: strategy,
                months: 0, totalPaid: 0, totalInterest: 0,
                payoffDate: Date(), timeline: [], didFinish: true
            )
        }

        var month = 0
        var totalPaid: Double = 0
        var totalInterest: Double = 0
        var timeline: [Double] = [debts.reduce(0) { $0 + $1.balance }]

        while debts.contains(where: { $0.balance > 0 }) && month < maxMonths {
            month += 1

            // 1. Accrue interest on every active debt.
            for i in debts.indices where debts[i].balance > 0 {
                let monthlyRate = debts[i].apr / 12
                let interest = debts[i].balance * monthlyRate
                debts[i].balance += interest
                totalInterest += interest
            }

            // 2. Pay the minimum on every active debt.
            var pool = extraMonthly
            for i in debts.indices where debts[i].balance > 0 {
                let pay = min(debts[i].minPayment, debts[i].balance)
                debts[i].balance -= pay
                totalPaid += pay
            }

            // 3. Apply the extra pool by strategy priority.
            if pool > 0 && strategy != .minimum {
                let order = priorityOrder(debts: debts, strategy: strategy)
                for idx in order where pool > 0 {
                    let extra = min(pool, debts[idx].balance)
                    debts[idx].balance -= extra
                    pool -= extra
                    totalPaid += extra
                }
            }

            timeline.append(debts.reduce(0) { $0 + max($1.balance, 0) })
        }

        let cleared = !debts.contains(where: { $0.balance > 0.01 })
        let payoffDate = cleared
            ? Calendar.current.date(byAdding: .month, value: month, to: Date())
            : nil

        return PayoffPlan(
            strategy: strategy,
            months: month,
            totalPaid: totalPaid,
            totalInterest: totalInterest,
            payoffDate: payoffDate,
            timeline: timeline,
            didFinish: cleared
        )
    }

    // MARK: - Priority

    private static func priorityOrder(debts: [Debt], strategy: PayoffStrategy) -> [Int] {
        let active = debts.enumerated().filter { $0.element.balance > 0 }
        switch strategy {
        case .minimum:
            return []
        case .snowball:
            return active
                .sorted { $0.element.balance < $1.element.balance }
                .map(\.offset)
        case .avalanche:
            // Highest APR first; tiebreak on largest balance so a 0% APR card
            // never takes priority over another 0% card with a smaller balance.
            return active
                .sorted {
                    if $0.element.apr == $1.element.apr {
                        return $0.element.balance > $1.element.balance
                    }
                    return $0.element.apr > $1.element.apr
                }
                .map(\.offset)
        }
    }

    // MARK: - Internal debt struct

    private struct Debt {
        var balance: Double
        let apr: Double          // annual rate as fraction (0.1999 = 19.99%)
        let minPayment: Double

        init(account: Account) {
            let bal = abs(account.currentBalance)
            self.balance = bal
            // iOS's Account.interestRate stores percent, not a 0-1 fraction.
            self.apr = (account.interestRate ?? 0) / 100
            let pct = bal * fallbackMinPercent
            self.minPayment = max(pct, fallbackMinFloor)
        }
    }
}
