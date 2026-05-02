# Reference Repair + Telemetry — Parity Report (P11)

Audit of both platforms' housekeeping layers against
`HOUSEHOLD_REBUILD_P1_SPEC.md` §8 (telemetry) and §6.2 (archive +
reference repair).

> Status: **DRAFT — pending sign-off**.
> Implementation deferred to a clean-build session, same rationale as P10.

---

## 1. Telemetry: spec §8 vs reality

Spec locks **14 event names**. Today both platforms emit a tiny subset
through different layers — and the two platforms don't even agree on
what the layer *is*.

### 1.1 iOS

`AnalyticsManager` (typed enum) emits:

| Today | Spec name | Status |
|---|---|---|
| `household_created` | `household.create` | rename |
| `household_joined` | n/a (not in spec) | keep, repurpose for invite redemption |
| `split_expense_added` | `household.split.record` | rename |

`HouseholdTelemetry` (UserDefaults counters):
- `splitsThisWeek`, `settlementsThisWeek` — local-only counters used by
  the dashboard "stats" chip. NOT sent to analytics. Keep as-is.

**Gap:** 12 of 14 spec events not emitted: `household.delete`,
`household.member.add`, `household.member.archive`, `.restore`,
`household.invite.regenerate`, `.split.edit`, `.split.delete`,
`household.settle.create`, `.settle.unsettle`, `household.budget.upsert`,
`household.goal.upsert`, `.goal.contribute`, plus the spec addition
`household.owner.transfer`, plus `household.snapshot.compute` (perf).

### 1.2 macOS

No `AnalyticsManager` analogue today (offline-only stack).
`HouseholdTelemetry` matches iOS for the local counters; adds
`attributionCoveragePercent` analytics helper (returns the % of
transactions with a `householdMember` set — used by the dashboard).

**Gap:** 14 of 14 spec events not emitted. macOS analytics integration
is gated on the in-progress macOS Cloud Port (per
`project_macos_cloud_port`).

## 2. Reference repair: spec §6.2 vs reality

Spec calls for `archiveMember(strategy:)` to handle open shares via
reassign / waive / fail. P5.2 wired this on iOS.

### 2.1 iOS

Existing sweepers:
- `sweepOrphanSplitExpenses(knownTransactionIds:)` — drops splits whose
  parent tx no longer exists.
- `sweepOrphanSettlements()` — drops settlements that reference vanished
  members. Already wired into `ContentView.loadUserData`.

**New gap from P3:** `expenseShares` is derived from `splitExpenses` via
`rebuildShares()`, so orphan shares can't exist by construction. ✓ Safe.

**New gap from P8.3:** `Settlement.linkedTransactionId` may point to a
transaction that the user later deletes outside the household flow. Needs
a sweeper: any settlement whose `linkedTransactionId` no longer resolves
should null the field (don't tombstone — the settlement record is still
valid, just unlinked).

### 2.2 macOS

`HouseholdReferenceRepair.run(context:)` (64 LoC). Today fixes orphan
`ExpenseShare.parentTransaction` and orphan `HouseholdSettlement.linkedTransaction`.
SwiftData's `.nullify` rule handles most of the work; the static method
just runs a final consistency pass.

**New gap from P4:**
- After the synthetic-`Household` migration runs, any `HouseholdMember`
  with `household == nil` should be re-attached or archived. Sweeper.
- `ExpenseShare` rows where `amountCents == 0 && amount != 0` need a
  one-time backfill. Idempotent.
- `HouseholdSettlement.amountCents` — same as above.

## 3. Harmonization plan

### 3.1 Telemetry events to add (iOS, this session deferred)

```swift
// AnalyticsEvent enum additions (rawValue in parens)
case householdDeleted                ("household.delete")
case householdMemberAdded            ("household.member.add")
case householdMemberArchived         ("household.member.archive")
case householdMemberRestored         ("household.member.restore")
case householdOwnerTransferred       ("household.owner.transfer")
case householdInviteRegenerated      ("household.invite.regenerate")
case householdSplitRecorded          ("household.split.record")
case householdSplitEdited            ("household.split.edit")
case householdSplitDeleted           ("household.split.delete")
case householdSettleCreated          ("household.settle.create")
case householdSettleUnsettled        ("household.settle.unsettle")
case householdBudgetUpserted         ("household.budget.upsert")
case householdGoalUpserted           ("household.goal.upsert")
case householdGoalContributed        ("household.goal.contribute")
// Performance — sample at 1% (spec §8 "sampled")
case householdSnapshotComputed       ("household.snapshot.compute")
```

Existing `householdCreated` raw value changes from `"household_created"`
→ `"household.create"`. `splitExpenseAdded` deprecated; emit
`householdSplitRecorded` instead. Existing `householdJoined`
(`"household_joined"`) kept as-is (member redemption flow, distinct from
spec events).

### 3.2 Common properties (per spec §8)

Every event sends:
- `householdId: UUID`
- `memberCount: Int`
- `actorRole: HouseholdRole.rawValue`
- `platform: "ios" | "macos"`

iOS `AnalyticsManager` doesn't currently support per-event property
payloads — needs a small extension. macOS would need analytics
infrastructure entirely (gated on Cloud Port).

### 3.3 Reference repair sweepers to add

iOS:
- `sweepOrphanSettlementTransactionLinks(knownTransactionIds:)` — null
  `Settlement.linkedTransactionId` when the tx is gone. Run alongside the
  existing two sweepers in `ContentView.loadUserData`.

macOS:
- Extend `HouseholdReferenceRepair.run(context:)`:
  - Re-attach `HouseholdMember.household == nil` to the synthetic root
    when one exists.
  - Backfill `ExpenseShare.amountCents` from `amount` when zero & non-zero.
  - Backfill `HouseholdSettlement.amountCents` similarly.

### 3.4 Implementation sequencing

When this ships, do it in this order on iOS (each step is a separate PR
or commit; clean build after each):

1. Add `AnalyticsEvent` cases + raw values. Sweep all switch sites.
2. Add per-event property extension to `AnalyticsManager`.
3. Wire engine-method emit calls (from `HouseholdManager+Engine.swift`).
4. Add the linked-transaction sweeper.
5. Run a clean build, fix latent compile errors per
   `feedback_clean_build_imports`.

macOS sequencing waits for the Cloud Port before steps 1–3 even make
sense. Step 4 (repair sweepers) can ship independently — pure model
hygiene, no analytics dep.

## 4. Out of scope for P11

- Analytics dashboard / admin-side queries (consumes the events but
  isn't part of the rebuild).
- Funnel definitions ("what % of users that create a household record
  their first split within 7 days") — that's a product analytics task
  layered on top of the harmonized event names.
- Real-time event streaming (we use batched sends; spec doesn't require
  realtime).

---

**Sign-off checklist:**

- [ ] §3.1 event name + raw value list approved
- [ ] §3.2 common-property contract approved
- [ ] §3.3 repair sweeper additions approved
