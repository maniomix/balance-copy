import Foundation

// ============================================================
// MARK: - AISubscription Forecast (Phase 3b — iOS port)
// ============================================================
//
// Projects upcoming charges for active aiSubscriptions over a date range.
// Pure compute — no Store access, no SwiftData. Callers pass already-
// filtered aiSubscriptions so this stays unit-testable and cacheable.
//
// Ported from macOS Centmond `SubscriptionForecast.swift`. Adapted:
//   - Amounts are `Int` cents (iOS convention) instead of `Decimal`
//   - Everything else is math, no data-layer changes
//
// Two primary outputs:
//   - flat `[UpcomingCharge]` list for timeline UIs
//   - daily `[Date: Int]` histogram for the Prediction page
// ============================================================

enum SubscriptionForecast {

    struct UpcomingCharge: Identifiable, Hashable {
        let id: UUID
        let subscriptionID: UUID
        let displayName: String
        let iconSymbol: String?
        let colorHex: String?
        let amount: Int            // cents; 0 for trial-end markers
        let date: Date
        let isTrialEnd: Bool

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    // MARK: - Timeline

    /// Flat list of projected charges for every active subscription within
    /// `[from, to]`. Multiple occurrences per subscription when the cycle
    /// is short enough to repeat in-window. Sorted by date ascending.
    /// Trial-end markers included as zero-amount entries when enabled.
    static func upcomingCharges(
        for aiSubscriptions: [AISubscription],
        from: Date,
        to: Date,
        includeTrialEnds: Bool = true
    ) -> [UpcomingCharge] {
        guard from <= to else { return [] }
        var out: [UpcomingCharge] = []

        for sub in aiSubscriptions where sub.status == .active || sub.status == .trial {
            let cadence = max(sub.effectiveCadenceDays, 1)
            var cursor = sub.nextPaymentDate
            var safety = 0
            let maxIterations = 500

            // Step forward to the window when `nextPaymentDate` is past.
            if cursor < from {
                while cursor < from, safety < maxIterations {
                    guard let next = advance(cursor, cycle: sub.billingCycle, customDays: sub.customCadenceDays) else { break }
                    if next <= cursor { break }
                    cursor = next
                    safety += 1
                }
            }

            while cursor <= to, safety < maxIterations {
                if cursor >= from {
                    out.append(UpcomingCharge(
                        id: UUID(),
                        subscriptionID: sub.id,
                        displayName: sub.serviceName,
                        iconSymbol: sub.iconSymbol,
                        colorHex: sub.colorHex,
                        amount: sub.amount,
                        date: cursor,
                        isTrialEnd: false
                    ))
                }
                guard let next = advance(cursor, cycle: sub.billingCycle, customDays: sub.customCadenceDays) else { break }
                if next <= cursor { break }
                cursor = next
                safety += 1
                if cadence >= 365 && out.count > 100 { break } // paranoia ceiling
            }

            if includeTrialEnds, sub.isTrial,
               let trialEnd = sub.trialEndsAt,
               trialEnd >= from, trialEnd <= to {
                out.append(UpcomingCharge(
                    id: UUID(),
                    subscriptionID: sub.id,
                    displayName: sub.serviceName,
                    iconSymbol: sub.iconSymbol,
                    colorHex: sub.colorHex,
                    amount: 0,
                    date: trialEnd,
                    isTrialEnd: true
                ))
            }
        }

        return out.sorted { $0.date < $1.date }
    }

    // MARK: - Rolling window totals

    static func total(for charges: [UpcomingCharge]) -> Int {
        charges.reduce(0) { $0 + $1.amount }
    }

    /// Daily buckets of projected charges — used by the Prediction page so
    /// its chart can render recurring baseline as a distinct layer.
    /// Key is calendar-day start; value is summed cents.
    static func dailyBaseline(
        for aiSubscriptions: [AISubscription],
        from: Date,
        to: Date
    ) -> [Date: Int] {
        let charges = upcomingCharges(for: aiSubscriptions, from: from, to: to, includeTrialEnds: false)
        var buckets: [Date: Int] = [:]
        let cal = Calendar.current
        for c in charges {
            let day = cal.startOfDay(for: c.date)
            buckets[day, default: 0] += c.amount
        }
        return buckets
    }

    /// Total recurring outflow (cents) projected for the next N days from
    /// `anchor`. Feeds summary-bar stats like "Next 7 days: $42.98".
    static func projected(
        for aiSubscriptions: [AISubscription],
        next days: Int,
        from anchor: Date = Date()
    ) -> Int {
        let to = Calendar.current.date(byAdding: .day, value: days, to: anchor) ?? anchor
        let charges = upcomingCharges(for: aiSubscriptions, from: anchor, to: to, includeTrialEnds: false)
        return total(for: charges)
    }

    /// Groups upcoming charges by day for a simple timeline list.
    static func groupedByDay(_ charges: [UpcomingCharge]) -> [(day: Date, charges: [UpcomingCharge])] {
        let cal = Calendar.current
        var buckets: [Date: [UpcomingCharge]] = [:]
        for c in charges {
            let day = cal.startOfDay(for: c.date)
            buckets[day, default: []].append(c)
        }
        return buckets.keys.sorted().map { ($0, buckets[$0] ?? []) }
    }

    // MARK: - Date math (mirrors reconciliation so both stay in step)

    private static func advance(_ date: Date, cycle: AIBillingCycle, customDays: Int?) -> Date? {
        let cal = Calendar.current
        switch cycle {
        case .weekly:     return cal.date(byAdding: .weekOfYear, value: 1, to: date)
        case .biweekly:   return cal.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly:    return cal.date(byAdding: .month,      value: 1, to: date)
        case .quarterly:  return cal.date(byAdding: .month,      value: 3, to: date)
        case .semiannual: return cal.date(byAdding: .month,      value: 6, to: date)
        case .annual:     return cal.date(byAdding: .year,       value: 1, to: date)
        case .custom:     return cal.date(byAdding: .day, value: max(customDays ?? 30, 1), to: date)
        }
    }
}
