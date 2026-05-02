# Dashboard Card & Overview — Unified UX Spec (P9)

Companion to the P1 / P7 / P8 specs. Locks how the household snapshot
renders on the home dashboard and on the dedicated overview screen across
iOS and macOS.

> Status: **DRAFT — pending sign-off**.

---

## 1. Goals

1. Both platforms render from the same `HouseholdSnapshot` struct (spec
   §6.5). No platform-specific fields.
2. Per the [One Accent Per Card](../../../.claude/projects/-Users-mani-Desktop-SwiftProjects-balance-copy/memory/feedback_one_accent_per_card.md)
   rule, the dashboard card uses one identity colour for content and blue
   for the CTA only.
3. Per the [Insight Banner No Buttons](../../../.claude/projects/-Users-mani-Desktop-SwiftProjects-balance-copy/memory/feedback_insight_banner_no_buttons.md)
   rule, no inline action pills on the card; the whole card taps into the
   overview.

## 2. Dashboard card anatomy

```
┌──────────────────────────────────────────────────┐
│  HOUSEHOLD                                       │  Section label
│  Anna · Brian · +2                       👁  ⚠   │  Member chips,
│                                                   │  alert dots
│  ──────────────────────────────────────────       │
│  You owe                              €18.00     │  Primary line
│  3 expenses to settle                             │  Secondary line
│  ──────────────────────────────────────────       │
│  March budget                  €240 / €400       │  Budget progress
│  ▰▰▰▰▰▰▰▱▱▱▱▱▱                  60%             │  Bar
│                                                   │
│  Tap to open                                      │  CTA hint
└──────────────────────────────────────────────────┘
```

Hidden when household is `nil`. Empty-state ("Invite your partner") shown
when `memberCount == 1`.

### 2.1 Field-to-snapshot mapping

| Card slot | Snapshot field | Empty when |
|---|---|---|
| Member chips | `memberCount` + first 3 names | always show |
| Primary line | `youOwe > 0 ? "You owe €X" : owedToYou > 0 ? "Owed to you €X" : "All settled"` | never |
| Secondary line | `unsettledCount` + " expenses to settle" | `unsettledCount == 0` |
| Budget progress | `sharedSpending`, `sharedBudget`, `budgetUtilization`, `isOverBudget` | `sharedBudget == 0` |
| Alert dot | `hasAlerts` | `hasAlerts == false` |

### 2.2 Tap target

- Whole card → push the Overview screen (§3).
- No inline buttons. No "Settle up" pill. No "Add member" pill.

## 3. Overview screen IA

Section order (top to bottom). Sections hide automatically when their
data source is empty (e.g. no shared budget set → section omitted).

1. **Header** — household name, member count, invite-code chip with copy
   button (owner only).
2. **Balances** — `youOwe` + `owedToYou` summary, then `openPairBalances`
   list (one row per debtor→creditor pair, biggest first). Tap any row →
   pre-filled `SettleUpSheet` (P8).
3. **Members** — active list with role badge, archived list collapsed by
   default. Tap → member detail / role-change. Owner-only "Add member"
   button at section end.
4. **Groups** — chips with colour swatches; tap → group detail. Hidden
   when no groups exist.
5. **Recent splits** — last 5 `splitExpenses` (legacy) or top
   `expenseShares` grouped by transactionId (when shares migrate to first-
   class). Tap → split detail / `SplitExpenseView` (P7) in edit mode.
6. **Settlements** — last 5 `settlements.filter { $0.isActive }` rows,
   newest first. Tap → row detail with "Unsettle" affordance.
7. **Shared budget** — month picker + per-category breakdown.
8. **Shared goals** — card per goal with progress bar.
9. **Pending invites** — list (`HouseholdInvite`). Hidden when empty.

## 4. Cross-platform delta

### iOS today
- [HouseholdDashboardCard](../balance/Views/Household/HouseholdDashboardCard.swift)
  (297 LoC) covers §2 mostly. Top-spender chip lives there; either keep
  or move into the overview's Members section.
- [HouseholdOverviewView](../balance/Views/Household/HouseholdOverviewView.swift)
  (1850 LoC) holds §3 today via a `HubTab` enum (overview / splits /
  settlements / members). Refactor target: collapse the tab bar into
  scroll-anchored sections so all data is visible by default; keep the
  tab bar only on iPhone where vertical scroll is heavy.

### macOS today
- [HouseholdView](../../Centmond/Centmond/Views/Household/HouseholdView.swift)
  (991 LoC) is one screen. No dashboard card analogue. Add a small
  `HouseholdDashboardCard` for the home screen mirroring §2.

## 5. Microcopy parity

Strings must match across platforms.

| Slot | Copy |
|---|---|
| Card label | `HOUSEHOLD` (uppercase, eyebrow) |
| Empty state | `Invite your partner to get started` |
| All settled | `All settled` |
| You owe | `You owe €{x}` |
| Owed to you | `Owed to you €{x}` |
| Settle hint | `{n} expenses to settle` (singular: `1 expense to settle`) |
| Budget label | `{Month} budget` |
| Over budget chip | `Over budget` |
| Tap hint | `Tap to open` |

## 6. Accessibility

- Whole card: `.accessibilityElement(children: .combine)`.
  VoiceOver announces: `"Household. You owe 18 euros. 3 expenses to
  settle. March budget 60 percent."`
- Member chips: `.accessibilityHidden(true)` (info already in combined
  label).
- Budget bar: `.accessibilityValue("\(percent) percent")`.

## 7. Out of scope for P9

- Per-member net-worth panel (separate phase, blocked on
  `Account.ownerMemberUserId` field).
- Settlement export / share to PDF.
- Activity log surfacing tombstoned settlements.

---

**Sign-off checklist:**

- [ ] §2 card anatomy approved
- [ ] §3 overview section order approved
- [ ] §5 microcopy approved
