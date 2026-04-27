import Foundation

// ============================================================
// MARK: - Forecast Engine (Phase 4a — iOS port)
// ============================================================
//
// Produces a per-day financial forecast over a configurable horizon.
// Pure compute — no Store/SwiftData fetches. Callers pass already-
// filtered inputs (`Inputs`) and receive a single typed `Horizon`
// the UI can render directly.
//
// Ported from macOS Centmond `CashflowForecastEngine.swift`. Adapted:
//   - Amounts: `Int` cents throughout (not `Decimal`). Callers convert
//     Account's `Double` balance to cents at the boundary.
//   - Recurring are expense-only on iOS (no `isIncome` flag)
//   - `RecurringTransaction.nextOccurrence(from:)` replaces the
//     macOS `RecurrenceFrequency.nextDate(after:)` helper
//   - Goals: `monthlyContribution` derived from
//     `(targetAmount - currentAmount) / monthsToTarget` since iOS's
//     Goal struct has no standalone contribution field
//
// Three balance-change sources:
//   1. Known events — subscription + recurring charges projected forward
//   2. Goal contributions — one outflow per month
//   3. Variable discretionary — weekday-aware mean + σ from history
// ============================================================

enum CashflowForecastEngine {

    // MARK: - Inputs

    struct Inputs {
        /// Sum of eligible account balances in cents at horizon start.
        /// Callers convert Account's Double `currentBalance` at the boundary.
        var startingBalance: Int

        var aiSubscriptions: [AISubscription]
        var recurring: [RecurringTransaction]
        var goals: [Goal]
        var history: [Transaction]

        /// Trailing window (days) for the discretionary baseline fit.
        /// 60 smooths weekday noise without leaking stale behavior.
        var baselineWindowDays: Int = 60

        /// Anchor for "today". Injected so tests can pin it.
        var asOf: Date = Date()
    }

    // MARK: - Outputs

    enum EventKind: String {
        case subscription
        case recurringBill
        case recurringIncome
        case goalContribution
    }

    struct Event: Identifiable, Hashable {
        let id: UUID
        let date: Date
        let name: String
        /// Signed cents — positive for income, negative for outflow.
        let delta: Int
        let kind: EventKind
        let iconSymbol: String
        let sourceID: UUID?

        static func == (lhs: Event, rhs: Event) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    struct Day: Hashable {
        let date: Date
        let dayOffset: Int
        let expectedBalance: Int
        let lowBalance: Int
        let highBalance: Int
        let events: [Event]
        let discretionary: Int
        let safeToSpend: Int
    }

    struct Summary {
        let horizonDays: Int
        let startingBalance: Int
        let endingExpectedBalance: Int
        let lowestExpectedBalance: Int
        let lowestExpectedBalanceDate: Date
        /// First day where the P10 band dips below zero — earliest plausible
        /// overdraft. `nil` if the cone stays positive.
        let firstAtRiskDate: Date?
        /// First day the expected line itself dips below zero.
        let firstExpectedNegativeDate: Date?
        let totalProjectedObligations: Int
        let totalProjectedIncome: Int
        let totalProjectedDiscretionary: Int
        let dailyDiscretionaryMean: Double
        let dailyDiscretionaryStdDev: Double
    }

    struct Horizon {
        let days: [Day]
        let summary: Summary
    }

    // MARK: - Scenario

    /// A lightweight set of tweaks applied to `Inputs` at build time — the
    /// what-if simulator. Views hold one in `@State`, update via sliders,
    /// and call `build(..., scenario:)` for a parallel overlay.
    struct Scenario: Equatable {
        var skippedSubscriptionIDs: Set<UUID> = []
        var skippedRecurringIDs: Set<UUID> = []
        var skippedGoalIDs: Set<UUID> = []
        /// Multiplier applied to discretionary mean — 0.8 = "spend 20% less".
        /// Clamped ≥ 0.
        var spendMultiplier: Double = 1.0
        var oneOffs: [OneOff] = []

        struct OneOff: Identifiable, Equatable {
            let id: UUID
            let date: Date
            /// Signed cents — negative = expense, positive = income.
            let delta: Int
            let label: String

            init(id: UUID = UUID(), date: Date, delta: Int, label: String) {
                self.id = id
                self.date = date
                self.delta = delta
                self.label = label
            }
        }

        var isIdentity: Bool {
            skippedSubscriptionIDs.isEmpty
                && skippedRecurringIDs.isEmpty
                && skippedGoalIDs.isEmpty
                && abs(spendMultiplier - 1.0) < 0.001
                && oneOffs.isEmpty
        }
    }

    // MARK: - Monthly risk

    enum MonthRisk {
        case healthy
        case tight
        case overdraft
    }

    struct MonthSummary: Identifiable {
        var id: Date { monthStart }
        let monthStart: Date
        let monthEnd: Date
        let daysIncluded: Int
        let startingBalance: Int
        let endingBalance: Int
        let lowestBalance: Int
        let lowestBalanceDate: Date
        let income: Int
        let obligations: Int
        let discretionary: Int
        /// Signed: income − obligations − discretionary.
        let net: Int
        let biggestEvent: Event?
        let risk: MonthRisk
    }

    // MARK: - Entry point

    static func build(_ inputs: Inputs, horizonDays: Int, scenario: Scenario = Scenario()) -> Horizon {
        let cal = Calendar.current
        let today = cal.startOfDay(for: inputs.asOf)
        let horizon = max(1, horizonDays)
        let end = cal.date(byAdding: .day, value: horizon, to: today) ?? today
        let spendMult = max(0, scenario.spendMultiplier)

        // --- Baseline fit ----------------------------------------------------
        let baseline = fitWeekdayBaseline(
            history: inputs.history,
            asOf: today,
            windowDays: inputs.baselineWindowDays,
            calendar: cal
        )

        // --- Collect future events ------------------------------------------
        var eventsByDay: [Date: [Event]] = [:]

        let activeSubs = inputs.aiSubscriptions.filter { !scenario.skippedSubscriptionIDs.contains($0.id) }
        for charge in SubscriptionForecast.upcomingCharges(
            for: activeSubs, from: today, to: end, includeTrialEnds: false
        ) where charge.amount > 0 {
            let day = cal.startOfDay(for: charge.date)
            eventsByDay[day, default: []].append(Event(
                id: charge.id,
                date: day,
                name: charge.displayName,
                delta: -charge.amount,
                kind: .subscription,
                iconSymbol: charge.iconSymbol ?? "arrow.triangle.2.circlepath",
                sourceID: charge.subscriptionID
            ))
        }

        for tpl in inputs.recurring where tpl.isActive && !scenario.skippedRecurringIDs.contains(tpl.id) {
            var stepped = tpl
            var cursor: Date? = stepped.nextOccurrence(from: today)
            var safety = 0
            while let next = cursor, next <= end, safety < 500 {
                if next >= today {
                    let day = cal.startOfDay(for: next)
                    // iOS recurring templates are expense-only.
                    eventsByDay[day, default: []].append(Event(
                        id: UUID(),
                        date: day,
                        name: tpl.name,
                        delta: -tpl.amount,
                        kind: .recurringBill,
                        iconSymbol: "repeat",
                        sourceID: tpl.id
                    ))
                }
                stepped.lastProcessedDate = next
                cursor = stepped.nextOccurrence(from: next)
                safety += 1
            }
        }

        for goal in inputs.goals where !goal.isCompleted && !scenario.skippedGoalIDs.contains(goal.id) {
            let monthly = impliedMonthlyContribution(for: goal, asOf: today)
            guard monthly > 0 else { continue }
            // One draw per calendar month inside the horizon, anchored to
            // today's day-of-month.
            var cursor = today
            var safety = 0
            while cursor <= end, safety < 24 {
                if cursor >= today {
                    let day = cal.startOfDay(for: cursor)
                    eventsByDay[day, default: []].append(Event(
                        id: UUID(),
                        date: day,
                        name: goal.name,
                        delta: -monthly,
                        kind: .goalContribution,
                        iconSymbol: goal.icon.isEmpty ? "target" : goal.icon,
                        sourceID: goal.id
                    ))
                }
                guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
                safety += 1
            }
        }

        for oneOff in scenario.oneOffs where oneOff.date >= today && oneOff.date <= end {
            let day = cal.startOfDay(for: oneOff.date)
            eventsByDay[day, default: []].append(Event(
                id: oneOff.id,
                date: day,
                name: oneOff.label,
                delta: oneOff.delta,
                kind: oneOff.delta > 0 ? .recurringIncome : .recurringBill,
                iconSymbol: oneOff.delta > 0 ? "plus.circle" : "minus.circle",
                sourceID: nil
            ))
        }

        // --- Walk the horizon day-by-day -----------------------------------
        var expected = inputs.startingBalance
        var low = inputs.startingBalance
        var high = inputs.startingBalance
        var days: [Day] = []

        var totalObligations = 0
        var totalIncome = 0
        var totalDiscretionaryDouble = 0.0
        var lowestExpected = inputs.startingBalance
        var lowestExpectedDate = today
        var firstAtRisk: Date?
        var firstExpectedNegative: Date?

        days.reserveCapacity(horizon + 1)
        days.append(Day(
            date: today, dayOffset: 0,
            expectedBalance: expected, lowBalance: low, highBalance: high,
            events: sortEvents(eventsByDay[today] ?? []),
            discretionary: 0, safeToSpend: expected
        ))

        for offset in 1...horizon {
            guard let date = cal.date(byAdding: .day, value: offset, to: today) else { break }
            let dayKey = cal.startOfDay(for: date)
            let dayEvents = sortEvents(eventsByDay[dayKey] ?? [])

            let eventDelta = dayEvents.reduce(0) { $0 + $1.delta }
            let incomeToday = dayEvents.filter { $0.delta > 0 }.reduce(0) { $0 + $1.delta }
            let outflowToday = dayEvents.filter { $0.delta < 0 }.reduce(0) { $0 - $1.delta }

            totalIncome += incomeToday
            totalObligations += outflowToday

            let bucket = baseline.bucket(for: dayKey, calendar: cal)
            let mean = bucket.mean * spendMult
            let stdev = bucket.stdev * spendMult
            totalDiscretionaryDouble += mean

            let meanCents = Int(mean.rounded())
            let stdevCents = Int(stdev.rounded())

            expected += eventDelta - meanCents
            low += eventDelta - (meanCents + stdevCents)
            high += eventDelta - max(0, meanCents - stdevCents)

            if expected < lowestExpected { lowestExpected = expected; lowestExpectedDate = dayKey }
            if firstAtRisk == nil, low < 0 { firstAtRisk = dayKey }
            if firstExpectedNegative == nil, expected < 0 { firstExpectedNegative = dayKey }

            days.append(Day(
                date: dayKey, dayOffset: offset,
                expectedBalance: expected, lowBalance: low, highBalance: high,
                events: dayEvents, discretionary: meanCents, safeToSpend: expected
            ))
        }

        let summary = Summary(
            horizonDays: horizon,
            startingBalance: inputs.startingBalance,
            endingExpectedBalance: expected,
            lowestExpectedBalance: lowestExpected,
            lowestExpectedBalanceDate: lowestExpectedDate,
            firstAtRiskDate: firstAtRisk,
            firstExpectedNegativeDate: firstExpectedNegative,
            totalProjectedObligations: totalObligations,
            totalProjectedIncome: totalIncome,
            totalProjectedDiscretionary: Int(totalDiscretionaryDouble.rounded()),
            dailyDiscretionaryMean: baseline.pooled.mean,
            dailyDiscretionaryStdDev: baseline.pooled.stdev
        )

        return Horizon(days: days, summary: summary)
    }

    // MARK: - Implied monthly goal contribution

    /// Derives the monthly draw a goal needs to hit its target by its
    /// target date. Falls back to 0 if no target date or the target is
    /// already met.
    private static func impliedMonthlyContribution(for goal: Goal, asOf: Date) -> Int {
        let gap = goal.targetAmount - goal.currentAmount
        guard gap > 0 else { return 0 }
        guard let deadline = goal.targetDate, deadline > asOf else { return 0 }
        let months = max(1, Calendar.current.dateComponents([.month], from: asOf, to: deadline).month ?? 1)
        return Int(Double(gap) / Double(months))
    }

    // MARK: - Baseline fit

    struct Baseline: Equatable {
        let mean: Double
        let stdev: Double
        let sampleDays: Int
    }

    struct WeekdayBaseline: Equatable {
        static let minSamplesPerBucket = 3
        let byWeekday: [Int: Baseline]
        let pooled: Baseline

        func bucket(for date: Date, calendar: Calendar) -> Baseline {
            let wd = calendar.component(.weekday, from: date)
            if let b = byWeekday[wd], b.sampleDays >= Self.minSamplesPerBucket {
                return b
            }
            return pooled
        }
    }

    /// Weekday-aware fit: groups daily discretionary totals by weekday and
    /// computes per-bucket mean + population σ, plus a pooled baseline for
    /// fallback. Discretionary = expense transactions. iOS has no
    /// `recurringTemplateID` back-link on Transaction, so recurring charges
    /// in historical data may double-count against future recurring events
    /// (a later phase should tag transactions with their template ID).
    /// Zero-spend days are included so dry stretches don't inflate means.
    static func fitWeekdayBaseline(
        history: [Transaction],
        asOf: Date,
        windowDays: Int,
        calendar: Calendar = .current
    ) -> WeekdayBaseline {
        let today = calendar.startOfDay(for: asOf)
        guard let windowStart = calendar.date(byAdding: .day, value: -max(1, windowDays), to: today) else {
            return WeekdayBaseline(byWeekday: [:], pooled: Baseline(mean: 0, stdev: 0, sampleDays: 0))
        }

        var totalsByDay: [Date: Int] = [:]
        for tx in history {
            guard tx.type == .expense, !tx.isTransfer else { continue }
            guard tx.date >= windowStart, tx.date < today else { continue }
            let day = calendar.startOfDay(for: tx.date)
            totalsByDay[day, default: 0] += tx.amount
        }

        let days = max(1, calendar.dateComponents([.day], from: windowStart, to: today).day ?? windowDays)
        var perWeekday: [Int: [Double]] = [:]
        var pooledValues: [Double] = []
        pooledValues.reserveCapacity(days)

        for offset in 0..<days {
            guard let d = calendar.date(byAdding: .day, value: offset, to: windowStart) else { continue }
            let dayKey = calendar.startOfDay(for: d)
            let value = Double(totalsByDay[dayKey] ?? 0)
            pooledValues.append(value)
            let wd = calendar.component(.weekday, from: dayKey)
            perWeekday[wd, default: []].append(value)
        }

        let pooled = baseline(from: pooledValues)
        var buckets: [Int: Baseline] = [:]
        for (wd, values) in perWeekday {
            buckets[wd] = baseline(from: values)
        }
        return WeekdayBaseline(byWeekday: buckets, pooled: pooled)
    }

    private static func baseline(from values: [Double]) -> Baseline {
        guard !values.isEmpty else { return Baseline(mean: 0, stdev: 0, sampleDays: 0) }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { acc, v in
            let diff = v - mean
            return acc + diff * diff
        } / Double(values.count)
        return Baseline(mean: mean, stdev: variance.squareRoot(), sampleDays: values.count)
    }

    // MARK: - Helpers

    private static func sortEvents(_ events: [Event]) -> [Event] {
        events.sorted { a, b in
            if (a.delta > 0) != (b.delta > 0) { return a.delta > 0 }
            return abs(a.delta) > abs(b.delta)
        }
    }
}

// MARK: - Monthly breakdown (extension)

extension CashflowForecastEngine.Horizon {
    /// One entry per calendar month that any day in the horizon touches.
    /// Partial months at the start/end included — the UI can show "through
    /// day N" for the tail. Sorted ascending by `monthStart`.
    func monthlyBreakdown(calendar: Calendar = .current) -> [CashflowForecastEngine.MonthSummary] {
        guard !days.isEmpty else { return [] }

        var buckets: [Date: [CashflowForecastEngine.Day]] = [:]
        for day in days {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: day.date)) ?? day.date
            buckets[monthStart, default: []].append(day)
        }

        return buckets.keys.sorted().compactMap { monthStart in
            guard let bucket = buckets[monthStart], let first = bucket.first, let last = bucket.last else {
                return nil
            }
            let monthEnd = calendar.date(
                byAdding: DateComponents(month: 1, second: -1),
                to: monthStart
            ) ?? last.date

            var income = 0
            var obligations = 0
            var discretionary = 0
            var lowest = first.expectedBalance
            var lowestDate = first.date
            var biggest: CashflowForecastEngine.Event?

            for d in bucket {
                discretionary += d.discretionary
                for ev in d.events {
                    if ev.delta > 0 { income += ev.delta }
                    else { obligations += -ev.delta }
                    if ev.delta < 0 {
                        if biggest == nil || ev.delta < biggest!.delta { biggest = ev }
                    }
                }
                if d.expectedBalance < lowest {
                    lowest = d.expectedBalance
                    lowestDate = d.date
                }
            }

            let anyExpectedNeg = bucket.contains { $0.expectedBalance < 0 }
            let anyLowNeg = bucket.contains { $0.lowBalance < 0 }
            let risk: CashflowForecastEngine.MonthRisk = {
                if anyExpectedNeg { return .overdraft }
                if anyLowNeg { return .tight }
                return .healthy
            }()

            return CashflowForecastEngine.MonthSummary(
                monthStart: monthStart,
                monthEnd: monthEnd,
                daysIncluded: bucket.count,
                startingBalance: first.expectedBalance,
                endingBalance: last.expectedBalance,
                lowestBalance: lowest,
                lowestBalanceDate: lowestDate,
                income: income,
                obligations: obligations,
                discretionary: discretionary,
                net: income - obligations - discretionary,
                biggestEvent: biggest,
                risk: risk
            )
        }
    }
}
