import Foundation

// ============================================================
// MARK: - SplitDraft (P7.2 — shared editor form state)
// ============================================================
//
// Drives the unified split editor (spec §4–§9 in
// docs/HOUSEHOLD_REBUILD_P7_EDITOR_SPEC.md). UI binds to this struct;
// engine handoff goes through `engineLines()` + `recordSplit(...)`.
//
// The macOS sibling is a verbatim port (different file, same shape) added
// when the macOS split editor rewrite lands.
// ============================================================

struct SplitDraft: Equatable {

    /// Cents. Comes from the parent transaction.
    var totalCents: Int
    /// Active member chosen as payer.
    var paidByMemberId: UUID?
    /// Selected split method.
    var method: ExpenseSplitMethod
    /// One row per active member. Order is the household member order.
    /// `value` interpretation depends on `method` — see spec §4.
    var rows: [Row] = []

    struct Row: Equatable, Identifiable {
        var id: UUID { memberId }
        var memberId: UUID
        var displayName: String
        /// `equal`   → ignored (computed display only)
        /// `percent` → 0…100
        /// `exact`   → cents
        /// `shares`  → integer weight
        var value: Double = 0

        var asEngineLine: SplitLine {
            SplitLine(memberId: memberId, value: value)
        }
    }

    init(
        totalCents: Int,
        paidByMemberId: UUID? = nil,
        method: ExpenseSplitMethod = .equal,
        rows: [Row] = []
    ) {
        self.totalCents = totalCents
        self.paidByMemberId = paidByMemberId
        self.method = method
        self.rows = rows
    }

    // MARK: Engine handoff (spec §9)

    /// Lines to hand to `recordSplit` / `editSplit`. `equal` returns `[]`
    /// because the engine computes shares from the active-member list.
    func engineLines() -> [SplitLine] {
        switch method {
        case .equal: return []
        case .percent, .exact, .shares:
            return rows.map(\.asEngineLine)
        }
    }

    // MARK: Validation (spec §6)

    enum ValidationError: Equatable {
        case zeroTotal
        case noPayer
        case payerArchived
        case needsTwoActiveMembers
        case percentSumOff(actual: Double)
        case percentOutOfRange
        case exactRemainder(cents: Int)         // positive = short, negative = over
        case exactNegativeLine
        case sharesAllZero
        case sharesNegative
    }

    var validationError: ValidationError? {
        if totalCents <= 0 { return .zeroTotal }
        if paidByMemberId == nil { return .noPayer }

        switch method {
        case .equal:
            if rows.count < 2 { return .needsTwoActiveMembers }
            return nil

        case .percent:
            for r in rows where r.value < 0 || r.value > 100 {
                return .percentOutOfRange
            }
            let sum = rows.reduce(0) { $0 + $1.value }
            if abs(sum - 100) > 0.01 { return .percentSumOff(actual: sum) }
            return nil

        case .exact:
            for r in rows where r.value < 0 {
                return .exactNegativeLine
            }
            let sumCents = rows.reduce(0) { $0 + Int($1.value.rounded()) }
            let remaining = totalCents - sumCents
            if remaining != 0 { return .exactRemainder(cents: remaining) }
            return nil

        case .shares:
            for r in rows where r.value < 0 {
                return .sharesNegative
            }
            let total = rows.reduce(0.0) { $0 + $1.value }
            if total <= 0 { return .sharesAllZero }
            return nil
        }
    }

    var isValid: Bool { validationError == nil }

    // MARK: Live indicator copy (spec §7)

    /// Footer string driven by current state. Per UX spec §7:
    /// "All set ✓", "€X.XX short", "€X.XX too much", or method-specific.
    var indicatorText: String {
        switch validationError {
        case .none: return "All set"
        case .exactRemainder(let cents):
            let euros = Double(abs(cents)) / 100.0
            let str = String(format: "%.2f", euros)
            return cents > 0 ? "€\(str) short" : "€\(str) too much"
        case .percentSumOff(let actual):
            let str = String(format: "%.1f", actual)
            return "\(str)% / 100%"
        case .needsTwoActiveMembers: return "Need at least 2 members"
        case .noPayer: return "Pick a payer"
        case .payerArchived: return "Payer is archived"
        case .zeroTotal: return "Total must be greater than zero"
        case .percentOutOfRange: return "Percent must be 0–100"
        case .exactNegativeLine, .sharesNegative: return "No negative values"
        case .sharesAllZero: return "Add at least one share"
        }
    }

    // MARK: Method-switch helpers (spec §5)

    /// Reset row values to method-appropriate defaults. Called when the user
    /// flips the method picker. Member list is preserved.
    mutating func didChangeMethod() {
        switch method {
        case .equal:
            // Inputs hidden in `equal`; preserve `value: 0` baseline.
            for i in rows.indices { rows[i].value = 0 }
        case .percent:
            // Reset to 0; user fills in.
            for i in rows.indices { rows[i].value = 0 }
        case .exact:
            // Distribute equally as a starting point. Remainder to first row.
            let n = rows.count
            guard n > 0 else { return }
            let per = totalCents / n
            let remainder = totalCents - per * n
            for i in rows.indices { rows[i].value = Double(per) }
            if !rows.isEmpty { rows[0].value += Double(remainder) }
        case .shares:
            for i in rows.indices { rows[i].value = 1 }
        }
    }
}
