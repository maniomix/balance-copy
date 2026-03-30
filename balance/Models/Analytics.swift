import SwiftUI

// MARK: - Analytics

struct Insight: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
    let level: Level
}

enum Analytics {

    struct MonthSummary {
        let budgetCents: Int
        let totalSpent: Int
        let remaining: Int
        let dailyAvg: Int
        let spentRatio: Double
    }

    struct Pressure {
        let title: String
        let detail: String
        let level: Level
    }

    struct Projection {
        let projectedTotal: Int
        let deltaAbs: Int
        let statusText: String
        let level: Level
    }

    struct DayPoint: Identifiable {
        let id = UUID()
        let day: Int
        let amount: Int
    }

    struct CategoryRow: Identifiable {
        let id = UUID()
        let category: Category
        let total: Int
    }

    struct PaymentBreakdown: Identifiable {
        let id = UUID()
        let method: PaymentMethod
        let total: Int
        let percentage: Double
    }

    struct DayGroup {
        let day: Date
        let title: String
        let items: [Transaction]
    }
}

struct ConsecutiveDayGroup: Identifiable {
    let id: String
    let day: Date
    let title: String
    let items: [Transaction]
}

extension Analytics {

    static func monthTransactions(store: Store) -> [Transaction] {
        let cal = Calendar.current
        return store.transactions
            .filter { cal.isDate($0.date, equalTo: store.selectedMonth, toGranularity: .month) }
            .sorted { $0.date > $1.date }
    }

    static func monthSummary(store: Store) -> MonthSummary {
        let tx = monthTransactions(store: store)

        let totalSpent = tx.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let totalIncome = tx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let remaining = store.budgetTotal + totalIncome - totalSpent

        let cal = Calendar.current
        let range = cal.range(of: .day, in: .month, for: store.selectedMonth) ?? 1..<31
        let daysInMonth = range.count
        let dayNow = cal.component(.day, from: Date())
        let isCurrentMonth = cal.isDate(Date(), equalTo: store.selectedMonth, toGranularity: .month)
        let divisor = max(1, isCurrentMonth ? min(dayNow, daysInMonth) : daysInMonth)
        let dailyAvg = totalSpent / divisor

        let ratio = store.budgetTotal > 0 ? Double(totalSpent) / Double(store.budgetTotal) : 0
        return .init(budgetCents: store.budgetTotal, totalSpent: totalSpent, remaining: remaining, dailyAvg: dailyAvg, spentRatio: ratio)
    }

    static func budgetPressure(store: Store) -> Pressure {
        let s = monthSummary(store: store)
        if s.spentRatio < 0.75 {
            return .init(title: "On Track",
                        detail: "Spending is on track", level: .ok)
        } else if s.spentRatio < 0.95 {
            return .init(title: "Needs Attention",
                        detail: "Budget pressure building", level: .watch)
        } else {
            return .init(title: "Budget Pressure",
                        detail: "Approaching or exceeded budget", level: .risk)
        }
    }

    /// Returns a status line if any category cap is near/over for the selected month.
    static func categoryCapPressure(store: Store) -> Pressure? {
        let tx = monthTransactions(store: store)
        guard !tx.isEmpty else { return nil }

        var bestWatch: Pressure? = nil

        for c in store.allCategories {
            let cap = store.categoryBudget(for: c)
            guard cap > 0 else { continue }

            let spent = tx.filter { $0.category == c }.reduce(0) { $0 + $1.amount }
            guard spent > 0 else { continue }

            if spent > cap {
                let over = spent - cap
                return .init(
                    title: "Over cap: \(c.title)",
                    detail: "You're \(DS.Format.money(over)) above your \(DS.Format.money(cap)) cap.",
                    level: .risk
                )
            }

            let ratio = Double(spent) / Double(max(1, cap))
            if ratio >= 0.9 {
                bestWatch = .init(
                    title: "Near cap: \(c.title)",
                    detail: "Used \(DS.Format.percent(ratio)) of your \(DS.Format.money(cap)) cap.",
                    level: .watch
                )
            }
        }

        return bestWatch
    }

    static func projectedEndOfMonth(store: Store) -> Projection {
        let summary = monthSummary(store: store)
        guard store.budgetTotal > 0 else {
            return Projection(projectedTotal: summary.totalSpent, deltaAbs: 0, statusText: "Budget not set", level: .watch)
        }

        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: store.selectedMonth) ?? 1..<31
        let daysInMonth = range.count

        let isCurrentMonth = calendar.isDate(Date(), equalTo: store.selectedMonth, toGranularity: .month)
        let dayNow = calendar.component(.day, from: Date())
        let elapsed = max(1, isCurrentMonth ? min(dayNow, daysInMonth) : daysInMonth)

        let tx = monthTransactions(store: store)
        var byDay: [Int: Int] = [:]
        for t in tx {
            let d = calendar.component(.day, from: t.date)
            byDay[d, default: 0] += t.amount
        }

        let dailyTotals: [Int] = (1...elapsed).map { byDay[$0] ?? 0 }

        func winsorizedMean(_ xs: [Int]) -> Double {
            guard !xs.isEmpty else { return 0 }
            if xs.count < 5 {
                let sum = xs.reduce(0, +)
                return Double(sum) / Double(max(1, xs.count))
            }

            let s = xs.sorted()
            let n = s.count
            let lowIdx = Int(Double(n) * 0.10)
            let highIdx = max(lowIdx, Int(Double(n) * 0.90) - 1)

            let low = s[min(max(0, lowIdx), n - 1)]
            let high = s[min(max(0, highIdx), n - 1)]

            let clampedSum = xs.reduce(0) { (acc: Int, v: Int) -> Int in
                let clampedValue = min(max(v, low), high)
                return acc + clampedValue
            }
            return Double(clampedSum) / Double(n)
        }

        let robustDailyAvg = winsorizedMean(dailyTotals)
        let projected = Int((robustDailyAvg * Double(daysInMonth)).rounded())

        let delta = projected - store.budgetTotal

        if delta <= 0 {
            return Projection(projectedTotal: projected, deltaAbs: abs(delta), statusText: "Below monthly budget", level: .ok)
        } else if delta < store.budgetTotal / 10 {
            return Projection(projectedTotal: projected, deltaAbs: delta, statusText: "Close to budget limit", level: .watch)
        } else {
            return Projection(projectedTotal: projected, deltaAbs: delta, statusText: "Likely to exceed budget", level: .risk)
        }
    }

    static func dailySpendPoints(store: Store) -> [DayPoint] {
        let tx = monthTransactions(store: store).filter { $0.type == .expense }
        guard !tx.isEmpty else { return [] }

        let cal = Calendar.current
        var byDay: [Int: Int] = [:]
        for t in tx {
            let d = cal.component(.day, from: t.date)
            byDay[d, default: 0] += t.amount
        }
        return byDay.keys.sorted().map { DayPoint(day: $0, amount: byDay[$0] ?? 0) }
    }

    static func dailyIncomePoints(store: Store) -> [DayPoint] {
        let tx = monthTransactions(store: store).filter { $0.type == .income }
        guard !tx.isEmpty else { return [] }

        let cal = Calendar.current
        var byDay: [Int: Int] = [:]
        for t in tx {
            let d = cal.component(.day, from: t.date)
            byDay[d, default: 0] += t.amount
        }
        return byDay.keys.sorted().map { DayPoint(day: $0, amount: byDay[$0] ?? 0) }
    }

    static func categoryBreakdown(store: Store) -> [CategoryRow] {
        let tx = monthTransactions(store: store)
        guard !tx.isEmpty else { return [] }

        var map: [Category: Int] = [:]
        for t in tx { map[t.category, default: 0] += t.amount }

        return map
            .map { CategoryRow(category: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    static func paymentBreakdown(store: Store) -> [PaymentBreakdown] {
        let tx = monthTransactions(store: store)
        guard !tx.isEmpty else { return [] }

        var map: [PaymentMethod: Int] = [:]
        for t in tx { map[t.paymentMethod, default: 0] += t.amount }

        let total = map.values.reduce(0, +)

        return map
            .map { PaymentBreakdown(
                method: $0.key,
                total: $0.value,
                percentage: total > 0 ? Double($0.value) / Double(total) : 0
            )}
            .sorted { $0.total > $1.total }
    }

    static func groupedByDay(_ tx: [Transaction], ascending: Bool = false) -> [DayGroup] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: tx) { cal.startOfDay(for: $0.date) }

        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.setLocalizedDateFormatFromTemplate("EEEE, MMM d")

        return groups
            .map { (day, items) in
                let sorted = ascending
                    ? items.sorted { $0.date < $1.date }
                    : items.sorted { $0.date > $1.date }
                return DayGroup(day: day, title: fmt.string(from: day), items: sorted)
            }
            .sorted { ascending ? $0.day < $1.day : $0.day > $1.day }
    }

    static func generateInsights(store: Store) -> [Insight] {
        let tx = monthTransactions(store: store)
        guard !tx.isEmpty else { return [] }

        var out: [Insight] = []

        if tx.count >= 5 {
            let proj = projectedEndOfMonth(store: store)
            if proj.level != .ok {
                let title = proj.level == .risk ? "This trend will pressure your budget" : "Approaching the limit"
                let detail = proj.level == .risk
                    ? "End-of-month projection is above budget. Prioritize cutting discretionary costs."
                    : "To stay in control, trim one discretionary category slightly."
                out.append(.init(title: title, detail: detail, level: proj.level))
            } else {
                out.append(.init(title: "Good control", detail: "Current trend aligns with your Main budget. Keep it steady.", level: .ok))
            }

            let breakdown = categoryBreakdown(store: store)
            if let top = breakdown.first {
                let total = breakdown.reduce(0) { $0 + $1.total }
                let share = total > 0 ? Double(top.total) / Double(total) : 0
                if share > 0.35 {
                    out.append(.init(
                        title: "Spending concentrated in \"\(top.category.title)\"",
                        detail: "This category is \(DS.Format.percent(share)) of monthly spending. If reducible, start here.",
                        level: .watch
                    ))
                }
            }
        }

        // Category budget caps
        for c in store.allCategories {
            let cap = store.categoryBudget(for: c)
            guard cap > 0 else { continue }

            let spent = tx.filter { $0.category == c }.reduce(0) { $0 + $1.amount }

            if spent > cap {
                let over = spent - cap
                out.append(.init(
                    title: "Over budget in \"\(c.title)\"",
                    detail: "You're \(DS.Format.money(over)) above your \(DS.Format.money(cap)) cap for this category.",
                    level: .risk
                ))
            } else {
                let ratio = Double(spent) / Double(max(1, cap))
                if ratio >= 0.9 {
                    out.append(.init(
                        title: "Near the cap in \"\(c.title)\"",
                        detail: "You've used \(DS.Format.percent(ratio)) of your \(DS.Format.money(cap)) cap.",
                        level: .watch
                    ))
                }
            }
        }

        if tx.count >= 5 {
            let smallThreshold = max(80_000, store.budgetTotal / 500)
            let smalls = tx.filter { $0.amount <= smallThreshold }
            if smalls.count >= 8 {
                let sum = smalls.reduce(0) { $0 + $1.amount }
                out.append(.init(
                    title: "Small expenses are adding up",
                    detail: "You have \(smalls.count) small transactions totaling \(DS.Format.money(sum)). Set a daily cap for small spending.",
                    level: .watch
                ))
            }

            let dining = tx.filter { $0.category == .dining }.reduce(0) { $0 + $1.amount }
            let ent = tx.filter { $0.category == .other }.reduce(0) { $0 + $1.amount }
            let total = tx.reduce(0) { $0 + $1.amount }
            if total > 0 {
                let opt = dining + ent
                let share = Double(opt) / Double(total)
                if share > 0.22 {
                    out.append(.init(
                        title: "Discretionary costs can be reduced",
                        detail: "Dining + Entertainment is \(DS.Format.percent(share)) of spending. A 10% cut noticeably reduces pressure.",
                        level: .watch
                    ))
                }
            }

            let s = monthSummary(store: store)
            if s.remaining < 0 {
                out.append(.init(
                    title: "Over budget",
                    detail: "You're above the monthly budget. Firm move: pause non\u{2011}essential spending until month end.",
                    level: .risk
                ))
            }
        }

        return out.sorted { rank($0.level) > rank($1.level) }
    }

    static func quickActions(store: Store) -> [String] {
        let tx = monthTransactions(store: store)
        guard !tx.isEmpty else { return [] }

        var actions: [String] = []
        for c in store.allCategories {
            let cap = store.categoryBudget(for: c)
            guard cap > 0 else { continue }

            let spent = tx.filter { $0.category == c }.reduce(0) { $0 + $1.amount }
            if spent > cap {
                actions.append("Pause spending in \"\(c.title)\" for the rest of the month or reduce it sharply.")
                break
            }

            let ratio = Double(spent) / Double(max(1, cap))
            if ratio >= 0.9 {
                actions.append("You're close to the \"\(c.title)\" cap—set a mini-cap for the next 7 days.")
                break
            }
        }

        if tx.count >= 5 {
            let proj = projectedEndOfMonth(store: store)

            if proj.level == .risk {
                actions.append("Set a daily spending cap for the next 7 days.")
                actions.append("Temporarily limit one discretionary category (Dining / Entertainment / Shopping).")
            }

            if let top = categoryBreakdown(store: store).first {
                actions.append("Set a weekly cap for \"\(top.category.title)\".")
            }
        }

        return Array(actions.prefix(3))
    }

    private static func rank(_ l: Level) -> Int { l == .risk ? 3 : (l == .watch ? 2 : 1) }
}
