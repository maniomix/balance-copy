import Foundation

// ============================================================
// MARK: - AI Insight Detectors (Phase 2 — iOS port)
// ============================================================
//
// Pure heuristic detectors. Each `detect*` function reads from
// the Store (and, for recurring-overdue, Store.recurringTransactions)
// and returns `[AIInsight]`. Detectors never mutate state and never
// make LLM calls — they're re-run on every engine refresh.
//
// Ported from macOS Centmond `InsightDetectors.swift`, adapted to
// the iOS data layer:
//   - Amounts are Int (cents) instead of Decimal
//   - Reads from `Store` (value type + singleton) instead of SwiftData
//   - iOS has no Account.currentBalance wiring, so `cashflowRunway`
//     uses `Store.remaining(for:)` as a proxy
//
// Dedupe-key prefixes (stable across refreshes, used by telemetry):
//   cashflow:runway:*       anomaly:daySpike:*
//   cashflow:incomeDrop:*   anomaly:newMerchant:*
//   recurring:overdue:*     duplicate:txn:*
// ============================================================

@MainActor
enum AIInsightDetectorsPack {

    // MARK: - Public entry point

    /// Run all portable detectors. Callers should merge this with existing
    /// `AIInsightEngine` detectors then dedupe by `dedupeKey`.
    static func all(store: Store) -> [AIInsight] {
        var out: [AIInsight] = []
        out += cashflowRunway(store: store)
        out += incomeDrop(store: store)
        out += recurringOverdue(store: store)
        out += daySpike(store: store)
        out += newLargeMerchant(store: store)
        out += duplicateTransactions(store: store)
        out += AIHouseholdInsightDetectors.all()
        return out
    }

    // MARK: - Cashflow: Runway

    /// Warns when `remaining(for: this month) / daily burn` drops below 14 days.
    /// Uses `Store.remaining` (budget + income − spent) as a proxy for spendable
    /// balance since iOS Store doesn't aggregate account balances.
    static func cashflowRunway(store: Store) -> [AIInsight] {
        let now = Date()
        let remaining = store.remaining(for: now)   // cents
        guard remaining > 0 else { return [] }

        let burn = averageDailySpend(store: store, lookbackDays: 30)
        guard burn > 0 else { return [] }

        let runwayDays = Int(Double(remaining) / burn)

        if runwayDays < 14 {
            return [AIInsight(
                type: .cashflowRisk,
                title: "Low runway — \(runwayDays) days",
                body: "At your recent pace (\(fmt(cents: Int(burn)))/day) your remaining budget covers only \(runwayDays) days.",
                severity: .critical,
                advice: "Pause non-essential spending and defer large charges, or reallocate from savings.",
                cause: "Based on \(fmt(cents: remaining)) remaining this month and 30-day average burn.",
                expiresAt: Calendar.current.date(byAdding: .day, value: 2, to: now),
                dedupeKey: "cashflow:runway:lt14",
                deeplink: .cashflow
            )]
        }
        if runwayDays < 30 {
            return [AIInsight(
                type: .cashflowRisk,
                title: "Runway tight — \(runwayDays) days",
                body: "At your recent pace your remaining budget covers about \(runwayDays) days.",
                severity: .warning,
                advice: "Review upcoming bills and discretionary categories this week.",
                cause: "Based on \(fmt(cents: remaining)) remaining and 30-day average burn.",
                expiresAt: Calendar.current.date(byAdding: .day, value: 3, to: now),
                dedupeKey: "cashflow:runway:lt30",
                deeplink: .cashflow
            )]
        }
        return []
    }

    // MARK: - Cashflow: Income drop

    /// Compares this month's income vs the trailing 3-month average. Only
    /// fires in the second half of the month to avoid false positives when
    /// paychecks haven't landed yet.
    static func incomeDrop(store: Store) -> [AIInsight] {
        let cal = Calendar.current
        let now = Date()
        guard cal.component(.day, from: now) >= 15 else { return [] }

        let thisMonth = store.income(for: now)
        let priors = (1...3).compactMap { offset -> Int? in
            guard let d = cal.date(byAdding: .month, value: -offset, to: now) else { return nil }
            let v = store.income(for: d)
            return v > 0 ? v : nil
        }
        guard priors.count >= 2 else { return [] }

        let priorAvg = priors.reduce(0, +) / priors.count
        guard priorAvg > 0 else { return [] }

        let ratio = Double(thisMonth) / Double(priorAvg)
        guard ratio < 0.7 else { return [] }

        let gap = priorAvg - thisMonth
        let pct = Int((1 - ratio) * 100)
        return [AIInsight(
            type: .cashflowRisk,
            title: "Income down \(pct)% this month",
            body: "You've logged \(fmt(cents: thisMonth)) in income vs a 3-month average of \(fmt(cents: priorAvg)).",
            severity: .warning,
            advice: "Tighten discretionary categories until the paycheck pace recovers, or flag missing income.",
            cause: "Shortfall vs trailing 3-month average: \(fmt(cents: gap)).",
            expiresAt: cal.date(byAdding: .day, value: 7, to: now),
            dedupeKey: "cashflow:incomeDrop:\(yearMonth(now))",
            deeplink: .transactions
        )]
    }

    // MARK: - Recurring: Overdue

    /// Recurring entries whose `nextOccurrence()` is in the past by more than
    /// 3 days. Signals a missed rent / utility bill or an outdated schedule.
    static func recurringOverdue(store: Store) -> [AIInsight] {
        let now = Date()
        let cal = Calendar.current
        var out: [AIInsight] = []

        for rec in store.recurringTransactions where rec.isActive {
            guard let next = rec.nextOccurrence(from: now) else { continue }
            guard next < now else { continue }
            let daysOverdue = cal.dateComponents([.day], from: next, to: now).day ?? 0
            guard daysOverdue > 3 else { continue }

            out.append(AIInsight(
                type: .recurringDetected,
                title: "\(rec.name) overdue by \(daysOverdue) days",
                body: "Scheduled \(fmt(cents: rec.amount)) hasn't been logged since \(fmtDate(next)).",
                severity: daysOverdue > 7 ? .warning : .info,
                advice: "Confirm the charge landed or adjust the schedule if the date shifted.",
                cause: "Expected \(rec.frequency.rawValue) charge due \(fmtDate(next)).",
                expiresAt: cal.date(byAdding: .day, value: 5, to: now),
                dedupeKey: "recurring:overdue:\(rec.id.uuidString)",
                deeplink: .recurring
            ))
        }
        return out
    }

    // MARK: - Anomaly: Day spike

    /// Flags today's spend if it exceeds 2× the 30-day average day. Uses
    /// same-day-of-week if enough samples exist, else straight daily average.
    static func daySpike(store: Store) -> [AIInsight] {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)

        let todayTotal = store.transactions
            .filter { $0.type == .expense && cal.isDate($0.date, inSameDayAs: todayStart) }
            .reduce(0) { $0 + $1.amount }
        guard todayTotal > 0 else { return [] }

        guard let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: todayStart) else { return [] }
        let recent = store.transactions.filter {
            $0.type == .expense && $0.date >= thirtyDaysAgo && $0.date < todayStart
        }
        guard recent.count >= 10 else { return [] }

        let totalRecent = recent.reduce(0) { $0 + $1.amount }
        let avgPerDay = totalRecent / 30
        guard avgPerDay > 0 else { return [] }

        let ratio = Double(todayTotal) / Double(avgPerDay)
        guard ratio >= 2.0 else { return [] }

        return [AIInsight(
            type: .spendingAnomaly,
            title: "Today is \(Int(ratio))× a normal day",
            body: "You've spent \(fmt(cents: todayTotal)) today vs a daily average of \(fmt(cents: avgPerDay)).",
            severity: ratio >= 3.0 ? .warning : .info,
            advice: "If this was a one-off (rent, annual bill) dismiss. Otherwise, slow down today.",
            cause: "Based on trailing 30-day daily average.",
            expiresAt: cal.date(byAdding: .day, value: 1, to: now),
            dedupeKey: "anomaly:daySpike:\(yearMonthDay(now))",
            deeplink: .transactions
        )]
    }

    // MARK: - Anomaly: New large merchant

    /// First-time merchant (identified by normalized `note`) with an amount
    /// above 1.5× the trailing 60-day average transaction size.
    static func newLargeMerchant(store: Store) -> [AIInsight] {
        let cal = Calendar.current
        let now = Date()
        guard let cutoff = cal.date(byAdding: .day, value: -60, to: now),
              let recentWindow = cal.date(byAdding: .day, value: -7, to: now) else { return [] }

        let expenses = store.transactions.filter { $0.type == .expense && $0.amount > 0 }
        guard expenses.count >= 10 else { return [] }

        let windowTotal = expenses.filter { $0.date >= cutoff && $0.date < recentWindow }
        guard !windowTotal.isEmpty else { return [] }
        let avgAmount = windowTotal.reduce(0) { $0 + $1.amount } / windowTotal.count
        guard avgAmount > 0 else { return [] }
        let threshold = Double(avgAmount) * 1.5

        let historicalMerchants = Set(windowTotal.map { normalizeMerchant($0.note) })

        var seen = Set<String>()
        var out: [AIInsight] = []
        for txn in expenses.filter({ $0.date >= recentWindow }) {
            let key = normalizeMerchant(txn.note)
            guard !key.isEmpty, !historicalMerchants.contains(key), !seen.contains(key) else { continue }
            guard Double(txn.amount) >= threshold else { continue }
            seen.insert(key)

            out.append(AIInsight(
                type: .spendingAnomaly,
                title: "New merchant: \(txn.note)",
                body: "\(fmt(cents: txn.amount)) at \(txn.note) — first time in the last 60 days, \(Int(Double(txn.amount) / Double(avgAmount)))× your typical charge.",
                severity: .info,
                advice: "Verify the charge and tag it if it will repeat.",
                cause: "Average transaction size over last 60 days: \(fmt(cents: avgAmount)).",
                expiresAt: cal.date(byAdding: .day, value: 5, to: now),
                dedupeKey: "anomaly:newMerchant:\(txn.id.uuidString)",
                deeplink: .transactions
            ))
        }
        return out
    }

    // MARK: - Duplicate transactions

    /// Finds pairs of transactions with the same merchant + amount within a
    /// 72-hour window. One insight per suspicious pair.
    static func duplicateTransactions(store: Store) -> [AIInsight] {
        let cal = Calendar.current
        let now = Date()
        guard let cutoff = cal.date(byAdding: .day, value: -14, to: now) else { return [] }

        let recent = store.transactions
            .filter { $0.type == .expense && $0.date >= cutoff && $0.amount > 0 }
            .sorted { $0.date < $1.date }

        var out: [AIInsight] = []
        var reported = Set<String>()
        for i in 0..<recent.count {
            let a = recent[i]
            let aKey = normalizeMerchant(a.note)
            guard !aKey.isEmpty else { continue }
            for j in (i + 1)..<recent.count {
                let b = recent[j]
                let gap = b.date.timeIntervalSince(a.date)
                if gap > 72 * 3600 { break }
                guard a.amount == b.amount else { continue }
                guard aKey == normalizeMerchant(b.note) else { continue }

                let pairKey = [a.id.uuidString, b.id.uuidString].sorted().joined(separator: "|")
                guard !reported.contains(pairKey) else { continue }
                reported.insert(pairKey)

                let hours = Int(gap / 3600)
                out.append(AIInsight(
                    type: .duplicateDetected,
                    title: "Possible duplicate: \(a.note)",
                    body: "Two \(fmt(cents: a.amount)) charges at \(a.note) within \(hours)h.",
                    severity: .warning,
                    advice: "Confirm both are real, or delete the duplicate.",
                    cause: "Matching amount and merchant \(hours)h apart.",
                    expiresAt: cal.date(byAdding: .day, value: 10, to: now),
                    dedupeKey: "duplicate:txn:\(pairKey)",
                    deeplink: .transactions
                ))
            }
        }
        return out
    }

    // MARK: - Helpers

    /// Running average daily spend (cents) over the last N days.
    private static func averageDailySpend(store: Store, lookbackDays: Int) -> Double {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -lookbackDays, to: Date()) else { return 0 }
        let total = store.transactions
            .filter { $0.type == .expense && $0.date >= cutoff }
            .reduce(0) { $0 + $1.amount }
        return Double(total) / Double(lookbackDays)
    }

    /// Normalize merchant text for matching — lowercase, trimmed, collapsed
    /// whitespace. Empty notes return empty string (dedupes to nothing).
    private static func normalizeMerchant(_ s: String) -> String {
        s.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    private static func yearMonth(_ date: Date) -> String {
        let cal = Calendar.current
        return String(format: "%04d-%02d", cal.component(.year, from: date), cal.component(.month, from: date))
    }

    private static func yearMonthDay(_ date: Date) -> String {
        let cal = Calendar.current
        return String(format: "%04d-%02d-%02d",
                      cal.component(.year, from: date),
                      cal.component(.month, from: date),
                      cal.component(.day, from: date))
    }

    private static func fmt(cents: Int) -> String {
        let amount = Double(cents) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    private static func fmtDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
