import Foundation
import Combine
import SwiftUI

// ============================================================
// MARK: - AI-Native Onboarding (Phase 10)
// ============================================================
//
// Structured, conversational onboarding that helps a new user
// set up their finances through AI-guided suggestions instead
// of heavy forms.
//
// Supports two paths:
//   • Quick Start — minimal friction, starter setup
//   • Guided Setup — fuller conversational walkthrough
//
// Produces a reviewable setup plan, then applies changes
// through existing systems (AccountManager, GoalManager,
// Store, AIAssistantModeManager, AIActionExecutor).
//
// ============================================================

// ══════════════════════════════════════════════════════════════
// MARK: - Onboarding Model
// ══════════════════════════════════════════════════════════════

/// The two onboarding paths.
enum OnboardingPath: String, Codable {
    case quickStart  = "quick_start"
    case guided      = "guided"

    var title: String {
        switch self {
        case .quickStart: return "Quick Start"
        case .guided:     return "Guided Setup"
        }
    }

    var icon: String {
        switch self {
        case .quickStart: return "hare.fill"
        case .guided:     return "map.fill"
        }
    }

    var description: String {
        switch self {
        case .quickStart:
            return "Answer a few questions and get a practical starter setup in under a minute."
        case .guided:
            return "Walk through a fuller setup with AI help — accounts, bills, budgets, goals, and preferences."
        }
    }
}

/// The stages of onboarding (ordered).
enum OnboardingStage: Int, Codable, CaseIterable, Comparable {
    case welcome            = 0
    case pathChoice         = 1
    case financialProfile   = 2
    case accountsSetup      = 3
    case recurringSetup     = 4
    case budgetSetup        = 5
    case goalsSetup         = 6
    case aiPreferences      = 7
    case review             = 8
    case applying           = 9
    case complete           = 10

    static func < (lhs: OnboardingStage, rhs: OnboardingStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .welcome:          return "Welcome"
        case .pathChoice:       return "Choose Path"
        case .financialProfile: return "Your Finances"
        case .accountsSetup:    return "Accounts"
        case .recurringSetup:   return "Bills & Subscriptions"
        case .budgetSetup:      return "Budget"
        case .goalsSetup:       return "Goals"
        case .aiPreferences:    return "AI Preferences"
        case .review:           return "Review"
        case .applying:         return "Setting Up"
        case .complete:         return "All Done"
        }
    }

    var icon: String {
        switch self {
        case .welcome:          return "hand.wave.fill"
        case .pathChoice:       return "arrow.triangle.branch"
        case .financialProfile: return "person.text.rectangle.fill"
        case .accountsSetup:    return "building.columns.fill"
        case .recurringSetup:   return "repeat"
        case .budgetSetup:      return "chart.bar.fill"
        case .goalsSetup:       return "target"
        case .aiPreferences:    return "dial.medium.fill"
        case .review:           return "checkmark.shield.fill"
        case .applying:         return "gearshape.2.fill"
        case .complete:         return "party.popper.fill"
        }
    }

    /// Stages used in Quick Start path.
    static var quickStartStages: [OnboardingStage] {
        [.welcome, .pathChoice, .financialProfile, .budgetSetup, .aiPreferences, .review, .applying, .complete]
    }

    /// Stages used in Guided path.
    static var guidedStages: [OnboardingStage] {
        OnboardingStage.allCases
    }
}

/// A single item in the suggested setup plan.
struct OnboardingSetupItem: Identifiable {
    let id = UUID()
    let category: SetupCategory
    let title: String
    let detail: String
    var icon: String
    var isIncluded: Bool = true   // user can toggle off

    /// The underlying action to apply.
    var action: AIAction?

    /// For account creation (needs separate path via AccountManager).
    var accountSpec: AccountSpec?

    /// For goal creation (needs separate path via GoalManager).
    var goalSpec: GoalSpec?

    enum SetupCategory: String {
        case account       = "Account"
        case budget        = "Budget"
        case categoryBudget = "Category Budget"
        case recurring     = "Recurring Bill"
        case subscription  = "Subscription"
        case goal          = "Goal"
        case aiPreference  = "AI Preference"
    }
}

/// Lightweight account creation spec (avoids needing full Account with userId at plan time).
struct AccountSpec {
    var name: String
    var type: AccountType
    var balance: Double     // dollars (converted to Account.currentBalance)
    var currency: String = "USD"
}

/// Lightweight goal creation spec.
struct GoalSpec {
    var name: String
    var targetAmount: Int   // cents
    var deadline: Date?
    var icon: String = "target"
}

/// Collected answers from the user during onboarding.
struct OnboardingAnswers: Codable {
    var path: OnboardingPath = .quickStart
    var monthlyIncome: Int?             // cents
    var hasCheckingAccount: Bool?
    var hasSavingsAccount: Bool?
    var hasCreditCard: Bool?
    var checkingBalance: Int?           // cents
    var savingsBalance: Int?            // cents
    var creditCardBalance: Int?         // cents (owed)
    var recurringBills: [RecurringBillAnswer] = []
    var subscriptions: [SubscriptionAnswer] = []
    var monthlyBudget: Int?             // cents — user's desired total budget
    var wantAutoBudget: Bool?           // auto-create category budgets?
    var goalName: String?
    var goalAmount: Int?                // cents
    var goalDeadline: String?           // ISO date
    var secondGoalName: String?
    var secondGoalAmount: Int?
    var selectedMode: AssistantMode = .assistant
    var wantsProactiveAlerts: Bool = true
    var prefersMoreConfirmation: Bool = false
}

struct RecurringBillAnswer: Codable, Identifiable {
    var id = UUID()
    var name: String
    var amount: Int         // cents
    var frequency: String   // "monthly", "yearly"
    var category: String    // e.g. "bills", "rent"
}

struct SubscriptionAnswer: Codable, Identifiable {
    var id = UUID()
    var name: String
    var amount: Int         // cents
    var frequency: String   // "monthly", "yearly"
}

// ══════════════════════════════════════════════════════════════
// MARK: - Onboarding Session
// ══════════════════════════════════════════════════════════════

/// Persistent state for one onboarding session.
struct OnboardingSession: Codable {
    let id: UUID
    var path: OnboardingPath
    var currentStage: OnboardingStage
    var answers: OnboardingAnswers
    var isComplete: Bool
    let startedAt: Date
    var completedAt: Date?

    init(path: OnboardingPath = .quickStart) {
        self.id = UUID()
        self.path = path
        self.currentStage = .welcome
        self.answers = OnboardingAnswers(path: path)
        self.isComplete = false
        self.startedAt = Date()
    }

    /// Stages for the chosen path.
    var stages: [OnboardingStage] {
        path == .quickStart ? OnboardingStage.quickStartStages : OnboardingStage.guidedStages
    }

    /// Index of current stage within the path.
    var currentStageIndex: Int {
        stages.firstIndex(of: currentStage) ?? 0
    }

    /// Total number of stages in the path.
    var totalStages: Int { stages.count }

    /// Progress 0.0–1.0.
    var progress: Double {
        guard totalStages > 1 else { return 0 }
        return Double(currentStageIndex) / Double(totalStages - 1)
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: - Onboarding Engine
// ══════════════════════════════════════════════════════════════

@MainActor
class AIOnboardingEngine: ObservableObject {
    static let shared = AIOnboardingEngine()

    @Published var session: OnboardingSession = OnboardingSession()
    @Published var setupPlan: [OnboardingSetupItem] = []
    @Published var isApplying: Bool = false
    @Published var applyProgress: Double = 0
    @Published var applyError: String?

    /// Whether AI onboarding has been completed (persisted).
    @AppStorage("ai.onboarding.completed") var hasCompletedAIOnboarding = false

    private let storageKey = "ai.onboarding.session"

    private init() {
        loadSession()
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Session Management
    // ══════════════════════════════════════════════════════════

    /// Start a new onboarding session.
    func startSession(path: OnboardingPath) {
        session = OnboardingSession(path: path)
        session.answers.path = path
        session.currentStage = .financialProfile
        if path == .quickStart {
            // Quick start skips accounts and recurring — jump to financialProfile
            session.currentStage = .financialProfile
        }
        setupPlan = []
        saveSession()
    }

    /// Move to the next stage in the current path.
    func advanceToNextStage() {
        let stages = session.stages
        guard let idx = stages.firstIndex(of: session.currentStage),
              idx + 1 < stages.count else { return }
        session.currentStage = stages[idx + 1]
        saveSession()
    }

    /// Move to a specific stage.
    func goToStage(_ stage: OnboardingStage) {
        session.currentStage = stage
        saveSession()
    }

    /// Go back one stage.
    func goBack() {
        let stages = session.stages
        guard let idx = stages.firstIndex(of: session.currentStage), idx > 0 else { return }
        session.currentStage = stages[idx - 1]
        saveSession()
    }

    /// Whether the user can go back from the current stage.
    var canGoBack: Bool {
        let stages = session.stages
        guard let idx = stages.firstIndex(of: session.currentStage) else { return false }
        return idx > 0 && session.currentStage != .applying && session.currentStage != .complete
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Setup Plan Generation
    // ══════════════════════════════════════════════════════════

    /// Generate a suggested setup plan from collected answers.
    func generateSetupPlan() {
        var items: [OnboardingSetupItem] = []
        let answers = session.answers

        // ── Accounts ──
        if session.path == .guided {
            if answers.hasCheckingAccount == true {
                items.append(OnboardingSetupItem(
                    category: .account,
                    title: "Checking Account",
                    detail: answers.checkingBalance.map { "Balance: \(fmtCents($0))" } ?? "No balance set",
                    icon: "building.columns.fill",
                    accountSpec: AccountSpec(
                        name: "Checking",
                        type: .bank,
                        balance: Double(answers.checkingBalance ?? 0) / 100.0
                    )
                ))
            }
            if answers.hasSavingsAccount == true {
                items.append(OnboardingSetupItem(
                    category: .account,
                    title: "Savings Account",
                    detail: answers.savingsBalance.map { "Balance: \(fmtCents($0))" } ?? "No balance set",
                    icon: "banknote.fill",
                    accountSpec: AccountSpec(
                        name: "Savings",
                        type: .savings,
                        balance: Double(answers.savingsBalance ?? 0) / 100.0
                    )
                ))
            }
            if answers.hasCreditCard == true {
                items.append(OnboardingSetupItem(
                    category: .account,
                    title: "Credit Card",
                    detail: answers.creditCardBalance.map { "Balance owed: \(fmtCents($0))" } ?? "No balance set",
                    icon: "creditcard.fill",
                    accountSpec: AccountSpec(
                        name: "Credit Card",
                        type: .creditCard,
                        balance: Double(answers.creditCardBalance ?? 0) / 100.0
                    )
                ))
            }
        } else {
            // Quick start: create a default checking account
            items.append(OnboardingSetupItem(
                category: .account,
                title: "Main Account",
                detail: "Your primary account",
                icon: "building.columns.fill",
                accountSpec: AccountSpec(name: "Main Account", type: .bank, balance: 0)
            ))
        }

        // ── Monthly budget ──
        let budgetAmount = answers.monthlyBudget ?? suggestBudget(from: answers)
        if budgetAmount > 0 {
            items.append(OnboardingSetupItem(
                category: .budget,
                title: "Monthly Budget: \(fmtCents(budgetAmount))",
                detail: "Total spending limit for this month",
                icon: "chart.bar.fill",
                action: AIAction(
                    type: .setBudget,
                    params: .init(budgetAmount: budgetAmount, budgetMonth: "this_month")
                )
            ))
        }

        // ── Category budgets (auto-suggested) ──
        if answers.wantAutoBudget == true && budgetAmount > 0 {
            let catSuggestions = suggestCategoryBudgets(total: budgetAmount)
            for (cat, amount) in catSuggestions {
                items.append(OnboardingSetupItem(
                    category: .categoryBudget,
                    title: "\(cat.capitalized): \(fmtCents(amount))",
                    detail: "Suggested \(cat) budget",
                    icon: categoryIcon(cat),
                    action: AIAction(
                        type: .setCategoryBudget,
                        params: .init(budgetAmount: amount, budgetCategory: cat)
                    )
                ))
            }
        }

        // ── Recurring bills (guided path) ──
        for bill in answers.recurringBills {
            items.append(OnboardingSetupItem(
                category: .recurring,
                title: "\(bill.name): \(fmtCents(bill.amount))/\(bill.frequency)",
                detail: "Recurring \(bill.category) bill",
                icon: "repeat",
                action: AIAction(
                    type: .addRecurring,
                    params: .init(
                        amount: bill.amount,
                        category: bill.category,
                        recurringName: bill.name,
                        recurringFrequency: bill.frequency
                    )
                )
            ))
        }

        // ── Subscriptions (guided path) ──
        for sub in answers.subscriptions {
            items.append(OnboardingSetupItem(
                category: .subscription,
                title: "\(sub.name): \(fmtCents(sub.amount))/\(sub.frequency)",
                detail: "Subscription",
                icon: "repeat.circle.fill",
                action: AIAction(
                    type: .addSubscription,
                    params: .init(
                        subscriptionName: sub.name,
                        subscriptionAmount: sub.amount,
                        subscriptionFrequency: sub.frequency
                    )
                )
            ))
        }

        // ── Goals ──
        if let goalName = answers.goalName, !goalName.isEmpty {
            items.append(OnboardingSetupItem(
                category: .goal,
                title: goalName,
                detail: answers.goalAmount.map { "Target: \(fmtCents($0))" } ?? "No target set",
                icon: "target",
                goalSpec: GoalSpec(
                    name: goalName,
                    targetAmount: answers.goalAmount ?? 0,
                    deadline: answers.goalDeadline.flatMap { ISO8601DateFormatter().date(from: $0) }
                )
            ))
        }
        if let goalName2 = answers.secondGoalName, !goalName2.isEmpty {
            items.append(OnboardingSetupItem(
                category: .goal,
                title: goalName2,
                detail: answers.secondGoalAmount.map { "Target: \(fmtCents($0))" } ?? "No target set",
                icon: "star.fill",
                goalSpec: GoalSpec(
                    name: goalName2,
                    targetAmount: answers.secondGoalAmount ?? 0
                )
            ))
        }

        // ── AI Preferences ──
        items.append(OnboardingSetupItem(
            category: .aiPreference,
            title: "AI Mode: \(answers.selectedMode.title)",
            detail: answers.selectedMode.tagline,
            icon: answers.selectedMode.icon
        ))

        if !answers.wantsProactiveAlerts {
            items.append(OnboardingSetupItem(
                category: .aiPreference,
                title: "Proactive alerts: Off",
                detail: "AI won't generate proactive notifications",
                icon: "bell.slash.fill"
            ))
        }

        if answers.prefersMoreConfirmation {
            items.append(OnboardingSetupItem(
                category: .aiPreference,
                title: "Extra confirmation: On",
                detail: "AI will ask before most actions",
                icon: "shield.checkered"
            ))
        }

        setupPlan = items
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Apply Setup Plan
    // ══════════════════════════════════════════════════════════

    /// Apply all included setup items through existing systems.
    func applySetupPlan(store: inout Store, userId: String) async {
        let included = setupPlan.filter(\.isIncluded)
        guard !included.isEmpty else {
            completeOnboarding()
            return
        }

        isApplying = true
        applyProgress = 0
        applyError = nil

        let total = Double(included.count)
        var appliedCount = 0

        for item in included {
            // ── Accounts (via AccountManager) ──
            if let spec = item.accountSpec {
                let account = Account(
                    id: UUID(),
                    name: spec.name,
                    type: spec.type,
                    currentBalance: spec.balance,
                    currency: spec.currency,
                    institutionName: nil,
                    creditLimit: spec.type == .creditCard ? 0 : nil,
                    interestRate: nil,
                    isArchived: false,
                    createdAt: Date(),
                    updatedAt: Date(),
                    userId: UUID(uuidString: userId) ?? UUID()
                )
                let success = await AccountManager.shared.createAccount(account)
                if !success {
                    SecureLogger.warning("Onboarding: Failed to create account \(spec.name)")
                }
            }

            // ── Goals (via GoalManager) ──
            if let spec = item.goalSpec {
                let goal = Goal(
                    id: UUID(),
                    name: spec.name,
                    type: .custom,
                    targetAmount: spec.targetAmount,
                    currentAmount: 0,
                    currency: "USD",
                    targetDate: spec.deadline,
                    linkedAccountId: nil,
                    icon: spec.icon,
                    colorToken: "accent",
                    notes: "Created during onboarding",
                    isCompleted: false,
                    createdAt: Date(),
                    updatedAt: Date(),
                    userId: userId
                )
                await GoalManager.shared.createGoal(goal)
            }

            // ── Actions (via AIActionExecutor — budgets, recurring, subscriptions) ──
            if let action = item.action {
                let result = await AIActionExecutor.execute(action, store: &store)
                if !result.success {
                    SecureLogger.warning("Onboarding: Action failed — \(result.summary)")
                }

                // Record in audit log for traceability
                AIActionHistory.shared.record(
                    action: action,
                    result: result,
                    trustDecision: nil,
                    classification: nil,
                    groupId: session.id,
                    groupLabel: "Onboarding Setup",
                    isAutoExecuted: true
                )
            }

            // ── AI Preferences (direct) ──
            if item.category == .aiPreference {
                applyAIPreferences()
            }

            appliedCount += 1
            applyProgress = Double(appliedCount) / total
        }

        // Save store after all mutations
        store.save(userId: userId)

        isApplying = false
        completeOnboarding()
    }

    /// Apply AI preference settings from answers.
    private func applyAIPreferences() {
        let answers = session.answers

        // Set AI mode
        AIAssistantModeManager.shared.currentMode = answers.selectedMode

        // If user doesn't want proactive and chose advisor explicitly, mode handles it.
        // But if they explicitly turned off proactive on a mode that has it, note it in memory.
        if !answers.wantsProactiveAlerts && answers.selectedMode.proactiveInsights {
            // Override to advisor mode which has proactive = none
            AIAssistantModeManager.shared.currentMode = .advisor
        }

        // If user wants more confirmation, set to advisor mode
        if answers.prefersMoreConfirmation && answers.selectedMode != .advisor {
            AIAssistantModeManager.shared.currentMode = .advisor
        }
    }

    /// Mark onboarding as complete.
    func completeOnboarding() {
        session.isComplete = true
        session.completedAt = Date()
        session.currentStage = .complete
        hasCompletedAIOnboarding = true
        saveSession()
    }

    /// Skip onboarding entirely — mark as done with no setup.
    func skipOnboarding() {
        hasCompletedAIOnboarding = true
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Suggestion Helpers
    // ══════════════════════════════════════════════════════════

    /// Suggest a monthly budget from income.
    private func suggestBudget(from answers: OnboardingAnswers) -> Int {
        guard let income = answers.monthlyIncome, income > 0 else { return 0 }
        // Suggest 70% of income as budget (30% savings target)
        return Int(Double(income) * 0.7)
    }

    /// Suggest category budget splits from total budget.
    private func suggestCategoryBudgets(total: Int) -> [(String, Int)] {
        // Practical split for a starter budget
        let allocations: [(String, Double)] = [
            ("rent",       0.30),
            ("groceries",  0.15),
            ("bills",      0.10),
            ("transport",  0.10),
            ("dining",     0.10),
            ("shopping",   0.08),
            ("health",     0.05),
            ("other",      0.12),
        ]
        return allocations.map { (cat, pct) in
            (cat, Int(Double(total) * pct))
        }
    }

    /// Icon for a category key.
    private func categoryIcon(_ key: String) -> String {
        switch key {
        case "rent":       return "house.fill"
        case "groceries":  return "cart.fill"
        case "bills":      return "bolt.fill"
        case "transport":  return "car.fill"
        case "dining":     return "fork.knife"
        case "shopping":   return "bag.fill"
        case "health":     return "heart.fill"
        case "education":  return "book.fill"
        default:           return "ellipsis.circle.fill"
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Persistence
    // ══════════════════════════════════════════════════════════

    private func saveSession() {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadSession() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(OnboardingSession.self, from: data),
           !saved.isComplete {
            session = saved
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Helpers
    // ══════════════════════════════════════════════════════════

    private func fmtCents(_ cents: Int) -> String {
        let isNeg = cents < 0
        let str = String(format: "$%.2f", Double(abs(cents)) / 100.0)
        return isNeg ? "-\(str)" : str
    }
}
