# Household AI Surface — Spec (P10)

Locks the household-related AI action types and detectors across iOS and
macOS. **Implementation deferred** — adding `AIAction.ActionType` cases
requires sweeping 50 switch sites across the two AI codebases, which per
[Action Type Switch Sweep](../../../.claude/projects/-Users-mani-Desktop-SwiftProjects-balance-copy/memory/feedback_action_type_switches.md)
fails silently at clean-build time. That sweep belongs in a session where
the user can run a clean build to verify.

> Status: **DRAFT — pending sign-off**.

---

## 1. Inverted finding (vs the original P1 plan)

The P1 plan said "Port AIHouseholdInsightDetectors to macOS." That's
backwards: macOS already has
[HouseholdInsightDetectors.swift](../../Centmond/Centmond/AI/Intelligence/HouseholdInsightDetectors.swift)
(219 LoC, all 4 detectors). iOS
[AIHouseholdInsightDetectors.swift](../balance/AI/AIHouseholdInsightDetectors.swift)
(187 LoC) is the port — and missing the `unattributedRecurring` detector
because iOS `Transaction` / `RecurringTransaction` lack the
`householdMember` field that macOS has.

**Correction:** the gap to close is on iOS, and only when iOS gets a
member-attribution field on its `Transaction` model. Until then, iOS keeps
3 detectors, macOS keeps 4. Document and move on.

## 2. Action types to add

Same five new cases on both platforms. Names and rawValues locked; params
follow.

| Swift case | rawValue | Confirm card | Audit |
|---|---|---|---|
| `recordSplit` | `"record_split"` | yes | yes |
| `editSplit` | `"edit_split"` | yes | yes |
| `settleUp` | `"settle_up"` | yes | yes |
| `inviteMember` | `"invite_member"` | yes | yes |
| `transferOwnership` | `"transfer_ownership"` | yes | yes |

Existing related cases stay as-is:
- iOS `splitTransaction` / macOS `splitTransaction` already exist; new
  `recordSplit` is the engine-aware variant. The old one becomes a thin
  alias that emits a `recordSplit` action under the hood.
- iOS `assignMember` / macOS `assignMember` stay (per-transaction member
  attribution, distinct from household-level mutations).

### 2.1 Param schemas

```jsonc
// record_split
{ "transaction_id": "uuid",
  "total_cents": 1234,
  "paid_by_member_id": "uuid",
  "method": "equal" | "percent" | "exact" | "shares",
  "lines": [
    { "member_id": "uuid", "value": 50.0 }
  ] }

// edit_split — same shape as record_split

// settle_up
{ "from_member_id": "uuid",
  "to_member_id": "uuid",
  "amount_cents": 1800,
  "note": "optional",
  "materialize_as_transaction": false }

// invite_member
{ "display_name": "Anna",
  "email": "anna@…",  // optional
  "role": "owner" | "partner" | "adult" | "child" | "viewer",
  "expires_in_days": 7 }

// transfer_ownership
{ "to_member_id": "uuid" }
```

`uuid` fields refer to `HouseholdMember.id`, not auth uid. The AI must
have member ids in context (snapshot+roster injection — see §4).

## 3. Confirm-card requirements (per spec §9 Q5)

All five gate behind Confirm/Reject. Card body must show:
- Action verb + concise summary ("Settle €18 from Brian to Anna")
- All affected member display names
- The amount (currency-formatted)
- For `record_split` / `edit_split`: the per-member breakdown
- Reject button reverts to chat input; Confirm calls the engine method.

This matches the [Confirm Every Action](../../../.claude/projects/-Users-mani-Desktop-SwiftProjects-balance-copy/memory/feedback_confirm_every_action.md)
hard rule.

## 4. Context injection

Both platforms' `AIContextBuilder` should add a `household` block when a
household exists and is non-empty:

```
HOUSEHOLD
  name: "Our Household"
  current_member_id: "<uuid>"
  members:
    - { id: "<uuid>", name: "Anna",   role: owner,   active: true }
    - { id: "<uuid>", name: "Brian",  role: partner, active: true }
  open_balances:
    - { from: "<uuid>", to: "<uuid>", cents: 1800 }
  unsettled_count: 3
  shared_budget_this_month: 40000   # cents
```

The current member id is the user's own member row (resolved from
`auth.uid` on iOS, from the `isOwner` member on macOS today). AI uses
ids when emitting actions; user-facing summary uses names.

## 5. System-prompt additions

Both platforms' `AISystemPrompt.swift` get a paragraph:

> When the user has a household with multiple members, you can record
> splits, settle up between members, invite a new member, or transfer
> ownership. Always emit a Confirm card. Use member ids from the
> HOUSEHOLD context block, never names. If a member is archived, refuse
> the action and ask the user to restore them first.

## 6. Intent router

macOS intent router needs to recognise household phrases:
- "split this with X / split equally" → `recordSplit`
- "settle up with X" / "I paid X back" → `settleUp`
- "invite X to the household" → `inviteMember`
- "make X the owner" → `transferOwnership`

iOS already has fragments; macOS gains the same trigger set.

## 7. Detector parity gap (deferred)

iOS `unattributedRecurring` detector requires a `householdMember`
relationship on `Transaction` and `RecurringTransaction`. Adding that is
a separate phase (it touches the Transaction model, the add/edit flows,
the import pipeline, and the AI context builder). Not in P10's scope.

## 8. Implementation checklist (when this ships)

For each of the 5 new ActionType cases, on each platform:

1. Add the enum case in `AIModels.swift`.
2. Run `grep -rn "switch.*\.type\b" balance/AI balance/Views/AI` (and
   macOS equivalent). Add a branch in every exhaustive switch.
3. Update `AIActionParser.swift` to recognise the new rawValue + param
   shapes from the LLM JSON output.
4. Update `AIActionExecutor.swift` to call `HouseholdEngine` methods.
5. Update `AISystemPrompt.swift` with the §5 paragraph + JSON examples.
6. Update `AIContextBuilder.swift` to inject the §4 block.
7. Add intent-router triggers (macOS only — iOS already handles via
   prompt).
8. Add Confirm-card UI for each (iOS extends ActionCard; macOS extends
   the equivalent).
9. **Run a clean build** and verify no compile errors. Per
   `feedback_clean_build_imports`, latent bugs only surface there.

## 9. Out of scope for P10

- AI proactive nudges that suggest splits / settle-ups (lives in
  `AIInsightEngine`'s nudge layer, separate phase).
- Receipt-scan auto-split (the receipt scanner stays user-driven for v1).
- Voice triggers (`"Hey Centmond, settle up"`).

---

**Sign-off checklist:**

- [ ] §2 action names + rawValues approved
- [ ] §2.1 param schemas approved
- [ ] §4 context block format approved
- [ ] §5 system-prompt paragraph approved
