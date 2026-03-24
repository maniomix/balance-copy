# Balance App — End-to-End Bug Analysis & Fix Plan

## Architecture Summary

```
Store (struct, Codable)           ← Single source of truth for transactions, budgets
  ├── transactions: [Transaction]
  ├── recurringTransactions: [RecurringTransaction]
  └── budgetsByMonth / categoryBudgetsByMonth

Singleton Managers (all @MainActor, ObservableObject):
  ├── ReviewEngine.shared         ← Detects spikes, duplicates, uncategorized
  ├── SubscriptionEngine.shared   ← Auto-detects recurring subscriptions
  ├── GoalManager.shared          ← CRUD goals via Supabase
  ├── HouseholdManager.shared     ← Split expenses, settlements (UserDefaults)
  ├── AccountManager.shared       ← Bank accounts via Supabase
  └── AuthManager.shared          ← Supabase auth
```

---

## BUG #1: Review Actions ("Flag It", "Looks Normal") Don't Persist

### Symptom
User taps "Flag It" or "Looks Normal" → sheet dismisses → but item reappears after switching months or restarting.

### Root Cause
**File:** `ReviewEngine.swift`

`resolve()` (line 181) marks the item as `.resolved` in memory but does **NOT** add its transaction key to `dismissedTransactionKeys`. When `analyze()` runs again, the detection algorithm creates **new** `ReviewItem` objects with **fresh UUIDs** for the same transactions. The merge logic keeps old resolved items by `id`, but the new items have different IDs and pass through the `dismissedTransactionKeys` filter — so duplicates appear.

Compare:
- `dismiss()` (line 188) → ✅ adds to `dismissedTransactionKeys` → persisted to UserDefaults
- `resolve()` (line 180) → ❌ only sets `.resolved` in memory → lost on re-analyze

### Fix

```swift
// ReviewEngine.swift — resolve() method (line 180)

// BEFORE:
func resolve(_ item: ReviewItem) {
    guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
    items[idx].status = .resolved
    items[idx].resolvedAt = Date()
    AnalyticsManager.shared.track(.reviewItemResolved(type: item.type.rawValue))
}

// AFTER:
func resolve(_ item: ReviewItem) {
    guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
    items[idx].status = .resolved
    items[idx].resolvedAt = Date()
    AnalyticsManager.shared.track(.reviewItemResolved(type: item.type.rawValue))

    // Persist so the same transactions aren't re-flagged
    let key = item.transactionIds.map { $0.uuidString }.sorted().joined(separator: "|")
    dismissedTransactionKeys.insert(key)
}
```

### Files Changed
| File | Change |
|------|--------|
| `balance/Manager/ReviewEngine.swift` | Add `dismissedTransactionKeys.insert(key)` to `resolve()` |

---

## BUG #2: Subscription Insight Banners Are Non-Interactive

### Symptom
"Missed Charge" and "Newly Detected" banners in Subscriptions overview show a chevron (">") but tapping them does nothing.

### Root Cause
**File:** `SubscriptionsOverviewView.swift`, lines 196-229

The insight banners are plain `HStack` views with a decorative chevron — no `Button`, no `NavigationLink`, no `onTapGesture`.

### Fix

```swift
// SubscriptionsOverviewView.swift — insightBanners (line 196)

// BEFORE:
@ViewBuilder
private var insightBanners: some View {
    if !engine.insights.isEmpty {
        VStack(spacing: 8) {
            ForEach(engine.insights) { insight in
                HStack(spacing: 10) {
                    Image(systemName: insight.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(insight.color)

                    Text(insight.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext)
                }
                .padding(12)
                .background(
                    insight.color.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(insight.color.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal)
    }
}

// AFTER:
@ViewBuilder
private var insightBanners: some View {
    if !engine.insights.isEmpty {
        VStack(spacing: 8) {
            ForEach(engine.insights) { insight in
                Button {
                    handleInsightTap(insight)
                    Haptics.light()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: insight.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(insight.color)

                        Text(insight.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.text)

                        Spacer()

                        // Show count
                        Text(insightCount(insight))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(insight.color)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    .padding(12)
                    .background(
                        insight.color.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(insight.color.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}

// Add these helper methods to SubscriptionsOverviewView:

private func handleInsightTap(_ insight: SubscriptionInsight) {
    switch insight {
    case .missedCharge:
        // Filter to show only active subs (missed charges are active subs past due)
        filterStatus = .active
    case .maybeUnused:
        filterStatus = .suspectedUnused
    case .priceIncreased:
        filterStatus = .active
    case .newlyDetected:
        filterStatus = .active
    default:
        filterStatus = nil
    }
}

private func insightCount(_ insight: SubscriptionInsight) -> String {
    switch insight {
    case .missedCharge: return "\(engine.missedChargeSubs.count)"
    case .maybeUnused: return "\(engine.unusedSubs.count)"
    case .priceIncreased: return "\(engine.priceIncreasedSubs.count)"
    case .newlyDetected:
        let count = engine.subscriptions.filter { $0.chargeHistory.count <= 3 && $0.isAutoDetected && $0.status == .active }.count
        return "\(count)"
    default: return ""
    }
}
```

### Files Changed
| File | Change |
|------|--------|
| `balance/Views/Subscriptions/SubscriptionsOverviewView.swift` | Wrap banners in Buttons, add helper methods |

---

## BUG #3: Subscription "In -16 days" Display

### Symptom
Upcoming renewal card shows "In -16 days" for overdue subscriptions (visible in screenshot).

### Root Cause
**File:** `SubscriptionsOverviewView.swift`, line 339

```swift
Text(days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days")
```
When `days` is negative (past due), it renders literally as "In -16 days".

### Fix

```swift
// SubscriptionsOverviewView.swift — renewalCard function (line 338)

// BEFORE:
if let days = sub.daysUntilRenewal {
    Text(days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days")
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(days <= 3 ? DS.Colors.warning : DS.Colors.subtext)
}

// AFTER:
if let days = sub.daysUntilRenewal {
    Text(days == 0 ? "Today" : days == 1 ? "Tomorrow" : days < 0 ? "\(abs(days))d overdue" : "In \(days) days")
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(days <= 3 ? DS.Colors.warning : DS.Colors.subtext)
}
```

Also fix in `SubscriptionsDashboardCard.swift` (line 91):
```swift
// BEFORE:
Text(days <= 0 ? "today" : days == 1 ? "tomorrow" : "in \(days)d")

// AFTER:
Text(days == 0 ? "today" : days == 1 ? "tomorrow" : days < 0 ? "\(abs(days))d overdue" : "in \(days)d")
```

### Files Changed
| File | Change |
|------|--------|
| `balance/Views/Subscriptions/SubscriptionsOverviewView.swift` | Handle negative days |
| `balance/Views/Subscriptions/SubscriptionsDashboardCard.swift` | Handle negative days |

---

## BUG #4: Goals — Create/Save Fails Silently

### Symptom
User taps "Create" on new goal → nothing happens, no error shown.

### Root Cause
**File:** `CreateEditGoalView.swift`, line 418

```swift
private func save() async {
    guard let userId = AuthManager.shared.currentUser?.uid else { return }  // ← SILENT FAIL
```

If the user's auth session expired or `currentUser` is nil, the save returns with zero feedback. The "Create" button stays enabled but nothing happens. Additionally, if GoalManager's Supabase call fails, `createGoal()` returns `false` but `save()` only calls `dismiss()` when `ok == true` — meaning the user is stuck on the form with no error indicator.

### Fix

```swift
// CreateEditGoalView.swift — save() function (line 417)

// BEFORE:
private func save() async {
    guard let userId = AuthManager.shared.currentUser?.uid else { return }
    isSaving = true
    // ... (rest of function)
    isSaving = false
}

// AFTER:
@State private var errorMessage: String?  // Add this @State property at line ~33

private func save() async {
    guard let userId = AuthManager.shared.currentUser?.uid else {
        errorMessage = "Please sign in to create goals."
        return
    }
    isSaving = true
    errorMessage = nil

    let target = DS.Format.cents(from: targetAmountText)
    let current = DS.Format.cents(from: currentAmountText)

    if var g = existing {
        g.name = name
        g.type = goalType
        g.targetAmount = target
        g.currentAmount = current
        g.icon = goalType.defaultIcon
        g.colorToken = selectedColorToken
        g.targetDate = hasTargetDate ? targetDate : nil
        g.notes = notes.isEmpty ? nil : notes
        g.linkedAccountId = selectedAccountId
        g.isCompleted = current >= target && target > 0

        let ok = await goalManager.updateGoal(g)
        if ok {
            dismiss()
        } else {
            errorMessage = goalManager.errorMessage ?? "Could not save goal. Please try again."
        }
    } else {
        let g = Goal(
            name: name,
            type: goalType,
            targetAmount: target,
            targetDate: hasTargetDate ? targetDate : nil,
            linkedAccountId: selectedAccountId,
            icon: goalType.defaultIcon,
            colorToken: selectedColorToken,
            notes: notes.isEmpty ? nil : notes,
            userId: userId
        )
        let ok = await goalManager.createGoal(g)
        if ok {
            dismiss()
        } else {
            errorMessage = goalManager.errorMessage ?? "Could not create goal. Please try again."
        }
    }

    isSaving = false
}
```

And add an error banner to the body (inside the ScrollView VStack, before `basicsSection`):

```swift
// Add after line 60 (inside VStack)
if let errorMessage {
    HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(DS.Colors.danger)
        Text(errorMessage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(DS.Colors.danger)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DS.Colors.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
}
```

### Files Changed
| File | Change |
|------|--------|
| `balance/Views/Goals/CreateEditGoalView.swift` | Add error state, show error on failure |

---

## BUG #5: Household — Deleted Transactions Leave Orphaned Split Expenses

### Symptom
User deletes a transaction that was linked to a household split → the split expense remains in household data, showing stale amounts and wrong balances.

### Root Cause
**File:** `ContentView.swift` (Store struct)

`Store.delete(id:)` and `Store.deleteTransactions(in:offsets:)` only remove from `transactions` array. They never notify `HouseholdManager` to clean up the corresponding `SplitExpense`.

`SplitExpense` has a `transactionId` field linking it to the deleted transaction, but nothing removes it.

### Fix

```swift
// ContentView.swift — Store struct

// BEFORE (line 8100):
mutating func delete(id: UUID) {
    transactions.removeAll { $0.id == id }
}

// AFTER:
mutating func delete(id: UUID) {
    transactions.removeAll { $0.id == id }
    // Track for cloud sync
    if !deletedTransactionIds.contains(id.uuidString) {
        deletedTransactionIds.append(id.uuidString)
    }
    // Clean up linked household split expense
    Task { @MainActor in
        HouseholdManager.shared.removeSplitExpense(forTransaction: id)
    }
}

// BEFORE (line 8095):
mutating func deleteTransactions(in items: [Transaction], offsets: IndexSet) {
    let toDelete = offsets.map { items[$0].id }
    transactions.removeAll { toDelete.contains($0.id) }
}

// AFTER:
mutating func deleteTransactions(in items: [Transaction], offsets: IndexSet) {
    let toDelete = offsets.map { items[$0].id }
    transactions.removeAll { toDelete.contains($0.id) }
    // Track for cloud sync
    for id in toDelete {
        if !deletedTransactionIds.contains(id.uuidString) {
            deletedTransactionIds.append(id.uuidString)
        }
    }
    // Clean up linked household split expenses
    Task { @MainActor in
        for id in toDelete {
            HouseholdManager.shared.removeSplitExpense(forTransaction: id)
        }
    }
}
```

Also add this convenience method to `HouseholdManager`:

```swift
// HouseholdManager.swift — add after removeSplitExpense(id:) (line 233)

/// Remove split expense linked to a specific transaction ID.
func removeSplitExpense(forTransaction transactionId: UUID) {
    let before = splitExpenses.count
    splitExpenses.removeAll { $0.transactionId == transactionId }
    if splitExpenses.count != before {
        save()
    }
}
```

### Files Changed
| File | Change |
|------|--------|
| `balance/App/ContentView.swift` (Store) | Call HouseholdManager cleanup on delete |
| `balance/Household/HouseholdManager.swift` | Add `removeSplitExpense(forTransaction:)` |

---

## BUG #6: Add Transaction — No Account/Goal Linking

### Symptom
User adds income but has no way to specify which account it goes to or allocate part to a goal.

### Root Cause
**File:** `ContentView.swift` — `AddTransactionSheet` and `TransactionFormCard`

The transaction form only has: amount, note, date, category, payment method, attachment. No fields for account or goal allocation. The `Transaction` model (in ContentView) doesn't appear to have `accountId` field.

### Analysis
This is a **feature gap** rather than a bug. The `Account` system lives in `AccountManager` (Supabase) while transactions live in `Store` (local + Supabase sync). They're not connected. Adding full account linking requires:

1. Adding `accountId: UUID?` to `Transaction`
2. Adding account picker to the form
3. Updating `AccountManager` balances when transactions are added

**Minimal viable fix**: Add an optional "Account" picker to the transaction form for income transactions. This shows which account the money comes from/goes to, for informational purposes.

```swift
// In AddTransactionSheet, add state:
@State private var selectedAccountId: UUID? = nil
@StateObject private var accountManager = AccountManager.shared

// In the body, after the payment method card, add:
if !accountManager.activeAccounts.isEmpty {
    DS.Card {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account (optional)")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.subtext)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        selectedAccountId = nil
                    } label: {
                        Text("None")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selectedAccountId == nil ? DS.Colors.text : DS.Colors.subtext)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedAccountId == nil ? DS.Colors.accent.opacity(0.15) : DS.Colors.surface2,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)

                    ForEach(accountManager.activeAccounts) { account in
                        Button {
                            selectedAccountId = account.id
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: account.type.iconName)
                                    .font(.system(size: 11))
                                Text(account.name)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(selectedAccountId == account.id ? DS.Colors.text : DS.Colors.subtext)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedAccountId == account.id ? DS.Colors.accent.opacity(0.15) : DS.Colors.surface2,
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
```

> **Note**: This requires adding `var accountId: UUID?` to the `Transaction` struct and including it in `saveTransaction()`. This is a larger change that touches the Store codable format, so test thoroughly.

### Files Changed
| File | Change |
|------|--------|
| `balance/App/ContentView.swift` (Transaction struct) | Add `accountId: UUID?` |
| `balance/App/ContentView.swift` (AddTransactionSheet) | Add account picker UI |
| `balance/App/ContentView.swift` (saveTransaction) | Pass selected accountId |

---

## Summary: Priority Order

| # | Bug | Severity | Effort | Risk |
|---|-----|----------|--------|------|
| 1 | Review resolve() not persisting | **High** | Low | Low — only adds one line |
| 5 | Household orphaned splits | **High** | Medium | Medium — touches delete flow |
| 4 | Goals silent failure | **High** | Low | Low — adds error handling |
| 2 | Insight banners non-interactive | **Medium** | Medium | Low — purely additive |
| 3 | "In -16 days" display | **Medium** | Low | Low — display-only |
| 6 | Transaction account linking | **Low** | High | High — changes data model |

---

## Regression Risks

1. **Bug #1 (Review persist)**: Low risk. The dismiss logic already works the same way. Verify that after resolving a spike, switching months and back doesn't re-show it.

2. **Bug #2 (Insight banners)**: Low risk. Adding tap handlers to previously inert views. Check that filter state works correctly and "All" filter resets.

3. **Bug #3 (Negative days)**: Very low risk. Display-only change. Verify renewal cards show correct text for past, today, tomorrow, and future dates.

4. **Bug #4 (Goals error)**: Low risk. Adding an error path to an existing flow. Verify: (a) creating a goal while logged in still works, (b) error shows when logged out, (c) Supabase errors display correctly.

5. **Bug #5 (Household cleanup)**: Medium risk. Deleting transactions now has a side effect on HouseholdManager. Verify: (a) deleting a non-household transaction doesn't crash, (b) deleting a split transaction removes it from household, (c) settle-up calculations update correctly, (d) cloud sync isn't affected.

6. **Bug #6 (Account linking)**: High risk. Changing the Transaction struct affects Codable, Supabase sync, and all views that display transactions. Consider doing this in a separate PR.

---

## Testing Checklist

### Review System (Bug #1)
- [ ] Add a transaction that triggers a spending spike
- [ ] Open Review → tap "Flag It" on the spike
- [ ] Switch to a different month, then back → spike should NOT reappear
- [ ] Restart the app → spike should NOT reappear
- [ ] Repeat with "Looks Normal" → same behavior
- [ ] Test duplicate detection: dismiss duplicates → verify they stay dismissed

### Subscription Insights (Bug #2)
- [ ] Ensure "Missed Charge" banner appears when a sub is overdue
- [ ] Tap "Missed Charge" → subscription list should filter to Active
- [ ] Tap "Newly Detected" → should filter to Active showing new subs
- [ ] Tap filter "All" → removes any active filter
- [ ] Verify insight counts show correct numbers

### Subscription Days Display (Bug #3)
- [ ] Subscription due today → shows "Today" / "today"
- [ ] Subscription due tomorrow → shows "Tomorrow" / "tomorrow"
- [ ] Subscription overdue by 5 days → shows "5d overdue"
- [ ] Subscription due in 10 days → shows "In 10 days" / "in 10d"

### Goals (Bug #4)
- [ ] Create a goal while logged in → should create successfully
- [ ] Log out → try to create a goal → should show error message
- [ ] Create a goal with expired session → should show error
- [ ] Edit an existing goal → should save and dismiss
- [ ] Verify the error banner is styled correctly in both light/dark mode

### Household (Bug #5)
- [ ] Create a split expense linked to a transaction
- [ ] Delete that transaction → split expense should also be removed
- [ ] Verify the household balance updates after deletion
- [ ] Delete multiple transactions at once (month clear) → all linked splits removed
- [ ] Verify non-split transactions can still be deleted normally
- [ ] Check that settlements referencing removed splits are unaffected

### Add Transaction (Bug #6, if implemented)
- [ ] Add income → verify account picker appears
- [ ] Select an account → save → verify transaction has accountId
- [ ] Add expense → verify account picker is optional
- [ ] Verify old transactions without accountId still load correctly
- [ ] Test Supabase sync with the new field
