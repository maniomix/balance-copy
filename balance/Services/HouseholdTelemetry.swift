import Foundation
import Combine

// ============================================================
// MARK: - Household Telemetry (Phase 6c — iOS port)
// ============================================================
//
// Weekly counters for the Household hub:
//   - `splitsThisWeek` — `SplitExpense` rows created this ISO week
//   - `settlementsThisWeek` — `Settlement` rows logged this ISO week
//
// Callers (`HouseholdManager` create paths, `SplitExpenseView`
// action buttons) bump the counters at the mutation site.
//
// Ported from macOS Centmond. Two decisions:
//   1. ObservableObject + `@Published` (iOS convention) instead of
//      macOS's `@Observable`.
//   2. Attribution-coverage metric DROPPED. macOS counts "% of txns
//      with `householdMember` set" — iOS Transaction has no such
//      field; attribution lives in `SplitExpense.paidBy` +
//      `splitBetween` lists, a different data shape. Adding a
//      coverage metric over SplitExpenses could land as a follow-up
//      but isn't 1:1 with the macOS one.
// ============================================================

@MainActor
final class HouseholdTelemetry: ObservableObject {

    static let shared = HouseholdTelemetry()

    private let defaults = UserDefaults.standard
    private let splitsKey      = "household.splitsThisWeek"
    private let settlementsKey = "household.settlementsThisWeek"
    private let weekStartKey   = "household.telemetryWeekStart"

    @Published private(set) var splitsThisWeek: Int
    @Published private(set) var settlementsThisWeek: Int

    private init() {
        self.splitsThisWeek      = defaults.integer(forKey: splitsKey)
        self.settlementsThisWeek = defaults.integer(forKey: settlementsKey)
        rolloverIfNeeded()
    }

    // MARK: - Record events

    func recordSplitCreated() {
        rolloverIfNeeded()
        splitsThisWeek += 1
        defaults.set(splitsThisWeek, forKey: splitsKey)
    }

    func recordSettlementLogged() {
        rolloverIfNeeded()
        settlementsThisWeek += 1
        defaults.set(settlementsThisWeek, forKey: settlementsKey)
    }

    func reset() {
        splitsThisWeek = 0
        settlementsThisWeek = 0
        defaults.set(0, forKey: splitsKey)
        defaults.set(0, forKey: settlementsKey)
    }

    // MARK: - Rollover

    /// ISO-week rollover. First mutation (or init) in a new week zeroes
    /// the counters. Matches `ReviewQueueTelemetry` for consistency.
    private func rolloverIfNeeded() {
        let cal = Calendar.current
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let weekKey = "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
        let stored = defaults.string(forKey: weekStartKey) ?? ""
        if stored != weekKey {
            splitsThisWeek = 0
            settlementsThisWeek = 0
            defaults.set(0, forKey: splitsKey)
            defaults.set(0, forKey: settlementsKey)
            defaults.set(weekKey, forKey: weekStartKey)
        }
    }
}
