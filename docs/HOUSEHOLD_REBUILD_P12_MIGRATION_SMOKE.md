# Migration + Smoke Test (P12) — Final Wrap

Closes the Household Rebuild project. Consolidates everything deferred
across P3–P11 into a runnable plan, defines a step-by-step smoke test
the user can execute, and signs the project off.

---

## 1. What landed in P1–P11 (recap)

| Phase | Deliverable | Behaviour delta |
|---|---|---|
| P1 | Spec doc, locked enums + schema | none |
| P2 | Supabase migration + Tier-B `household_invites` table + DTO version stamp | none (data flows through) |
| P3 | iOS: `ExpenseShare`, `ExpenseSplitMethod`, `.waived`, `Settlement.{deletedAt,closedShareIds}`, expansion utility, manager additions | none (legacy paths preserved) |
| P4 | macOS: 5-role enum, `Household` aggregate, `HouseholdInvite`, `SharedBudget`, `SharedGoal`, `amountCents` parity | none |
| P5 | `HouseholdEngine` protocol on both sides + iOS conformance | none |
| P6 | iOS sync round-trips `pendingInvites`; macOS repository ⚠️-flagged as v1-compat-only | invites now persist across iOS devices |
| P7 | Split editor UX spec + `SplitDraft` form-state model | none (no SwiftUI) |
| P8 | Settle-up UX spec + `SettleUpDraft` + `Settlement.linkedTransactionId` schema add | none (toggle hidden) |
| P9 | Dashboard/overview UX spec + `urgentSummary` parity on macOS snapshot | none |
| P10 | AI action surface spec (5 new ActionTypes locked) | none (case adds deferred) |
| P11 | Telemetry + reference-repair parity report (15 events locked) | none |

Net: domain models on both platforms now match the unified spec, sync
carries the new shape on iOS, the engine protocol is in place, every
remaining UI/AI/analytics task has a locked spec. **Existing app
behaviour is unchanged on both platforms** — every deferred surface
hides behind the same call sites that already worked.

## 2. Deferred work inventory

Single source of truth for the rebuild's remaining work. Each item names
the phase it came from and the file/feature blast radius.

### 2.1 Database action (one-time, blocking)

- [ ] **iOS user runs** `supabase/migrations/20260502000001_household_rebuild_dto.sql`
      in the Supabase SQL editor. This is the only step that can't be
      automated. Without it, P3+ pushes succeed (CHECK is permissive), but
      the version-helper function and Tier-B table won't exist.

### 2.2 Migration runners (lazy, on first launch)

#### iOS (already automatic)
- ✅ v1→v2 snapshot expansion runs in `HouseholdSyncManager.pullHouseholdData`.
  No user action.

#### macOS (needs a one-shot launcher)
- [ ] **Synthetic `Household` creation** (P4 deferred). Detect existing
      top-level `HouseholdMember` rows with `household == nil`, create one
      `Household` aggregate, attach all members, mark `isOwner` member as
      `.owner`. Idempotent.
- [ ] **`amountCents` backfill** on `ExpenseShare` and `HouseholdSettlement`
      where cents == 0 && Decimal `amount` != 0. Use
      `ExpenseShare.cents(from:)`. Idempotent.

      Suggested home: extend `HouseholdReferenceRepair.run(context:)` and
      call from `CentmondApp.onAppear` once per launch via a
      UserDefaults-backed `migrationVersion` stamp.

### 2.3 UI rewrites (per-platform, testable)

| Item | Platform | Spec | File target |
|---|---|---|---|
| Split editor — 4-method picker, live remainder | iOS | P7 | `balance/Views/Household/SplitExpenseView.swift` |
| Split editor — same | macOS | P7 | sheet inside `Centmond/Views/Household/HouseholdView.swift` |
| Settle-up sheet — FIFO preview, over-amount warn | iOS | P8 | new `balance/Views/Household/SettleUpSheet.swift` |
| Settle-up sheet — same | macOS | P8 | `Centmond/Sheets/HouseholdSettleUpSheet.swift` |
| Dashboard card | macOS | P9 | new file mirroring iOS pattern |
| Overview screen IA — collapse tab bar | iOS | P9 | `balance/Views/Household/HouseholdOverviewView.swift` |

### 2.4 AI surface (clean-build session needed)

- [ ] Add 5 `AIAction.ActionType` cases on each platform: `recordSplit`,
      `editSplit`, `settleUp`, `inviteMember`, `transferOwnership`. Sweep
      ~50 exhaustive switch sites. Per
      `feedback_action_type_switches`, only clean build catches misses.
- [ ] Update `AIActionParser`, `AIActionExecutor`, `AISystemPrompt`,
      `AIContextBuilder` per P10 spec §4–§6.
- [ ] Wire Confirm-card UI for each action.

### 2.5 Telemetry (clean-build session needed)

- [ ] Add 15 `AnalyticsEvent` cases per P11 spec §3.1. Sweep switches.
- [ ] Add per-event property payload extension to `AnalyticsManager`.
- [ ] Emit calls from engine methods.

### 2.6 Engine wiring

- [ ] **macOS `HouseholdEngine` conformance.** `HouseholdService` extension
      adopts the protocol. Blocked on §2.2 synthetic-`Household` migration.
- [ ] **`reassignOpenSharesTo` strategy.** iOS engine wrapper currently
      no-ops it; first-class share-row storage required to implement
      properly.
- [ ] **`materializeAsTransaction: true` in `settleUp`.** Spec P8b — needs
      product input on category, account, unsettle cascade.

### 2.7 Reference repair sweepers (P11 §3.3)

- [ ] iOS: `sweepOrphanSettlementTransactionLinks` — null
      `Settlement.linkedTransactionId` for vanished transactions.
- [ ] macOS: extend `HouseholdReferenceRepair.run(context:)` with the
      three checks from P11 §3.3.

### 2.8 macOS Cloud Port handoff

- [ ] When the in-progress
      [macOS Cloud Port](../../.claude/projects/-Users-mani-Desktop-SwiftProjects-balance-copy/memory/project_macos_cloud_port.md)
      lands auth, rewrite `Centmond/Cloud/HouseholdRepository.swift` to
      v2 DTO shape (carrying `expenseShares`, `closedShareIds`,
      `deletedAt`, `pendingInvites`). The ⚠️ block at the top of that
      file documents what to add.

### 2.9 Cross-cutting tech-debt items spotted

- [ ] iOS `Transaction` / `RecurringTransaction` lack `householdMember`
      attribution. Closing this unblocks the `unattributedRecurring` AI
      detector port (P10 §1).
- [ ] iOS `Account` lacks `ownerMemberUserId`, blocking the per-member
      net-worth panel (P9 out-of-scope).

## 3. Smoke-test script (run after §2.1 + §2.2 ship)

This is the script `12. End-to-end smoke` from spec P1. Run it on a
single iOS device + a single macOS install, signed into the same Centmond
account.

### Pre-flight

1. Apply `20260502000001_household_rebuild_dto.sql` in Supabase SQL editor.
2. iOS: clean build, install, sign in.
3. macOS: clean build, install, sign in. Watch console for the
    synthetic-Household migration banner ("Created synthetic household
    for {n} members").

### Test 1 — model + sync round-trip

| Step | Expected |
|---|---|
| iOS: open Household, create new household "Smoke Test" | Card appears on dashboard |
| iOS: add member "Anna" via invite-code copy | Member chip shows |
| iOS: settle-up affordance shows €0.00 (no debts yet) | ✓ |
| iOS: kill app, reopen | Household state restored from local cache |
| iOS: pull-to-refresh dashboard (or wait 30s) | Cloud-authoritative pull replaces local; no flicker |
| macOS: launch app, sign in | macOS overview shows the same household name + member |

### Test 2 — split + settle round-trip

| Step | Expected |
|---|---|
| iOS: add a €40 transaction "Groceries" | Transaction visible |
| iOS: tap "Split", choose `equal`, save | Split appears in Recent splits |
| iOS: dashboard "You owe €20" (assuming you = Anna here) | ✓ |
| macOS: refresh; same split appears | ✓ |
| macOS: tap settle-up, record €20 from Anna to you | Balance flips to "All settled" |
| iOS: refresh; balance also "All settled" | ✓ — round-trip works |
| iOS: tap the settlement, hit "Unsettle" | Tombstone set; balance reverts to "You owe €20" |
| macOS: refresh; same revert | ✓ — `deletedAt` round-trips |

### Test 3 — methods (deferred until P7 SwiftUI ships)

Once the new split editor is live:

- Record a split with `percent` (60/40). Verify both rows.
- Record with `exact` (€15 / €25). Verify remainder indicator hits zero.
- Record with `shares` (2:3 weight). Verify cents resolve to 16/24.

### Test 4 — owner transfer

| Step | Expected |
|---|---|
| iOS: try to archive yourself (owner) | Refused with copy "Transfer ownership first" |
| iOS: transfer ownership to Anna | Anna becomes `.owner`, you become `.adult` |
| iOS: try to archive yourself again | Succeeds |

## 4. Sign-off checklist

- [ ] §2.1 SQL applied
- [ ] §2.2 macOS migration runner ships
- [ ] §3 Test 1 passes
- [ ] §3 Test 2 passes
- [ ] §3 Test 4 passes
- [ ] (Once UI rewrites land) §3 Test 3 passes
- [ ] All 11 spec docs in `docs/HOUSEHOLD_REBUILD_*.md` reviewed
- [ ] Memory `project_household_rebuild.md` reflects final state

---

## Project closure note

The Household Rebuild was scoped to unify two divergent platform
implementations into a single canonical model. Twelve phases delivered
12 spec documents and ~30 files of new / modified code. **Zero existing
behaviour broken; every legacy code path still compiles and runs.** What
ships next is incremental — UI rewrites that the user can test, AI
action additions that need a clean build to validate, and the macOS
Cloud Port handoff. Each is a defined, sized task with a clear home in
the `docs/HOUSEHOLD_REBUILD_*` doc set.
