# Split Editor — Unified UX Spec (P7)

Companion to `HOUSEHOLD_REBUILD_P1_SPEC.md`. Locks the user-facing behaviour
of the split-expense editor across iOS and macOS so the engine surface from
P5 (`recordSplit/editSplit`) drives identical UI on both platforms.

> Status: **DRAFT — pending sign-off**. This phase ships the spec + shared
> form-state model only; SwiftUI implementation lands per-platform in a
> follow-up session.

---

## 1. Goals

1. One UX, two SwiftUI implementations.
2. Method picker exposes all four: `equal`, `percent`, `exact`, `shares`.
3. Live remainder indicator: at any moment the user can see how far the
   current line totals are from the parent transaction total.
4. Engine sees a validated payload. UI prevents submission of invalid
   states.

## 2. Non-goals (v1)

- Per-line currency override.
- Saved presets ("the usual 60/40").
- AI-suggested splits (could land later as a button that pre-fills lines).
- Split history / past-edit undo on the editor itself (lives in the
  household activity log).

## 3. Anatomy

```
┌────────────────────────────────────────────┐
│  ← Cancel              Split             ⤴│  Header
├────────────────────────────────────────────┤
│  Total                            €42.50   │  Read-only header chip
│  Paid by      [ Anna ▾ ]                   │  Member picker
│                                             │
│  How to split                              │
│  [ Equal ] [ Percent ] [ Exact ] [ Shares ]│  Segmented control
├────────────────────────────────────────────┤
│  Anna                            ────       │  Per-member row
│  Brian                           ────       │  (right-side input
│  Catalina                        ────       │   depends on method)
├────────────────────────────────────────────┤
│  Remaining                       €0.00 ✓   │  Footer indicator
│                                             │
│  [        Save split        ]              │  Primary CTA
└────────────────────────────────────────────┘
```

## 4. Method modes

### 4.1 `equal`

- All right-side inputs hidden. Each row shows its computed share
  (read-only).
- Engine: `lines: []` (member list is implicit — every active member is in).
- Remainder indicator: always €0.00 ✓ (engine assigns the rounding penny to
  the payer).
- Edge case: if every member is archived except payer, show error inline
  ("need at least 2 active members to split equally").

### 4.2 `percent`

- Right-side input is `0…100` percent, suffixed with `%`. Numeric
  keypad, two decimals max.
- Sum-of-percent indicator under the rows: `99.5% / 100%` (red if not 100,
  green check at 100).
- Each row also shows the live cents equivalent in muted text:
  `(€21.25)`.
- Submit disabled until sum == 100 (within ±0.01 tolerance).
- Engine: `lines: [(memberId, percent)]`.

### 4.3 `exact`

- Right-side input is currency, formatted per the user's locale.
- Live remainder indicator: `Remaining €3.50` (red if non-zero, green ✓ at
  zero).
- Submit disabled until remainder == 0.
- Engine: `lines: [(memberId, cents)]`. Lines with zero amount are still
  sent (member explicitly owes €0).

### 4.4 `shares`

- Right-side input is integer weight (default 1). Stepper controls.
- Sum-of-shares shown: `5 shares`.
- Each row shows live cents equivalent: `(€8.50)`.
- Engine computes per-row cents = `total * weight / Σweight`. Penny
  rounding to payer.
- Engine: `lines: [(memberId, weight)]`.

## 5. Cross-mode behavior

- **Switching methods preserves member list** but resets right-side values
  to the new method's defaults (`equal` removes inputs, `percent` zeros
  them, `exact` distributes equally as a starting point, `shares` sets each
  to weight 1).
- **Adding a member** mid-edit (rare — would only happen if a member was
  added in another tab) inserts at end with method-default value and shifts
  remainder.
- **Archived members** are excluded from the editor entirely. Editing a
  pre-existing split that referenced an archived member surfaces a banner:
  "One member has been archived since this split was created. Re-saving
  will rebuild without them." Engine keeps the original share row intact
  in storage until the user actually re-saves.

## 6. Validation contract

A draft is `valid` when ALL of:

- `totalCents > 0`
- `paidByMemberId` is set and active
- For `equal`: at least 2 active members exist.
- For `percent`: `Σ percent == 100 ± 0.01`, all percents in `[0, 100]`.
- For `exact`: `Σ cents == totalCents`, all cents `≥ 0`.
- For `shares`: `Σ weight > 0`, all weights `≥ 0` integers.

The Save button is disabled (not hidden) when invalid; tapping the
disabled button shows a one-line inline error explaining the first failed
rule.

## 7. Microcopy

- Header: `Split` (new) / `Edit split` (existing).
- Save button: `Save split`. After save, sheet dismisses and the parent
  view shows a toast: `Split saved`.
- Method labels: `Equal`, `Percent`, `Exact`, `Shares`.
- Remainder messages:
  - On target: `All set ✓`
  - Over: `€{x} too much` (red).
  - Under: `€{x} short` (red).

## 8. Accessibility

- Method picker exposes each option as a separate accessibility element
  (`accessibilityLabel("Method"), accessibilityValue("Percent")`, etc.).
- Per-member rows combine `accessibilityElement(children: .combine)` so
  VoiceOver reads `"Anna, owes €21.25"` as one element.
- Remainder indicator is an accessibility live region — updates announce
  immediately.
- Numeric inputs use `.keyboardType(.decimalPad)` (iOS).

## 9. Engine handoff

On Save:

```
HouseholdEngine.recordSplit(
    transactionId: <existing or new UUID>,
    totalCents: draft.totalCents,
    paidByMemberId: draft.paidByMemberId!,
    method: draft.method,
    lines: draft.engineLines()
)
```

`engineLines()` is implemented on the shared form-state model (P7.2 ships
it). For `equal`, it returns `[]`. For other methods, it returns the
per-member entries.

## 10. Files affected

### iOS
- Primary: [balance/Views/Household/SplitExpenseView.swift](../balance/Views/Household/SplitExpenseView.swift) — replace the body with the spec'd UX. Currently uses the legacy `SplitRule` enum directly.
- Add: a small composable component for the per-member row (used by both `equal`/`percent`/`exact`/`shares`).
- Touch: any caller that constructs a `SplitExpense` directly should switch to `recordSplit` via `HouseholdEngine`.

### macOS
- Primary: existing splits sheet inside [Centmond/Views/Household/HouseholdView.swift](../../Centmond/Centmond/Views/Household/HouseholdView.swift) (the file that holds the household UI today). When P5 macOS conformance lands, route through `recordSplit`.
- macOS today uses `ExpenseShare` rows already, so the editor is closer to the spec; mostly needs the method picker update and the live remainder indicator.

## 11. Out of scope for P7

- Wiring the new editor into AI Confirm cards (P10).
- Localisation of microcopy beyond English (handled when the broader app
  pass goes multi-locale).
- Tablet / iPad-specific layout (uses the stock sheet on iPad initially).

---

**Sign-off checklist:**

- [ ] Section §4 method modes approved
- [ ] Section §5 cross-mode behaviour approved
- [ ] Section §6 validation rules approved
- [ ] Section §7 microcopy approved
