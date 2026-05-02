import Foundation

// ============================================================
// MARK: - SettleUpDraft (P8.2 — shared form state)
// ============================================================
//
// Drives the unified settle-up sheet (spec §3–§9 of
// docs/HOUSEHOLD_REBUILD_P8_SETTLEUP_SPEC.md).
//
// `materialize` is wired but the engine ignores it for v1 — the
// "Also record as a transaction" toggle is hidden in the UI until P8b
// resolves the open category/account questions.
// ============================================================

struct SettleUpDraft: Equatable {

    var fromMemberId: UUID?
    var toMemberId: UUID?
    /// Cents.
    var amountCents: Int
    var note: String
    var materialize: Bool

    /// Computed default that populates `amountCents` when from/to change.
    /// The engine's `openDebt` is the source; this struct only carries the
    /// chosen value.
    var defaultOpenDebtCents: Int = 0

    init(
        fromMemberId: UUID? = nil,
        toMemberId: UUID? = nil,
        amountCents: Int = 0,
        note: String = "",
        materialize: Bool = false
    ) {
        self.fromMemberId = fromMemberId
        self.toMemberId = toMemberId
        self.amountCents = amountCents
        self.note = note
        self.materialize = materialize
    }

    // MARK: Validation (spec §5)

    enum ValidationError: Equatable {
        case noFrom
        case noTo
        case samePair
        case zeroAmount
        case payerCannotSettle
    }

    /// Pure validation — does not check role permissions (caller passes
    /// `payerCanSettle` based on the resolved member's role).
    func validationError(payerCanSettle: Bool) -> ValidationError? {
        if fromMemberId == nil { return .noFrom }
        if toMemberId == nil { return .noTo }
        if fromMemberId == toMemberId { return .samePair }
        if amountCents <= 0 { return .zeroAmount }
        if !payerCanSettle { return .payerCannotSettle }
        return nil
    }

    func isValid(payerCanSettle: Bool) -> Bool {
        validationError(payerCanSettle: payerCanSettle) == nil
    }

    // MARK: Indicator copy (spec §4 over-amount warning)

    /// One-line indicator. `nil` when amount is at or below open debt.
    func overAmountWarning() -> String? {
        guard amountCents > defaultOpenDebtCents, defaultOpenDebtCents >= 0 else {
            return nil
        }
        let extra = Double(amountCents - defaultOpenDebtCents) / 100.0
        let str = String(format: "%.2f", extra)
        return "€\(str) more than open debt"
    }
}
