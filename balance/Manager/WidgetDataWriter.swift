import Foundation
import WidgetKit

// ============================================================
// MARK: - Widget Data Writer
// ============================================================
//
// Called from the main app whenever Store changes.
// Computes WidgetSharedData from current app state and writes
// it to the App Group container so widgets can read it.
//
// IMPORTANT: This file must ONLY be in the "balance" (main app) target.
// Do NOT add it to CentmondWidgetExtension.
// ============================================================

@MainActor
enum WidgetDataWriter {

    /// Convert a Goal `colorToken` to a 6-char hex string for the widget.
    /// Mirrors `GoalColorHelper.color(for:)` but without the SwiftUI Color wrapping.
    private static func goalColorHex(_ token: String) -> String {
        switch token {
        case "positive": return "2ECC71"
        case "warning":  return "F39C12"
        case "danger":   return "E74C3C"
        case "accent":   return "338CFF"
        case "subtext":  return "8E8E93"
        case "blue":     return "4A90D9"
        case "purple":   return "8B5CF6"
        case "teal":     return "14B8A6"
        case "pink":     return "EC4899"
        case "indigo":   return "6366F1"
        default:         return "338CFF"
        }
    }

    private static func categoryHex(_ cat: Category) -> String {
        switch cat {
        case .groceries:  return "2ECC71"
        case .rent:       return "3498DB"
        case .bills:      return "F39C12"
        case .transport:  return "9B59B6"
        case .health:     return "E74C3C"
        case .education:  return "1ABC9C"
        case .dining:     return "E91E63"
        case .shopping:   return "FF5722"
        case .other:      return "607D8B"
        case .custom:     return "95A5A6"
        }
    }

    static func update(store: Store) {
        let cal = Calendar.current
        let now = Date()
        let month = store.selectedMonth

        // ── Budget ────────────────────────────────────
        let budgetTotal: Int = store.budgetTotal

        let monthTxns: [Transaction] = store.transactions.filter { txn in
            let sameMonth = cal.isDate(txn.date, equalTo: month, toGranularity: .month)
            let isExp = (txn.type == TransactionType.expense)
            return sameMonth && isExp
        }
        let spentThisMonth: Int = monthTxns.reduce(0) { $0 + $1.amount }
        let remainingBudget: Int = max(0, budgetTotal - spentThisMonth)

        let todayTxns: [Transaction] = monthTxns.filter { cal.isDateInToday($0.date) }
        let spentToday: Int = todayTxns.reduce(0) { $0 + $1.amount }

        let dayOfMonth: Int = cal.component(.day, from: now)
        let daysInMonth: Int = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let daysRemaining: Int = max(1, daysInMonth - dayOfMonth + 1)
        let dailyDivisor: Int = max(1, dayOfMonth)
        let dailyAverage: Int = dayOfMonth > 0 ? spentThisMonth / dailyDivisor : 0

        // ── Safe to Spend ─────────────────────────────
        let forecast: ForecastResult? = ForecastEngine.shared.forecast
        let safeToSpendTotal: Int
        let safeToSpendPerDay: Int
        let reservedForBills: Int
        let reservedForGoals: Int

        if let f = forecast {
            safeToSpendTotal = f.safeToSpend.totalAmount
            safeToSpendPerDay = f.safeToSpend.perDay
            reservedForBills = f.safeToSpend.reservedForBills
            reservedForGoals = f.safeToSpend.reservedForGoals
        } else {
            reservedForBills = 0
            reservedForGoals = 0
            safeToSpendTotal = remainingBudget
            if daysRemaining > 0 {
                safeToSpendPerDay = remainingBudget / daysRemaining
            } else {
                safeToSpendPerDay = 0
            }
        }

        // ── Upcoming Bills ────────────────────────────
        let upcomingBills: [WidgetBill]
        if let f = forecast {
            let billSlice = f.upcomingBills.prefix(5)
            upcomingBills = billSlice.map { bill in
                WidgetBill(
                    name: bill.name,
                    amount: bill.amount,
                    dueDateTimestamp: bill.dueDate.timeIntervalSince1970,
                    categoryName: bill.category.title
                )
            }
        } else {
            upcomingBills = []
        }

        // ── Net Worth ─────────────────────────────────
        let acctMgr = AccountManager.shared
        let netWorth: Int = Int(acctMgr.netWorth * 100)
        let accountCount: Int = acctMgr.accounts.count
        let totalAssets: Int = Int(acctMgr.totalAssets * 100)
        let totalLiabilities: Int = Int(acctMgr.totalLiabilities * 100)

        // ── Risk ──────────────────────────────────────
        let riskLevel: String
        if let f = forecast {
            switch f.riskLevel {
            case .safe: riskLevel = "safe"
            case .caution: riskLevel = "caution"
            case .highRisk: riskLevel = "highRisk"
            }
        } else {
            let ratio: Double = budgetTotal > 0 ? Double(spentThisMonth) / Double(budgetTotal) : 0.0
            if ratio > 0.9 {
                riskLevel = "highRisk"
            } else if ratio > 0.7 {
                riskLevel = "caution"
            } else {
                riskLevel = "safe"
            }
        }

        // ── Income ────────────────────────────────────
        let incomeTxns: [Transaction] = store.transactions.filter { txn in
            let sameMonth = cal.isDate(txn.date, equalTo: month, toGranularity: .month)
            let isInc = (txn.type == TransactionType.income)
            return sameMonth && isInc
        }
        let incomeThisMonth: Int = incomeTxns.reduce(0) { $0 + $1.amount }

        // ── Weekly Spending (last 7 days) ────────────
        var weeklySpending: [Int] = []
        for dayOffset in (0...6).reversed() {
            let targetDay = cal.date(byAdding: .day, value: -dayOffset, to: cal.startOfDay(for: now))!
            let dayTotal = store.transactions.filter { txn in
                cal.isDate(txn.date, inSameDayAs: targetDay) && txn.type == .expense
            }.reduce(0) { $0 + $1.amount }
            weeklySpending.append(dayTotal)
        }

        // ── Top Categories ───────────────────────────
        var categoryTotals: [String: (icon: String, amount: Int, colorHex: String)] = [:]
        for txn in monthTxns {
            let key = txn.category.title
            let hex = Self.categoryHex(txn.category)
            let existing = categoryTotals[key] ?? (icon: txn.category.icon, amount: 0, colorHex: hex)
            categoryTotals[key] = (icon: existing.icon, amount: existing.amount + txn.amount, colorHex: existing.colorHex)
        }
        let topCategories: [WidgetCategory] = categoryTotals
            .sorted { $0.value.amount > $1.value.amount }
            .prefix(5)
            .map { WidgetCategory(name: $0.key, icon: $0.value.icon, amount: $0.value.amount, colorHex: $0.value.colorHex) }

        // ── Top Goals (max 3 by priority) ─────────────
        // Goals Rebuild Phase 9: surface in-memory GoalManager state.
        // If goals haven't been fetched yet, this is empty and any goals
        // widget renders the empty state.
        let goalManager = GoalManager.shared
        let topGoalSlice = goalManager.goalsByPriority.prefix(3)
        let topGoals: [WidgetGoal] = topGoalSlice.map { goal in
            let days: Int?
            if let target = goal.targetDate {
                days = cal.dateComponents([.day], from: now, to: target).day
            } else {
                days = nil
            }
            return WidgetGoal(
                name: goal.name,
                icon: goal.icon,
                currentAmount: goal.currentAmount,
                targetAmount: goal.targetAmount,
                colorHex: goalColorHex(goal.colorToken),
                daysRemaining: days
            )
        }

        // ── Currency Symbol ───────────────────────────
        let currencyCode: String = UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"
        let currencySymbol: String
        switch currencyCode {
        case "EUR": currencySymbol = "\u{20AC}"
        case "USD": currencySymbol = "$"
        case "GBP": currencySymbol = "\u{00A3}"
        case "JPY": currencySymbol = "\u{00A5}"
        case "CAD": currencySymbol = "C$"
        default: currencySymbol = currencyCode
        }

        // ── Build & Write ────────────────────────────
        let shared = WidgetSharedData(
            budgetTotal: budgetTotal,
            spentThisMonth: spentThisMonth,
            remainingBudget: remainingBudget,
            spentToday: spentToday,
            dailyAverage: dailyAverage,
            daysRemainingInMonth: daysRemaining,
            dayOfMonth: dayOfMonth,
            daysInMonth: daysInMonth,
            safeToSpendTotal: safeToSpendTotal,
            safeToSpendPerDay: safeToSpendPerDay,
            reservedForBills: reservedForBills,
            reservedForGoals: reservedForGoals,
            upcomingBills: upcomingBills,
            netWorth: netWorth,
            accountCount: accountCount,
            totalAssets: totalAssets,
            totalLiabilities: totalLiabilities,
            riskLevel: riskLevel,
            incomeThisMonth: incomeThisMonth,
            weeklySpending: weeklySpending,
            topCategories: topCategories,
            topGoals: topGoals.isEmpty ? nil : topGoals,
            currencySymbol: currencySymbol,
            lastUpdated: now
        )

        WidgetDataBridge.write(shared)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
