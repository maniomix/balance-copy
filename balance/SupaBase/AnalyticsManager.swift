import Foundation
import SwiftUI

// ============================================================
// MARK: - Product Analytics
// ============================================================
//
// Centralized, typed analytics for growth, retention, and
// feature measurement. Privacy-safe: no raw financial amounts
// are ever sent — only metadata (counts, ratios, flags).
//
// Events flow: App → AnalyticsManager → SupabaseManager.trackEvent()
// ============================================================

// MARK: - Typed Event Catalog

/// Every trackable event in the app. Adding a new event
/// is a single case — the compiler enforces exhaustive handling.
enum AnalyticsEvent {

    // ── Lifecycle ──────────────────────────────────────────
    case appOpen
    case appBackground(sessionSeconds: Int)
    case signup(source: String)

    // ── Onboarding ─────────────────────────────────────────
    case onboardingStarted
    case onboardingStepViewed(step: String)
    case onboardingCompleted(stepsCount: Int)
    case onboardingSkipped(atStep: String)

    // ── Core Features (first-time flags) ───────────────────
    case firstTransactionAdded
    case firstBudgetCreated
    case firstGoalCreated

    // ── Transactions ───────────────────────────────────────
    case transactionAdded(isExpense: Bool)
    case transactionEdited
    case transactionDeleted
    case csvImported(count: Int)

    // ── Budget ─────────────────────────────────────────────
    case budgetSet
    case budgetExceeded(spentRatio: Double)
    case categoryBudgetSet

    // ── Goals ──────────────────────────────────────────────
    case goalCreated
    case goalContribution
    case goalCompleted

    // ── Export ──────────────────────────────────────────────
    case exportUsed(format: String)

    // ── Dashboard Engagement ───────────────────────────────
    case dashboardViewed
    case tabSwitched(tab: String)
    case monthSwitched

    // ── Forecast / Engines ─────────────────────────────────
    case forecastViewed
    case reviewQueueOpened(pendingCount: Int)
    case reviewItemResolved(type: String)

    // ── Subscriptions (app subscription) ───────────────────
    case paywallViewed(location: String)
    case trialStarted
    case subscriptionPurchased(plan: String)

    // ── Household ──────────────────────────────────────────
    case householdCreated
    case householdJoined
    case splitExpenseAdded

    // ── Widgets ────────────────────────────────────────────
    case widgetInstalled(kind: String)

    // ── Subscriptions Engine ───────────────────────────────
    case subscriptionDetected(count: Int)

    // ── Errors ─────────────────────────────────────────────
    case error(context: String, message: String)

    // ── Screen Time ────────────────────────────────────────
    case screenViewed(name: String)
    case screenExited(name: String, seconds: Int)

    // Computed properties for storage
    var name: String {
        switch self {
        case .appOpen:                  return "app_open"
        case .appBackground:            return "app_background"
        case .signup:                   return "signup"
        case .onboardingStarted:        return "onboarding_started"
        case .onboardingStepViewed:     return "onboarding_step_viewed"
        case .onboardingCompleted:      return "onboarding_completed"
        case .onboardingSkipped:        return "onboarding_skipped"
        case .firstTransactionAdded:    return "first_transaction_added"
        case .firstBudgetCreated:       return "first_budget_created"
        case .firstGoalCreated:         return "first_goal_created"
        case .transactionAdded:         return "transaction_added"
        case .transactionEdited:        return "transaction_edited"
        case .transactionDeleted:       return "transaction_deleted"
        case .csvImported:              return "csv_imported"
        case .budgetSet:                return "budget_set"
        case .budgetExceeded:           return "budget_exceeded"
        case .categoryBudgetSet:        return "category_budget_set"
        case .goalCreated:              return "goal_created"
        case .goalContribution:         return "goal_contribution"
        case .goalCompleted:            return "goal_completed"
        case .exportUsed:               return "export_used"
        case .dashboardViewed:          return "dashboard_viewed"
        case .tabSwitched:              return "tab_switched"
        case .monthSwitched:            return "month_switched"
        case .forecastViewed:           return "forecast_viewed"
        case .reviewQueueOpened:        return "review_queue_opened"
        case .reviewItemResolved:       return "review_item_resolved"
        case .paywallViewed:            return "paywall_viewed"
        case .trialStarted:             return "trial_started"
        case .subscriptionPurchased:    return "subscription_purchased"
        case .householdCreated:         return "household_created"
        case .householdJoined:          return "household_joined"
        case .splitExpenseAdded:        return "split_expense_added"
        case .widgetInstalled:          return "widget_installed"
        case .subscriptionDetected:     return "subscription_detected"
        case .error:                    return "error"
        case .screenViewed:             return "screen_viewed"
        case .screenExited:             return "screen_exited"
        }
    }

    /// Privacy-safe properties — no raw financial data.
    var properties: [String: String] {
        switch self {
        case .appOpen:
            return [:]
        case .appBackground(let secs):
            return ["session_seconds": "\(secs)"]
        case .signup(let source):
            return ["source": source]

        case .onboardingStarted:
            return [:]
        case .onboardingStepViewed(let step):
            return ["step": step]
        case .onboardingCompleted(let count):
            return ["steps_count": "\(count)"]
        case .onboardingSkipped(let step):
            return ["at_step": step]

        case .firstTransactionAdded, .firstBudgetCreated, .firstGoalCreated:
            return [:]

        case .transactionAdded(let isExpense):
            return ["is_expense": isExpense ? "true" : "false"]
        case .transactionEdited, .transactionDeleted:
            return [:]
        case .csvImported(let count):
            return ["count": "\(count)"]

        case .budgetSet:
            return [:]
        case .budgetExceeded(let ratio):
            return ["spent_ratio": String(format: "%.2f", ratio)]
        case .categoryBudgetSet:
            return [:]

        case .goalCreated, .goalContribution, .goalCompleted:
            return [:]

        case .exportUsed(let format):
            return ["format": format]

        case .dashboardViewed:
            return [:]
        case .tabSwitched(let tab):
            return ["tab": tab]
        case .monthSwitched:
            return [:]

        case .forecastViewed:
            return [:]
        case .reviewQueueOpened(let count):
            return ["pending_count": "\(count)"]
        case .reviewItemResolved(let type):
            return ["type": type]

        case .paywallViewed(let location):
            return ["location": location]
        case .trialStarted:
            return [:]
        case .subscriptionPurchased(let plan):
            return ["plan": plan]

        case .householdCreated, .householdJoined, .splitExpenseAdded:
            return [:]

        case .widgetInstalled(let kind):
            return ["kind": kind]
        case .subscriptionDetected(let count):
            return ["count": "\(count)"]

        case .error(let context, let message):
            return ["context": context, "message": String(message.prefix(200))]

        case .screenViewed(let name):
            return ["screen": name]
        case .screenExited(let name, let secs):
            return ["screen": name, "seconds": "\(secs)"]
        }
    }
}

// MARK: - Analytics Manager

@MainActor
final class AnalyticsManager {
    static let shared = AnalyticsManager()

    // Session tracking
    private var sessionStart: Date?

    // First-time flags (persisted)
    private let defaults = UserDefaults.standard
    private let firstTxKey = "analytics.first_tx"
    private let firstBudgetKey = "analytics.first_budget"
    private let firstGoalKey = "analytics.first_goal"

    private var supabase: SupabaseManager { SupabaseManager.shared }

    private init() {}

    // MARK: - Public API

    /// Fire-and-forget event tracking. Safe to call from anywhere.
    func track(_ event: AnalyticsEvent) {
        SecureLogger.debug("[Analytics] \(event.name)")

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.supabase.trackEvent(
                    name: event.name,
                    properties: event.properties
                )
            } catch {
                SecureLogger.warning("Analytics tracking failed for \(event.name)")
            }
        }
    }

    // MARK: - Session

    func startSession() {
        sessionStart = Date()
        track(.appOpen)
    }

    func endSession() {
        guard let start = sessionStart else { return }
        let seconds = Int(Date().timeIntervalSince(start))
        track(.appBackground(sessionSeconds: seconds))
        sessionStart = nil
    }

    // MARK: - First-Time Milestones

    /// Call after a transaction is added. Fires first_transaction_added once.
    func checkFirstTransaction() {
        guard !defaults.bool(forKey: firstTxKey) else { return }
        defaults.set(true, forKey: firstTxKey)
        track(.firstTransactionAdded)
    }

    /// Call after a budget is set. Fires first_budget_created once.
    func checkFirstBudget() {
        guard !defaults.bool(forKey: firstBudgetKey) else { return }
        defaults.set(true, forKey: firstBudgetKey)
        track(.firstBudgetCreated)
    }

    /// Call after a goal is created. Fires first_goal_created once.
    func checkFirstGoal() {
        guard !defaults.bool(forKey: firstGoalKey) else { return }
        defaults.set(true, forKey: firstGoalKey)
        track(.firstGoalCreated)
    }
}

// MARK: - View Modifier for automatic screen tracking

struct TrackScreenModifier: ViewModifier {
    let screen: String
    @State private var appeared = Date()

    func body(content: Content) -> some View {
        content
            .onAppear {
                appeared = Date()
                AnalyticsManager.shared.track(.screenViewed(name: screen))
            }
            .onDisappear {
                let seconds = Int(Date().timeIntervalSince(appeared))
                if seconds >= 2 { // Only track meaningful visits
                    AnalyticsManager.shared.track(.screenExited(name: screen, seconds: seconds))
                }
            }
    }
}

extension View {
    /// Attach screen tracking. Usage: `.trackScreen("budget")`
    func trackScreen(_ name: String) -> some View {
        modifier(TrackScreenModifier(screen: name))
    }
}
