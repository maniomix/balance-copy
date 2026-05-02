# Settle-Up Sheet — Unified UX Spec (P8)

Companion to `HOUSEHOLD_REBUILD_P1_SPEC.md` and `_P7_EDITOR_SPEC.md`. Locks
the user-facing settle-up flow on both platforms so both sheets call the
same engine method (`HouseholdEngine.settleUp(...)`) with identical
semantics.

> Status: **DRAFT — pending sign-off**.

---

## 1. Goals

1. Same UX on iOS + macOS, two SwiftUI implementations.
2. Live preview of which open shares the entered amount will close (FIFO,
   oldest first).
3. Optional "also record this as a transaction" toggle that, when on,
   creates a real ledger entry alongside the `Settlement` row.
4. Partial payments handled cleanly — the sheet doesn't force "settle
   everything".

## 2. Non-goals (v1)

- Splitting one settlement across multiple recipients in one save.
- Reverse direction (negative settle-up). Use `unsettle(settlementId:)`
  instead.
- Currency conversion if from-member and to-member have different default
  currencies.

## 3. Anatomy

```
┌────────────────────────────────────────────┐
│  ← Cancel          Settle up               │
├────────────────────────────────────────────┤
│  From            [ Brian ▾ ]               │  Active members only
│  To              [ Anna  ▾ ]               │  Active members only
│  Amount                       €18.00       │  Editable; defaults to open
│                                             │  debt from→to
│  Note            [ optional… ]              │
│                                             │
│  ──────────  Closes ──────────              │  Read-only preview
│  • Mar 12  Groceries          €12.00       │  FIFO oldest-first
│  • Mar 18  Dinner              €6.00       │  highlighted "will close"
│  Mar 22  Taxi                  €8.00       │  dimmed "will not close"
│                                             │
│  ☐ Also record as a transaction            │  Toggle (P8b — see §6)
│                                             │
│  [        Record settlement      ]          │
└────────────────────────────────────────────┘
```

## 4. Behaviour

- **From / To pickers** show only active members. Pre-fill `From = current
  user`, `To = member with the largest open debt to current user`.
- **Amount default** = `engine.openDebt(debtor: from, creditor: to)`. If
  the user types > openDebt, surface a non-blocking warning chip
  ("€{x} more than open debt; will be banked as credit"). Engine still
  accepts the larger amount.
- **Closes preview** runs the same FIFO walk the engine would and
  highlights the rows that the entered amount will fully close. Reactive
  to amount edits.
- **Same payer + recipient** → submit disabled ("Pick a different recipient").
- **Zero amount** → submit disabled.
- After save: sheet dismisses; toast `Settlement recorded`.

## 5. Validation

- `from != to`
- `amount > 0`
- both members are active
- if from is `.viewer`/`.child` (no `canSettle`), submit blocked with copy
  "{role} can't record settlements"

## 6. "Also record as a transaction" toggle (P8b — DEFERRED)

When on, calls `settleUp(..., materializeAsTransaction: true)`. The engine
creates a real `Transaction` representing the cash movement and stores its
id on `Settlement.linkedTransactionId` (P8.3 adds this field).

**Deferred decisions before P8b ships:**

1. Which `Category` should the materialized transaction belong to? Options:
   - Use a built-in `transfer` / `settlement` category (creates one if
     missing).
   - Let the user pick at save time.
   - Reuse the most-used category from the closed shares (probably noisy).
   *Proposal:* dedicated built-in `Settlement` category, auto-created.
2. Which `Account` does the cash move from / to? iOS has multi-account
   ledger; settlements need a from-account and to-account.
   *Proposal:* user picks at save time when toggle is on; default to first
   account each side.
3. If the user later `unsettle`s a settlement that materialized a
   transaction, do we delete that transaction? *Proposal:* tombstone the
   transaction (mark as deleted), don't hard-delete.

Until those land, the toggle is **hidden** in the UI and the engine call
passes `materializeAsTransaction: false`.

## 7. Microcopy

- Sheet title: `Settle up`
- CTA: `Record settlement`
- Closes header: `Closes`
- Over-amount warning: `€{x} more than open debt`
- Same-pair error: `Pick a different recipient`

## 8. Accessibility

- From/To pickers labeled `From member` / `To member`.
- Amount field uses currency input mode.
- "Closes" preview is an accessibility list — VoiceOver reads
  `"Will close: 2 expenses, total €18.00"`.

## 9. Engine handoff

```
HouseholdEngine.settleUp(
    fromMemberId: draft.fromId!,
    toMemberId:   draft.toId!,
    amount:       draft.amountCents,
    materializeAsTransaction: draft.materialize  // toggle from §6
) -> Settlement?
```

Engine FIFO walk + Settlement creation are already implemented in
`HouseholdManager.settleUp(fromUser:toUser:amount:note:)` and wrapped by
`HouseholdManager+Engine.swift`. The new sheet only drives the existing
call.

## 10. Files affected

### iOS
- Replace existing settle-up affordance (today inline in
  [balance/Views/Household/HouseholdOverviewView.swift](../balance/Views/Household/HouseholdOverviewView.swift)
  via a private `SettleUpSheet` struct) with a top-level
  `SettleUpSheet.swift` driven by `SettleUpDraft` (P8.2).
- Wire the call site at `pairBalancesCard` to the new sheet.

### macOS
- [Centmond/Sheets/HouseholdSettleUpSheet.swift](../../Centmond/Centmond/Sheets/HouseholdSettleUpSheet.swift)
  (already exists, 279 LoC). Refactor the body to match this spec.
  Replace direct `HouseholdService` calls with the `HouseholdEngine`
  surface once macOS conformance lands.

---

**Sign-off checklist:**

- [ ] §3 anatomy approved
- [ ] §4 behaviour approved
- [ ] §6 P8b deferred decisions approved (or alternatives chosen)
- [ ] §7 microcopy approved
