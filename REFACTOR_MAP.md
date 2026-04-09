# REFACTOR_MAP.md — Phase 0 Discovery

Snapshot date: 2026-04-09
Working directory: `/Users/mani/Desktop/SwiftProjects/balance copy`
Mode: **Discovery only — no code changes were made.**

> Note: `REFACTOR_PROMPT.md` was written against an older snapshot and assumes
> `App/ContentView.swift` is a 10,789-line monolith. The current file is
> **600 lines**. A prior split has already landed. This map reflects reality
> and adjusts the plan accordingly (see §7).

---

## 1. ContentView.swift Audit

File: `balance/App/ContentView.swift` — **600 lines**

| Type | Lines | Responsibility |
|------|-------|----------------|
| `struct ContentView: View` | 8–370 | Root shell: auth gate, TabView (Dashboard / Transactions / Budget / Insights / More), launch animation, sync lifecycle, notification hookup |
| `struct PDFExporter` | 371–523 | PDF generation for monthly reports (ancillary, UI-free) |
| `struct LaunchScreenView: View` | 524–600 | Animated splash with fade in/out |

- `Tab` enum lives in `Models/AppHelpers.swift` (already externalized — good)
- No embedded giant sub-views, no 500-line helpers
- State in ContentView: 1 `@State var store: Store`, sync tasks, auth observers, UI flags
- Hidden tabs (Accounts, Goals, Subscriptions, Household, Settings) reached via MoreView navigation

**Verdict:** ContentView is effectively "root shell only" per the P1 target.

Optional polish (non-blocking):
- Move `PDFExporter` → `Export/PDFExporter.swift`
- Move `LaunchScreenView` → `Views/Components/LaunchScreenView.swift`

---

## 2. Top-Level Layout (what lives where)

```
balance/
├── App/
│   ├── ContentView.swift          Root TabView + lifecycle (600L)
│   └── balanceApp.swift           @main entry, env obj setup (21L)
│
├── Models/
│   ├── Store.swift                Local Codable source of truth for Transactions
│   ├── Transaction.swift          Transaction struct (accountId?, linkedGoalId?)
│   ├── Category.swift             Category enum + helpers
│   ├── Analytics.swift            Monthly/category summaries (computed)
│   ├── AppHelpers.swift           Tab enum, ImportHistory, shared utils
│   ├── ActionCard.swift           Review action types
│   ├── MonthlyBriefing.swift      Monthly briefing model
│   └── TransactionService.swift   Mutation pipeline (syncs Accounts/Goals/Household on tx CRUD)
│
├── SupaBase/                      Cloud CRUD + auth
│   ├── SupabaseManager.swift      Client + realtime
│   ├── AuthManager.swift          Session / login / logout
│   ├── AccountManager.shared      Accounts CRUD (cloud authoritative)
│   ├── GoalManager.shared         Goals CRUD (cloud authoritative)
│   ├── AnalyticsManager.shared    Event tracking
│   ├── NetWorthManager.shared     Account balance aggregation
│   ├── HouseholdSyncManager.swift Household push/pull
│   └── SupabaseTestView.swift     Debug view (not in prod flow)
│
├── Sync/
│   └── SyncCoordinator.shared     NWPathMonitor + debounced push/pull + conflict resolution
│
├── Manager/                        Local computation engines
│   ├── ReviewEngine.shared         Spike / duplicate / uncategorized detection
│   ├── ForecastEngine.shared       Cash flow forecast (~988L, split candidate)
│   ├── HealthScoreEngine.shared    Behavioral score
│   ├── ActionCardEngine.swift      Review UI card logic
│   ├── BriefingEngine.swift        Monthly briefing copy gen
│   ├── PDFReportGenerator.swift    PDF formatting
│   ├── ReviewItem.swift            Review detection result model
│   ├── RecurringTransactionsCard.swift  Dashboard card
│   ├── Recurringtransactions.swift Recurring tx processing (naming issue)
│   ├── UpcomingPaymentsBanner.swift Bill due notifications
│   └── WidgetDataWriter.swift      Widget App Group writer
│
├── Household/
│   ├── HouseholdManager.shared     Split expenses (UserDefaults + push to Supabase)
│   └── HouseholdModels.swift       Household, SplitExpense, Settlement, SharedGoal
│
├── Subscription/
│   ├── SubscriptionManager.shared  StoreKit2 paywall / entitlement
│   ├── SubscriptionEngine.shared   Recurring pattern detection over Store
│   ├── SubscriptionActionProvider.swift  Action logic
│   └── DetectedSubscription.swift
│
├── Security/
│   ├── AppLockManager.shared       Biometric + timeout lock
│   ├── AppConfig.shared            Feature flags / error mapping
│   ├── SecureLogger.swift          Sanitized logging
│   ├── AIProxyService.shared       AI call wrapper
│   ├── RequestGuard.swift          Rate limiting
│   └── LockScreenView.swift        Biometric prompt UI
│
├── Notifications/
│   └── NotificationScheduler.shared  UNUserNotificationCenter delegate
│
├── Export/
│   └── Exporter.swift              CSV + PDF export
│
├── DesignSystem/
│   ├── DS.swift                    Tokens (color / typography / spacing / formats)
│   ├── ColorExtensions.swift
│   └── Haptics.swift
│
├── Views/                          UI layer (80+ files), grouped by feature:
│   Dashboard/ Transactions/ Budget/ Insights/ Account/ Goals/
│   Subscriptions/ Household/ Charts/ Settings/ Authentication/
│   Review/ Briefing/ Components/ Onboarding/ Import/
│
├── Resources/                      Assets / fonts / localization
│
├── Account.swift                   ⚠️ MISPLACED — belongs in Models/
└── Goal.swift                      ⚠️ MISPLACED — belongs in Models/
```

Repo root also contains: `Untitled.swift` (empty stub — delete candidate).

---

## 3. Singletons & Shared State

| Singleton | File | Reads/Writes Store? |
|-----------|------|---------------------|
| `SupabaseManager.shared` | SupaBase/SupabaseManager.swift | No — wraps client |
| `AuthManager.shared` | SupaBase/AuthManager.swift | No — session only |
| `AccountManager.shared` | SupaBase/AccountManager.swift | No — owns `accounts`. Store holds `accountId?` refs |
| `GoalManager.shared` | SupaBase/GoalManager.swift | No — owns `goals`. Store holds `linkedGoalId?` refs |
| `AnalyticsManager.shared` | SupaBase/AnalyticsManager.swift | Reads Store for event tracking |
| `NetWorthManager.shared` | SupaBase/NetWorthManager.swift | No — reads AccountManager only |
| `HouseholdManager.shared` | Household/HouseholdManager.swift | No direct Store access. Owns splits/settlements. SplitExpense has `transactionId` FK |
| `SubscriptionManager.shared` | Subscription/SubscriptionManager.swift | No — StoreKit entitlement |
| `SubscriptionEngine.shared` | Subscription/SubscriptionEngine.swift | **Reads Store**, produces DetectedSubscription |
| `ReviewEngine.shared` | Manager/ReviewEngine.swift | **Reads Store**, mutates `items` + `dismissedTransactionKeys` |
| `ForecastEngine.shared` | Manager/ForecastEngine.swift | **Reads Store**, emits Forecast |
| `HealthScoreEngine.shared` | Manager/HealthScoreEngine.swift | **Reads Store**, emits score |
| `SyncCoordinator.shared` | Sync/SyncCoordinator.swift | **Reads + writes Store** via SupabaseManager pull/push |
| `OnboardingManager.shared` | Views/Onboarding/OnboardingSystem.swift | No — onboarding flags |
| `AppLockManager.shared` | Security/AppLockManager.swift | No — lock state |
| `AppConfig.shared` | Security/AppConfig.swift | No — config |
| `AIProxyService.shared` | Security/AIProxyService.swift | No — API wrapper |
| `NotificationScheduler.shared` | Notifications/NotificationScheduler.swift | No — UNC delegate |
| `CurrencyConverter.shared` | Views/Transactions/Currency/CurrencyConverter.swift | No — utility |

All cloud-authoritative managers (`AccountManager`, `GoalManager`) store data outside `Store`. `Store` only holds FK references (`accountId?`, `linkedGoalId?`).

---

## 4. Store vs. Supabase Intersection — Shared-State Hazards

### The split of ownership
- **Store** owns: `transactions`, `deletedTransactionIds`, `budgetsByMonth`, `categoryBudgetsByMonth`, custom categories
- **AccountManager** (cloud) owns: `accounts` and their balances
- **GoalManager** (cloud) owns: `goals` and their `currentAmount`
- **HouseholdManager** (local UD + cloud push) owns: `splitExpenses`, `settlements`

### Intersection points
| Shared concept | Owner | Referenced by | Cleanup path | Hazard |
|----------------|-------|---------------|--------------|--------|
| Account.id | AccountManager | `Transaction.accountId?` in Store | Store sanitizes orphan refs on load | ✅ safe |
| Goal.id | GoalManager | `Transaction.linkedGoalId?` in Store | Store sanitizes orphan refs on load | ✅ safe |
| Account balance | AccountManager | Adjusted via `TransactionService` on tx CRUD | Pipeline calls `adjustBalance()` | ⚠️ if pipeline partially fails, cloud drifts from Store |
| Goal progress | GoalManager | Adjusted via `TransactionService` on tx CRUD | `addContribution/withdrawContribution()` | ⚠️ same partial-failure risk |
| **SplitExpense.transactionId** | HouseholdManager | References Store transaction | **None** | 🔴 **BUG #5** — deleting a Transaction leaves orphan SplitExpense |

The **SplitExpense → Transaction** link is the one hazard not covered by existing sanitization. Every other cross-owner edge has a cleanup path.

---

## 5. Dead Code / Duplicates / Naming Inconsistencies

### Dead / empty
- `Untitled.swift` (repo root) — empty stub, **delete candidate**
- `Views/Components/PDFExportView_Placeholder.swift` — 16-line legacy shim, no references. Low-cost to keep, low-cost to delete.
- `SupaBase/SupabaseTestView.swift` — debug view, not wired into prod flow. Consider gating behind `#if DEBUG`.

### Misplaced (top-level files that should live in `Models/`)
- `balance/Account.swift` — AccountType enum + helpers → `Models/Account.swift`
- `balance/Goal.swift` — GoalType enum + helpers → `Models/Goal.swift`

### Naming inconsistencies (lowercase in PascalCase filenames)
| Current | Should be |
|---------|-----------|
| `Manager/Recurringtransactions.swift` | `Manager/RecurringTransactions.swift` |
| `Views/Authentication/Profileview.swift` | `Views/Authentication/ProfileView.swift` |
| `Views/Components/Emailverificationbanner.swift` | `Views/Components/EmailVerificationBanner.swift` |
| `Views/Components/Syncstatusview.swift` | `Views/Components/SyncStatusView.swift` |

Low-risk renames — Xcode handles import propagation, no code imports by filename.

### Duplicates
- **BackupManager**: only one file exists (`Views/Components/BackupManager.swift`). No duplicate confirmed.
- No duplicated helpers of note surfaced in discovery.

### Oversize files (split candidates, not urgent)
| File | Lines |
|------|-------|
| `Views/Household/HouseholdOverviewView.swift` | 1332 |
| `Views/Dashboard/DashboardView.swift` | 1247 |
| `Views/Transactions/TransactionsView.swift` | 1150 |
| `Manager/ForecastEngine.swift` | 988 |
| `SupaBase/SupabaseManager.swift` | 870 |

---

## 6. BUGFIX_PLAN.md Cross-Reference

| # | Bug | Severity | Primary edit sites |
|---|-----|----------|--------------------|
| 1 | `ReviewEngine.resolve()` not persisting | High | `Manager/ReviewEngine.swift` (resolve method — mirror dismiss's `dismissedTransactionKeys` insert) |
| 2 | Subscription insight banners non-interactive | Medium | `Views/Subscriptions/SubscriptionsOverviewView.swift` (~L196 insightBanners); possibly `SubscriptionsDashboardCard.swift` |
| 3 | Subscription "In -16 days" display | Medium | `Views/Subscriptions/SubscriptionsOverviewView.swift` (~L339); `SubscriptionsDashboardCard.swift` (~L91) |
| 4 | Goal save silent failure | High | `Views/Goals/CreateEditGoalView.swift` (save — add error state + banner); `SupaBase/GoalManager.swift` (bubble throws up) |
| 5 | Orphaned SplitExpense on tx delete | High | `Models/Store.swift` (delete path) + `Household/HouseholdManager.swift` (add cascade cleanup); launch-time sweep |
| 6 | AddTransaction missing Account/Goal linking | Low | `Views/Transactions/Forms/AddTransactionSheet.swift` (add pickers). `Transaction` model already supports it |

---

## 7. Phase-1 Status & Revised Plan

### Phase 1 verdict: **Effectively DONE**

- ContentView is 600 lines, structured as a root shell
- Model/Service/View separation already exists in folders
- No monolith remains to split

### Proposed revised phase commits

Because P1 is done, absorb its leftovers into a small "P1.x cleanup" commit pack and move directly to P2.

**P1 cleanup pack (pure moves + renames, zero behavior change):**
1. `P1.1: move Account/Goal type files into Models/` — move `balance/Account.swift` and `balance/Goal.swift` → `balance/Models/`
2. `P1.2: delete Untitled.swift stub` — dead file at repo root
3. `P1.3: rename lowercase-convention files` — the 4 files listed in §5
4. `P1.4 (optional): extract PDFExporter + LaunchScreenView out of ContentView.swift` — move to `Export/` and `Views/Components/`
5. `P1.5 (optional): gate SupabaseTestView behind #if DEBUG`

Each commit is independently buildable. After this pack, ContentView can shrink further (closer to ~300 lines, matching the original P1 target), and `Models/` becomes the single home for all model types.

**Then proceed to P2 as originally scoped** (TextNormalization, DecimalInput, AddTransactionSheet Account/Goal linking for BUG #6), followed by P3–P8 unchanged.

---

## 8. Shared-State / Risk Flags for Later Phases

- **P3 (ReviewEngine)**: `dismissedTransactionKeys` is the lever — resolve() must write into it (same as dismiss) so that analyze() doesn't re-spawn the item on the next pass.
- **P4 (Subscriptions)**: the "-16 days" bug is in display math, not the engine — `SubscriptionEngine` produces correct dates, the view formats them wrong.
- **P5 (Goals)**: `GoalManager.shared` is cloud-authoritative; any silent failure likely lives in a `try?` on the save path. Surface via a throwing async API + view-side error state.
- **P6 (Household)**: `SplitExpense.transactionId` is the one intersection without cleanup. Decision point — `HouseholdManager` currently persists via UserDefaults; moving its storage into `Store` would simplify cascade deletes but is a schema touch (S6).
- **P7 (Sync)**: `SyncCoordinator` + `TransactionService` multi-manager writes are the partial-failure surface. Worth auditing for transactional guarantees.
- **P8**: no architectural risk; polish/QA.

---

## 9. Summary

- **Phase 1 is already landed.** Adjust the plan: absorb leftovers into a small cleanup pack (§7), then move to P2.
- **6 bugs** from `BUGFIX_PLAN.md` all have concrete edit sites identified.
- **1 genuine shared-state hazard**: SplitExpense orphaning (BUG #5).
- **Low-risk cleanup opportunities**: 2 misplaced model files, 4 filename case fixes, 1 dead stub.
- **Architecture is healthy**: clear layering, consistent singleton pattern, sanitization for FK refs is already in place for Accounts/Goals.

Discovery complete. **Stopping here. Waiting for "go" to start the P1 cleanup pack (or jump straight to P2 if you prefer).**
