# Household System — Unified Spec (P1)

Source-of-truth spec for the iOS + macOS household rebuild. Lock this before
writing any code. Anything not in here is undefined and should be raised before
implementation.

> Status: **DRAFT — pending sign-off**.
> Companion plan: see chat history "Household System — Unification Rebuild Plan".

---

## 1. Goals

1. One household domain model that compiles and persists on both iOS (Codable +
   Supabase + UserDefaults) and macOS (SwiftData mirror of the same shape).
2. Money in `Int` cents everywhere. No `Decimal` in the household domain.
3. Per-share row split mechanic (macOS shape) — strictly more expressive than
   the iOS `SplitRule` aggregate.
4. Multi-user is a v2 concern. v1 ships single-user households on both
   platforms with the schema in place for v2.

## 2. Non-goals (v1)

- Cross-user invite acceptance over the wire (Supabase JSONB layout blocks
  cross-user reads — re-enable in a later phase).
- Per-group budget envelopes (`HouseholdGroup` is descriptive only).
- Multi-currency split lines (parent transaction currency wins).
- Importing third-party splitwise/tricount data.

## 3. Entities

All identifiers are `UUID` unless noted. All amounts are `Int` cents. All dates
are `Date` (ISO-8601 in JSON).

### 3.1 Household (aggregate root)

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `name` | String | default "Our Household" |
| `createdBy` | String | userId of creator (auth uid) |
| `inviteCode` | String | 6-char `[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]` |
| `members` | [HouseholdMember] | embedded; non-empty |
| `groups` | [HouseholdGroup] | embedded; may be empty |
| `createdAt` | Date | |
| `updatedAt` | Date | bumped on any mutation |

Invariants:
- Exactly one member with `role == .owner`. Owner cannot be archived.
- `inviteCode` must be unique per household for the lifetime of the row;
  regeneration is allowed and revokes old codes.

### 3.2 HouseholdMember

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | local member identity (stable across rename) |
| `userId` | String | auth uid; empty string for unlinked members |
| `displayName` | String | required, max 60 chars |
| `email` | String | optional, may be `""` |
| `avatarColorHex` | String | 6-char hex, no `#`; default `"3B82F6"` |
| `role` | HouseholdRole | see §4 |
| `defaultSharePercent` | Double? | 0…100; nil means "no default" |
| `joinedAt` | Date | |
| `sharedAccountIds` | [UUID]? | nil = share all; `[]` = none |
| `shareTransactions` | Bool | default `true` |
| `isActive` | Bool | archived members hidden from pickers |
| `archivedAt` | Date? | set iff `isActive == false` |
| `groupIds` | [UUID] | references HouseholdGroup.id |

Invariants:
- `archivedAt != nil ⇔ isActive == false`.
- A member with open (unsettled) shares cannot be archived without a
  reassign-or-waive prompt (engine-enforced, §6.3).

### 3.3 HouseholdGroup

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `name` | String | required, max 40 chars |
| `colorHex` | String | 6-char hex, no `#`; default `"8B5CF6"` |
| `memberIds` | [UUID] | denormalized; mirror of `HouseholdMember.groupIds` |
| `createdAt` | Date | |

### 3.4 ExpenseShare

One row per member who owes a portion of a transaction. Replaces iOS
`SplitExpense` aggregate.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `householdId` | UUID | |
| `transactionId` | UUID | parent ledger transaction |
| `memberId` | UUID | HouseholdMember.id |
| `paidByMemberId` | UUID | who fronted the cash |
| `amount` | Int | cents this member owes (≥ 0) |
| `percent` | Double? | 0…100; null unless `method == .percent` |
| `method` | ExpenseSplitMethod | see §4 |
| `status` | ShareStatus | see §4 |
| `createdAt` | Date | |
| `settledAt` | Date? | set iff `status == .settled` |
| `settlementId` | UUID? | links to Settlement that closed it |

Invariants:
- For a given `transactionId`, `Σ amount across shares == transaction.total`.
- The payer's own share row exists with `amount = transaction.total - othersOwed`
  and `status = .settled` at creation (they don't owe themselves).
- `status == .waived` means owed amount is forgiven; it counts toward "settled"
  for balance math.

### 3.5 Settlement

A cash event between two members.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `householdId` | UUID | |
| `fromMemberId` | UUID | who pays |
| `toMemberId` | UUID | who receives |
| `amount` | Int | cents |
| `note` | String | default `"Settlement"` |
| `date` | Date | |
| `linkedTransactionId` | UUID? | optional ledger entry materializing the cash move |
| `closedShareIds` | [UUID] | which `ExpenseShare`s this settlement closed |
| `createdAt` | Date | |
| `deletedAt` | Date? | tombstone — `unsettle` sets this; balance math ignores rows where set |

Invariants:
- `fromMemberId != toMemberId`.
- `Σ amount of closedShares == amount` (FIFO matching, see §6.4).

### 3.6 SharedBudget

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `householdId` | UUID | |
| `monthKey` | String | `YYYY-MM` |
| `totalAmount` | Int | cents |
| `splitRule` | BudgetSplitRule | see §4 |
| `categoryBudgets` | [String: Int] | `Category.storageKey` → cents |
| `createdAt` / `updatedAt` | Date | |

Unique on `(householdId, monthKey)`.

### 3.7 SharedGoal

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `householdId` | UUID | |
| `name` | String | required, max 60 |
| `icon` | String | SF Symbol; default `"star.fill"` |
| `targetAmount` | Int | cents, > 0 |
| `currentAmount` | Int | cents, ≥ 0 |
| `createdBy` | String | userId |
| `createdAt` / `updatedAt` | Date | |

Derived (not stored): `progress`, `progressPercent`, `remainingAmount`,
`isCompleted`.

### 3.8 HouseholdInvite

Stored row, but cross-user redemption is **deferred** in v1.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `householdId` | UUID | |
| `invitedBy` | String | userId |
| `inviteCode` | String | matches Household.inviteCode at issue time |
| `role` | HouseholdRole | role assigned to the joiner |
| `status` | InviteStatus | pending / accepted / declined / expired |
| `createdAt` | Date | |
| `expiresAt` | Date | default +7 days |

## 4. Enums (locked)

```
HouseholdRole       = owner | partner | adult | child | viewer
ExpenseSplitMethod  = equal | percent | exact | shares
ShareStatus         = owed | settled | waived
BudgetSplitRule     = equal | percent(Double) | paidBy(memberId: UUID)
InviteStatus        = pending | accepted | declined | expired
```

Permission matrix:

| Capability | owner | partner | adult | child | viewer |
|---|---|---|---|---|---|
| canEditBudgets | ✅ | ✅ | ✅ |  |  |
| canAddExpenses | ✅ | ✅ | ✅ | ✅ |  |
| canManageMembers | ✅ |  |  |  |  |
| canSettle | ✅ | ✅ | ✅ |  |  |

`guest` (macOS legacy) maps to `viewer` on migration.

## 5. Wire format / Supabase schema

Two-tier strategy:

**Tier A — single-user (v1, ships day 1):** keep the existing
`household_state` JSONB blob, but with the new shape (snapshot DTO updated):

```jsonc
{
  "household": Household,
  "expenseShares":   [ExpenseShare],
  "settlements":     [Settlement],
  "sharedBudgets":   [SharedBudget],
  "sharedGoals":     [SharedGoal],
  "invites":         [HouseholdInvite]
}
```

RLS: `owner_id == auth.uid()`. Cross-user reads blocked.

**Tier B — multi-user (deferred phase):** add row-per-entity tables
`household_members`, `expense_shares`, `household_settlements`, etc., with RLS
predicate `auth.uid() ∈ household.member_user_ids`. JSONB blob becomes a
read-through cache. Migration runs server-side from blob → rows.

Naming: snake_case on the wire, camelCase in Swift. JSON encoder uses
`.convertToSnakeCase`.

## 6. Engine contracts

The household engine on each platform must expose this surface, with identical
semantics. iOS implementation lives in `HouseholdManager`, macOS in a rewritten
`HouseholdService`.

### 6.1 Lifecycle

- `createHousehold(name, ownerDisplayName) -> Household`
- `deleteHousehold()` — purges local + cloud snapshot.
- `regenerateInviteCode() -> String`

### 6.2 Members

- `addMember(displayName, role, …) -> HouseholdMember`
- `updateMember(id, mutator) -> HouseholdMember`
- `archiveMember(id, strategy: ArchiveStrategy)`
  - strategies: `.reassignOpenSharesTo(memberId)`, `.waiveOpenShares`, `.failIfOpenShares`
- `restoreMember(id)`
- `transferOwnership(toMemberId)` — required before owner self-archive; old
  owner becomes `.adult`, target becomes `.owner`. Owner-only.

### 6.3 Splits

- `recordSplit(transactionId, totalCents, paidByMemberId, method, lines) -> [ExpenseShare]`
  - `lines` is an array of `(memberId, valueByMethod)` where `valueByMethod`
    is `Int cents` for `.exact`, `Double percent` for `.percent`, `Int weight`
    for `.shares`, ignored for `.equal`.
  - Engine validates `Σ amount == totalCents` (penny-rounding remainder goes to
    the payer), persists rows, returns them.
- `editSplit(transactionId, …)` — replaces all shares atomically.
- `deleteSplit(transactionId)` — removes shares; settlements that referenced
  them get `closedShareIds` updated and may go negative — surfaced as a repair
  job.

### 6.4 Settlement

- `settleUp(fromMemberId, toMemberId, amount, materializeAsTransaction: Bool) -> Settlement`
  - FIFO across `from`'s open shares owed to `to`, oldest first.
  - Partial settlement is allowed: a share whose remaining is larger than the
    settlement amount stays `owed` with `amount` reduced; the consumed slice
    becomes a settled child share (engine implementation detail).
- `unsettle(settlementId)` — reverses, restoring share statuses.

### 6.5 Snapshot

`snapshot() -> HouseholdSnapshot` (read-only, used by dashboard + AI):

| Field | Type | Notes |
|---|---|---|
| `memberCount` | Int | active only |
| `hasPartner` | Bool | any member with role `.partner` |
| `sharedSpending` | Int | cents this month tied to shares |
| `sharedBudget` | Int | cents this month (0 = unset) |
| `budgetUtilization` | Double? | nil if no budget |
| `isOverBudget` | Bool | |
| `unsettledCount` | Int | shares with status `.owed` |
| `unsettledAmount` | Int | sum cents |
| `youOwe` | Int | cents current user owes others |
| `owedToYou` | Int | cents others owe current user |
| `activeSharedGoalCount` | Int | |
| `topGoal` | SharedGoal? | highest progress, incomplete |
| `totalGoalProgress` | Int | 0…100 |
| `pendingInviteCount` | Int | |

## 7. Migration

### 7.1 iOS

Old: `SplitExpense` rows with `SplitRule` enum (incl. `paidByMe`,
`paidByPartner`, `percentage(Double)`).

Mapping at first launch on the new build:

| Old `SplitRule` | New shares |
|---|---|
| `.equal` | one row per member, `method = .equal`, equal split + remainder to payer |
| `.custom` | one row per non-zero `MemberSplit`, `method = .exact` |
| `.paidByMe` | one row, payer owes full amount, others owe 0 (`method = .exact`) |
| `.paidByPartner` | symmetric |
| `.percentage(p)` | rows for payer (p%) and one other (100-p%), `method = .percent` |

Old `Settlement.relatedExpenseIds` → new `closedShareIds` (need to fan out from
expense → share rows the migration produced).

### 7.2 macOS

Old: SwiftData `@Model` `HouseholdMember`, `HouseholdGroup`, `ExpenseShare`,
`HouseholdSettlement`. No `Household` aggregate, no invites, no shared
budget/goal.

Mapping:
- Create one synthetic `Household` row for every existing local store on first
  launch. Copy all members in. Mark first `isOwner` member as `.owner`, others
  as `.adult` (or preserve `.role` if set).
- `HouseholdRole.guest` → `.viewer`.
- `ExpenseShare.amount: Decimal` → `Int` cents (`× 100` rounded half-even).
  Reject NaN / negative; log to a one-time repair report.
- `HouseholdSettlement.amount: Decimal` → `Int` cents identically.
- Add `paidByMemberId` to existing shares by reading their parent
  `Transaction`'s payer field. If the transaction has no household payer
  recorded, fall back to the household owner and surface a repair task.

### 7.3 Failure modes

- Migration is idempotent: running twice on a migrated store is a no-op.
- A failed migration leaves the old store untouched and surfaces a recovery
  banner. Users can retry from Settings.

## 8. Telemetry (locked event names)

```
household.create
household.delete
household.owner.transfer
household.member.add
household.member.archive
household.member.restore
household.invite.regenerate
household.split.record
household.split.edit
household.split.delete
household.settle.create
household.settle.unsettle
household.budget.upsert
household.goal.upsert
household.goal.contribute
household.snapshot.compute  // perf, sampled
```

Properties on every event: `householdId`, `memberCount`, `actorRole`,
`platform = ios|macos`.

## 9. Open questions — RESOLVED 2026-05-02

1. **Owner role: distinguished.** Owner is the household creator (their
   `auth.uid` becomes `Household.createdBy`, role `.owner`). No specific email
   is hardcoded. Owner is the only role with `canManageMembers`. Owner cannot
   self-archive — must transfer ownership first. Engine method
   `transferOwnership(toMemberId:)` reassigns the role.
2. **Multi-currency splits: locked OUT.** Parent transaction currency wins
   for every share. No per-share currency override.
3. **Settlements: tombstone.** Settlement model gains `deletedAt: Date?`.
   `unsettle` sets the timestamp instead of deleting the row; balance math
   filters `deletedAt == nil`. Future activity log can surface the reversal
   history without a schema change.
4. **macOS `Transaction.payerMember`: EXISTS.** Reuse the existing
   `householdMember: HouseholdMember?` relationship on `Transaction` as the
   payer pointer for split transactions (it's already member-attribution —
   for a split, attribution == payer). No schema add in P4.
5. **AI Confirm-card surface: all writes.** `recordSplit`, `editSplit`,
   `deleteSplit`, `settleUp`, `unsettle`, `archiveMember`, `restoreMember`,
   `addMember`, `transferOwnership`, `regenerateInviteCode`,
   `upsertSharedBudget`, `upsertSharedGoal`, `contributeSharedGoal` all gate
   behind Confirm/Reject. Reads (`snapshot`, balances) flow without Confirm.
6. **`SharedGoal.contribute`: UserDefaults overlay.** Reuse the existing
   pattern from `feedback_goal_contribution_writes`. Revisit when the
   `goal_contributions` RLS fix lands.

### Schema deltas from resolutions

- `Settlement` adds `deletedAt: Date?` (§3.5).
- Engine surface adds `transferOwnership(toMemberId:)` (§6.2).

---

**Sign-off:**

- [x] Enums frozen (§4)
- [x] Schema fields frozen (§3) — plus `Settlement.deletedAt`
- [x] Open questions §9 resolved (2026-05-02)
- [x] Telemetry names approved (§8) — add `household.owner.transfer`
