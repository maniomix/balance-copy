import Foundation

// ============================================================
// MARK: - AI Household Insight Detectors (iOS port of macOS P7)
// ============================================================
//
// Three detectors adapted from macOS `HouseholdInsightDetectors`:
//
//   1. imbalance        — top pairwise debt above threshold
//   2. unpaidShares     — open splits aging past N days
//   3. spenderSpike     — member's share of split-expense total is
//                         >= 50% AND 2× their 3-month average
//
// Unattributed-recurring is NOT ported: iOS `Transaction` and
// `RecurringTransaction` have no `householdMember` field, so there's
// nothing to detect.
//
// Dedupe keys are namespaced under "household:" — matches the macOS
// prefix rule so they share a dismissal silo.
// ============================================================

@MainActor
enum AIHouseholdInsightDetectors {

    // MARK: - Tunables (cents)

    private static let imbalanceThreshold: Int = 10_000       // $100.00
    private static let unpaidMinTotal: Int     = 2_500        // $25.00
    private static let spikeShareFloor: Double = 0.5
    private static let spikeRatioFloor: Double = 2.0

    /// Aging days, clamped at call site (per feedback rule).
    private static var unpaidAgeDays: Int {
        let raw = UserDefaults.standard.object(forKey: "householdUnsettledReminderDays") as? Int ?? 30
        return max(7, min(raw, 90))
    }

    /// Global kill-switch mirroring macOS P9.
    private static var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: "householdNotificationsEnabled") as? Bool ?? true
    }

    // MARK: - Entry

    static func all(manager: HouseholdManager = .shared) -> [AIInsight] {
        guard notificationsEnabled, manager.household != nil else { return [] }
        var out: [AIInsight] = []
        out += imbalance(manager: manager)
        out += unpaidShares(manager: manager)
        out += spenderSpike(manager: manager)
        return out
    }

    // MARK: - Imbalance

    private static func imbalance(manager: HouseholdManager) -> [AIInsight] {
        let pairs = manager.openPairBalances()
        guard let top = pairs.first, top.amount >= imbalanceThreshold else { return [] }

        let severity: AIInsight.Severity
        let bucket: String
        if top.amount >= 50_000 {       // $500+
            severity = .warning; bucket = "gt500"
        } else if top.amount >= 25_000 { // $250+
            severity = .warning; bucket = "gt250"
        } else {
            severity = .info; bucket = "gt100"
        }

        let amountStr = DS.Format.money(top.amount)
        let title = "\(top.creditor.displayName) is owed \(amountStr)"
        let body = "\(top.debtor.displayName) owes \(top.creditor.displayName) \(amountStr) across open splits. Record a settlement to zero the ledger."

        return [AIInsight(
            type: .householdAlert,
            title: title,
            body: body,
            severity: severity,
            advice: "Open Settle Up and log the payment — FIFO walk will also flip the oldest splits to settled.",
            cause: "Computed from open split-expense shares minus same-direction settlements (clamp-safe).",
            expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
            dedupeKey: "household:imbalance:\(bucket)",
            deeplink: .household
        )]
    }

    // MARK: - Unpaid shares aging

    private static func unpaidShares(manager: HouseholdManager) -> [AIInsight] {
        guard let h = manager.household else { return [] }
        let days = unpaidAgeDays
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else { return [] }

        let aging = manager.splitExpenses.filter {
            $0.householdId == h.id
                && !$0.isSettled
                && $0.createdAt <= cutoff
        }
        guard !aging.isEmpty else { return [] }

        let total = aging.reduce(0) { $0 + $1.amount }
        guard total >= unpaidMinTotal else { return [] }

        let count = aging.count
        return [AIInsight(
            type: .householdAlert,
            title: "\(count) share\(count == 1 ? "" : "s") pending > \(days) days",
            body: "\(DS.Format.money(total)) in split shares has been sitting unsettled for over \(days) days.",
            severity: .info,
            advice: "Open Settle Up and clear the oldest balances — or mark them settled manually if the household never planned to collect.",
            cause: "SplitExpense rows with isSettled == false and createdAt older than \(days) days.",
            expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
            dedupeKey: "household:unpaid:\(count)",
            deeplink: .household
        )]
    }

    // MARK: - Spender spike

    /// iOS-adapted spender-spike. Uses `SplitExpense.splits(members:)` amounts
    /// per member, since iOS transactions aren't attributed to household
    /// members. This catches split-expense skew, not global transaction skew.
    private static func spenderSpike(manager: HouseholdManager) -> [AIInsight] {
        guard let h = manager.household, h.members.count >= 2 else { return [] }

        let cal = Calendar.current
        let now = Date()
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let threeMonthStart = cal.date(byAdding: .month, value: -3, to: monthStart)
        else { return [] }

        let hid = h.id
        let thisMonth = manager.splitExpenses.filter {
            $0.householdId == hid && $0.date >= monthStart
        }
        let priorWindow = manager.splitExpenses.filter {
            $0.householdId == hid && $0.date >= threeMonthStart && $0.date < monthStart
        }

        func tally(_ expenses: [SplitExpense]) -> [String: Int] {
            var acc: [String: Int] = [:]
            for e in expenses {
                let splits = e.splits(members: h.members)
                for s in splits {
                    acc[s.userId, default: 0] += s.amount
                }
            }
            return acc
        }

        let monthShares = tally(thisMonth)
        let priorTotals = tally(priorWindow)

        let monthTotal = monthShares.values.reduce(0, +)
        guard monthTotal > 0 else { return [] }

        guard let (topId, topAmt) = monthShares.max(by: { $0.value < $1.value }),
              let topMember = h.members.first(where: { $0.userId == topId })
        else { return [] }

        let shareOfTotal = Double(topAmt) / Double(monthTotal)
        guard shareOfTotal >= spikeShareFloor else { return [] }

        let priorMonthly = Double(priorTotals[topId] ?? 0) / 3.0
        guard priorMonthly > 0 else { return [] }

        let ratio = Double(topAmt) / priorMonthly
        guard ratio >= spikeRatioFloor else { return [] }

        let pct = Int((shareOfTotal * 100).rounded())
        let ratioStr = String(format: "%.1fx", ratio)
        let priorCents = Int(priorMonthly)

        return [AIInsight(
            type: .householdAlert,
            title: "\(topMember.displayName) is \(pct)% of household splits",
            body: "\(topMember.displayName) is attributed \(DS.Format.money(topAmt)) in splits this month — \(ratioStr) their 3-month average of \(DS.Format.money(priorCents)).",
            severity: .info,
            advice: "Scan their recent split expenses for a one-off purchase or a new recurring bill before assuming a real shift.",
            cause: "Sum of SplitExpense shares per member, this month vs mean of prior 3 months.",
            expiresAt: Calendar.current.date(byAdding: .day, value: 10, to: Date()),
            dedupeKey: "household:spike:\(topMember.userId.prefix(8))",
            deeplink: .household
        )]
    }
}
