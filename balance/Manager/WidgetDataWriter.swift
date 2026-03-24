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
            currencySymbol: currencySymbol,
            lastUpdated: now
        )

        WidgetDataBridge.write(shared)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
