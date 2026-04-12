import Foundation
import Combine

// ============================================================
// MARK: - AI Workflow Engine (Phase 4)
// ============================================================
//
// Multi-step workflow system that lets the AI execute structured,
// checkpointed, multi-action tasks safely.
//
// Supports:
//   • ordered step execution with progress tracking
//   • approval checkpoints (pause when risky)
//   • failure + retry per step
//   • trust system integration
//   • grouped audit trail (all actions share workflowId)
//   • 3 built-in workflow types:
//     – cleanupUncategorized
//     – budgetRescue
//     – monthlyClose
//
// ============================================================

// ══════════════════════════════════════════════════════════════
// MARK: - Workflow Model
// ══════════════════════════════════════════════════════════════

/// The type of a workflow (determines which steps get generated).
enum WorkflowType: String, Codable, CaseIterable, Identifiable {
    case cleanupUncategorized = "cleanup_uncategorized"
    case budgetRescue         = "budget_rescue"
    case monthlyClose         = "monthly_close"
    case subscriptionReview   = "subscription_review"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cleanupUncategorized: return "Cleanup Transactions"
        case .budgetRescue:         return "Budget Rescue"
        case .monthlyClose:         return "Monthly Close"
        case .subscriptionReview:   return "Subscription Review"
        }
    }

    var icon: String {
        switch self {
        case .cleanupUncategorized: return "tag.fill"
        case .budgetRescue:         return "lifepreserver.fill"
        case .monthlyClose:         return "calendar.badge.checkmark"
        case .subscriptionReview:   return "repeat"
        }
    }

    var subtitle: String {
        switch self {
        case .cleanupUncategorized:
            return "Find and fix uncategorized transactions"
        case .budgetRescue:
            return "Rebalance over-budget categories"
        case .monthlyClose:
            return "Review, clean up, and plan ahead"
        case .subscriptionReview:
            return "Review recurring charges and optimize"
        }
    }
}

/// Overall workflow status.
enum WorkflowStatus: String, Codable {
    case running
    case paused              // waiting for user approval at a checkpoint
    case completed
    case failed
    case cancelled
}

/// A complete multi-step workflow instance.
struct AIWorkflow: Identifiable {
    let id: UUID
    let type: WorkflowType
    var status: WorkflowStatus
    var steps: [AIWorkflowStep]
    var currentStepIndex: Int
    let startedAt: Date
    var updatedAt: Date
    var completedAt: Date?
    let title: String
    let summary: String
    let groupId: UUID           // shared with audit records

    var currentStep: AIWorkflowStep? {
        guard currentStepIndex >= 0, currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }

    var isComplete: Bool { status == .completed }
    var isPaused: Bool { status == .paused }

    var progress: Double {
        guard !steps.isEmpty else { return 1.0 }
        let done = steps.filter { $0.status == .completed || $0.status == .skipped }.count
        return Double(done) / Double(steps.count)
    }

    var completedStepCount: Int {
        steps.filter { $0.status == .completed }.count
    }

    var failedStep: AIWorkflowStep? {
        steps.first { $0.status == .failed }
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: - Workflow Step Model
// ══════════════════════════════════════════════════════════════

/// The kind of work a step performs.
enum WorkflowStepKind: String, Codable {
    case analyze            // Pure read — no mutations
    case autoExecute        // Execute safe mutations automatically
    case review             // Present results, pause for approval
    case apply              // Apply approved changes
    case summary            // Show final results
}

/// Status of a single step.
enum WorkflowStepStatus: String, Codable {
    case pending
    case running
    case awaitingApproval    // paused for user approval
    case completed
    case failed
    case skipped
}

/// A single step in a workflow.
struct AIWorkflowStep: Identifiable {
    let id: UUID
    let title: String
    let icon: String
    let kind: WorkflowStepKind
    var status: WorkflowStepStatus = .pending
    var requiresApproval: Bool
    var isRetryable: Bool

    // ── Results (populated after execution) ──
    var resultMessage: String?
    var detailLines: [String] = []
    var error: String?

    // ── Proposed actions (populated by analyze/review steps) ──
    var proposedItems: [ProposedItem] = []

    /// Count of executed actions (for audit summary).
    var executedCount: Int = 0
    var skippedCount: Int = 0
    var failedCount: Int = 0
}

/// A single proposed change within a step that may need approval.
struct ProposedItem: Identifiable {
    let id: UUID
    let summary: String
    let detail: String
    var isApproved: Bool
    var isHighConfidence: Bool

    /// In-memory reference — the AIAction to execute if approved.
    var action: AIAction?

    /// For budget rescue: amount in cents.
    var amountCents: Int?
    var categoryKey: String?
}

// ══════════════════════════════════════════════════════════════
// MARK: - Workflow Engine
// ══════════════════════════════════════════════════════════════

@MainActor
class AIWorkflowEngine: ObservableObject {
    static let shared = AIWorkflowEngine()

    @Published var activeWorkflow: AIWorkflow?

    private let actionHistory = AIActionHistory.shared
    private let trustManager = AITrustManager.shared
    private let categorySuggester = AICategorySuggester.shared
    private let merchantMemory = AIMerchantMemory.shared

    private init() {}

    // ══════════════════════════════════════════════════════════
    // MARK: - Public API
    // ══════════════════════════════════════════════════════════

    /// Start a new workflow of the given type.
    func start(_ type: WorkflowType, store: Store) {
        let groupId = UUID()

        let workflow: AIWorkflow
        switch type {
        case .cleanupUncategorized:
            workflow = buildCleanupWorkflow(store: store, groupId: groupId)
        case .budgetRescue:
            workflow = buildBudgetRescueWorkflow(store: store, groupId: groupId)
        case .monthlyClose:
            workflow = buildMonthlyCloseWorkflow(store: store, groupId: groupId)
        case .subscriptionReview:
            workflow = buildSubscriptionReviewWorkflow(groupId: groupId)
        }

        activeWorkflow = workflow

        // Auto-run the first step if it doesn't need approval
        Task {
            await runNextStepIfReady(store: store)
        }
    }

    /// Run the next pending step (called automatically or after approval).
    func runNextStep(store: inout Store) async {
        guard var workflow = activeWorkflow,
              workflow.status == .running || workflow.status == .paused,
              let step = workflow.currentStep,
              step.status == .pending || step.status == .awaitingApproval else { return }

        // Mark running
        workflow.steps[workflow.currentStepIndex].status = .running
        workflow.status = .running
        workflow.updatedAt = Date()
        activeWorkflow = workflow

        // Dispatch to the correct handler
        do {
            switch workflow.type {
            case .cleanupUncategorized:
                try await executeCleanupStep(stepIndex: workflow.currentStepIndex, store: &store)
            case .budgetRescue:
                try await executeBudgetRescueStep(stepIndex: workflow.currentStepIndex, store: &store)
            case .monthlyClose:
                try await executeMonthlyCloseStep(stepIndex: workflow.currentStepIndex, store: &store)
            case .subscriptionReview:
                try await executeSubscriptionStep(stepIndex: workflow.currentStepIndex, store: &store)
            }
        } catch {
            markCurrentStepFailed(error.localizedDescription)
            return
        }

        // After execution, check if we should advance
        advanceIfReady(store: store)
    }

    /// Approve the current paused step and continue.
    func approveAndContinue(store: inout Store) async {
        guard var workflow = activeWorkflow,
              workflow.status == .paused,
              workflow.currentStepIndex < workflow.steps.count else { return }

        // Mark approved items and continue
        workflow.steps[workflow.currentStepIndex].status = .pending
        workflow.status = .running
        activeWorkflow = workflow

        await runNextStep(store: &store)
    }

    /// Toggle approval on a proposed item.
    func toggleItemApproval(_ itemId: UUID) {
        guard var workflow = activeWorkflow,
              workflow.currentStepIndex < workflow.steps.count else { return }

        if let idx = workflow.steps[workflow.currentStepIndex]
            .proposedItems.firstIndex(where: { $0.id == itemId }) {
            workflow.steps[workflow.currentStepIndex].proposedItems[idx].isApproved.toggle()
            activeWorkflow = workflow
        }
    }

    /// Retry the current failed step.
    func retryCurrentStep(store: inout Store) async {
        guard var workflow = activeWorkflow,
              let step = workflow.currentStep,
              step.status == .failed, step.isRetryable else { return }

        workflow.steps[workflow.currentStepIndex].status = .pending
        workflow.steps[workflow.currentStepIndex].error = nil
        workflow.status = .running
        activeWorkflow = workflow

        await runNextStep(store: &store)
    }

    /// Skip the current step.
    func skipCurrentStep(store: Store) {
        guard var workflow = activeWorkflow,
              workflow.currentStepIndex < workflow.steps.count else { return }

        workflow.steps[workflow.currentStepIndex].status = .skipped
        workflow.status = .running
        activeWorkflow = workflow
        advanceIfReady(store: store)
    }

    /// Cancel the entire workflow.
    func cancel() {
        guard var workflow = activeWorkflow else { return }
        workflow.status = .cancelled
        workflow.updatedAt = Date()
        activeWorkflow = workflow
    }

    /// Dismiss a completed/cancelled/failed workflow.
    func dismiss() {
        activeWorkflow = nil
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Step Advancement
    // ══════════════════════════════════════════════════════════

    private func advanceIfReady(store: Store) {
        guard var workflow = activeWorkflow else { return }
        let idx = workflow.currentStepIndex

        // If current step completed, move forward
        if idx < workflow.steps.count && workflow.steps[idx].status == .completed {
            let nextIdx = idx + 1
            if nextIdx >= workflow.steps.count {
                // Workflow complete
                workflow.status = .completed
                workflow.completedAt = Date()
                workflow.updatedAt = Date()
                activeWorkflow = workflow
                return
            }

            workflow.currentStepIndex = nextIdx
            workflow.updatedAt = Date()
            activeWorkflow = workflow

            // Auto-run next step if it doesn't need approval
            Task {
                await runNextStepIfReady(store: store)
            }
        }
    }

    private func runNextStepIfReady(store: Store) async {
        guard let step = activeWorkflow?.currentStep,
              step.status == .pending else { return }

        // Only auto-run read-only steps (analyze/summary).
        // Mutating steps (autoExecute/apply) must be triggered by the view
        // with a proper inout Store binding so mutations aren't lost.
        guard step.kind == .analyze || step.kind == .summary else { return }

        var mutableStore = store
        await runNextStep(store: &mutableStore)
    }

    /// Whether the current step is a pending mutating step that the view should auto-trigger.
    var needsAutoExecution: Bool {
        guard let step = activeWorkflow?.currentStep,
              step.status == .pending,
              activeWorkflow?.status == .running else { return false }
        return step.kind == .autoExecute || step.kind == .apply
    }

    private func markCurrentStepFailed(_ message: String) {
        guard var workflow = activeWorkflow else { return }
        workflow.steps[workflow.currentStepIndex].status = .failed
        workflow.steps[workflow.currentStepIndex].error = message
        workflow.status = .failed
        workflow.updatedAt = Date()
        activeWorkflow = workflow
    }

    private func markCurrentStepCompleted(message: String? = nil) {
        guard var workflow = activeWorkflow else { return }
        workflow.steps[workflow.currentStepIndex].status = .completed
        if let message { workflow.steps[workflow.currentStepIndex].resultMessage = message }
        workflow.updatedAt = Date()
        activeWorkflow = workflow
    }

    private func pauseForApproval(message: String? = nil) {
        guard var workflow = activeWorkflow else { return }
        workflow.steps[workflow.currentStepIndex].status = .awaitingApproval
        if let message { workflow.steps[workflow.currentStepIndex].resultMessage = message }
        workflow.status = .paused
        workflow.updatedAt = Date()
        activeWorkflow = workflow
    }

    private func updateCurrentStep(_ update: (inout AIWorkflowStep) -> Void) {
        guard var workflow = activeWorkflow,
              workflow.currentStepIndex < workflow.steps.count else { return }
        update(&workflow.steps[workflow.currentStepIndex])
        activeWorkflow = workflow
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Workflow Builders
    // ══════════════════════════════════════════════════════════

    private func buildCleanupWorkflow(store: Store, groupId: UUID) -> AIWorkflow {
        let month = store.selectedMonth
        let uncategorized = monthTransactions(store: store, month: month)
            .filter { $0.category == .other }

        let steps: [AIWorkflowStep] = [
            AIWorkflowStep(
                id: UUID(), title: "Scan Transactions", icon: "magnifyingglass",
                kind: .analyze, requiresApproval: false, isRetryable: false
            ),
            AIWorkflowStep(
                id: UUID(), title: "Auto-Categorize Safe", icon: "bolt.fill",
                kind: .autoExecute, requiresApproval: false, isRetryable: true
            ),
            AIWorkflowStep(
                id: UUID(), title: "Review Uncertain", icon: "hand.raised.fill",
                kind: .review, requiresApproval: true, isRetryable: false
            ),
            AIWorkflowStep(
                id: UUID(), title: "Apply Reviewed", icon: "checkmark.circle.fill",
                kind: .apply, requiresApproval: false, isRetryable: true
            ),
            AIWorkflowStep(
                id: UUID(), title: "Summary", icon: "list.clipboard.fill",
                kind: .summary, requiresApproval: false, isRetryable: false
            ),
        ]

        return AIWorkflow(
            id: UUID(), type: .cleanupUncategorized, status: .running,
            steps: steps, currentStepIndex: 0,
            startedAt: Date(), updatedAt: Date(),
            title: "Cleanup Transactions",
            summary: "\(uncategorized.count) uncategorized transaction(s) found",
            groupId: groupId
        )
    }

    private func buildBudgetRescueWorkflow(store: Store, groupId: UUID) -> AIWorkflow {
        let steps: [AIWorkflowStep] = [
            AIWorkflowStep(
                id: UUID(), title: "Analyze Budget", icon: "chart.bar.fill",
                kind: .analyze, requiresApproval: false, isRetryable: false
            ),
            AIWorkflowStep(
                id: UUID(), title: "Prepare Rescue Plan", icon: "wand.and.stars",
                kind: .review, requiresApproval: true, isRetryable: false
            ),
            AIWorkflowStep(
                id: UUID(), title: "Apply Changes", icon: "checkmark.circle.fill",
                kind: .apply, requiresApproval: false, isRetryable: true
            ),
            AIWorkflowStep(
                id: UUID(), title: "Summary", icon: "list.clipboard.fill",
                kind: .summary, requiresApproval: false, isRetryable: false
            ),
        ]

        return AIWorkflow(
            id: UUID(), type: .budgetRescue, status: .running,
            steps: steps, currentStepIndex: 0,
            startedAt: Date(), updatedAt: Date(),
            title: "Budget Rescue",
            summary: "Rebalance over-budget categories",
            groupId: groupId
        )
    }

    private func buildMonthlyCloseWorkflow(store: Store, groupId: UUID) -> AIWorkflow {
        let steps: [AIWorkflowStep] = [
            AIWorkflowStep(
                id: UUID(), title: "Cleanup Check", icon: "magnifyingglass",
                kind: .analyze, requiresApproval: false, isRetryable: false
            ),
            AIWorkflowStep(
                id: UUID(), title: "Auto-Fix Transactions", icon: "bolt.fill",
                kind: .autoExecute, requiresApproval: false, isRetryable: true
            ),
            AIWorkflowStep(
                id: UUID(), title: "Month Review", icon: "chart.pie.fill",
                kind: .analyze, requiresApproval: false, isRetryable: false
            ),
            AIWorkflowStep(
                id: UUID(), title: "Next Month Budget", icon: "calendar.badge.plus",
                kind: .review, requiresApproval: true, isRetryable: false
            ),
            AIWorkflowStep(
                id: UUID(), title: "Apply Budget", icon: "checkmark.circle.fill",
                kind: .apply, requiresApproval: false, isRetryable: true
            ),
            AIWorkflowStep(
                id: UUID(), title: "Month Closed", icon: "flag.checkered",
                kind: .summary, requiresApproval: false, isRetryable: false
            ),
        ]

        return AIWorkflow(
            id: UUID(), type: .monthlyClose, status: .running,
            steps: steps, currentStepIndex: 0,
            startedAt: Date(), updatedAt: Date(),
            title: "Monthly Close",
            summary: "Close out this month and prepare next",
            groupId: groupId
        )
    }

    private func buildSubscriptionReviewWorkflow(groupId: UUID) -> AIWorkflow {
        let steps: [AIWorkflowStep] = [
            AIWorkflowStep(
                id: UUID(), title: "Scan Subscriptions", icon: "repeat",
                kind: .analyze, requiresApproval: false, isRetryable: false
            ),
            AIWorkflowStep(
                id: UUID(), title: "Review Findings", icon: "lightbulb.fill",
                kind: .review, requiresApproval: true, isRetryable: false
            ),
            AIWorkflowStep(
                id: UUID(), title: "Summary", icon: "list.clipboard.fill",
                kind: .summary, requiresApproval: false, isRetryable: false
            ),
        ]

        return AIWorkflow(
            id: UUID(), type: .subscriptionReview, status: .running,
            steps: steps, currentStepIndex: 0,
            startedAt: Date(), updatedAt: Date(),
            title: "Subscription Review",
            summary: "Review and optimize recurring charges",
            groupId: groupId
        )
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Cleanup Uncategorized — Step Handlers
    // ══════════════════════════════════════════════════════════

    private func executeCleanupStep(stepIndex: Int, store: inout Store) async throws {
        guard let workflow = activeWorkflow else { return }
        let step = workflow.steps[stepIndex]

        switch stepIndex {
        case 0: // Scan
            let month = store.selectedMonth
            let uncategorized = monthTransactions(store: store, month: month)
                .filter { $0.category == .other }

            if uncategorized.isEmpty {
                updateCurrentStep { s in
                    s.resultMessage = "All transactions are already categorized!"
                    s.detailLines = ["No cleanup needed this month."]
                }
                markCurrentStepCompleted()
                // Skip remaining steps
                skipRemainingSteps()
                return
            }

            // Classify into high-confidence and low-confidence
            var highConf: [ProposedItem] = []
            var lowConf: [ProposedItem] = []

            for txn in uncategorized {
                if let suggestion = suggestCategory(for: txn) {
                    let item = ProposedItem(
                        id: UUID(),
                        summary: "\(txn.note.isEmpty ? "Unknown" : txn.note) → \(suggestion.category.title)",
                        detail: "\(fmtCents(txn.amount)) on \(fmtDate(txn.date))",
                        isApproved: true,
                        isHighConfidence: suggestion.confidence >= 0.75,
                        action: AIAction(
                            type: .editTransaction,
                            params: AIAction.ActionParams(
                                category: suggestion.category.storageKey,
                                transactionId: txn.id.uuidString
                            )
                        ),
                        categoryKey: suggestion.category.storageKey
                    )

                    if suggestion.confidence >= 0.75 {
                        highConf.append(item)
                    } else {
                        lowConf.append(item)
                    }
                } else {
                    lowConf.append(ProposedItem(
                        id: UUID(),
                        summary: "\(txn.note.isEmpty ? "Unknown" : txn.note) — no suggestion",
                        detail: "\(fmtCents(txn.amount)) on \(fmtDate(txn.date))",
                        isApproved: false,
                        isHighConfidence: false
                    ))
                }
            }

            updateCurrentStep { s in
                s.resultMessage = "Found \(uncategorized.count) uncategorized transaction(s)"
                s.detailLines = [
                    "\(highConf.count) can be auto-fixed (high confidence)",
                    "\(lowConf.count) need your review"
                ]
                // Store proposals in the next steps
            }

            // Populate step 1 (auto) and step 2 (review)
            if var wf = activeWorkflow {
                if wf.steps.count > 1 { wf.steps[1].proposedItems = highConf }
                if wf.steps.count > 2 { wf.steps[2].proposedItems = lowConf }
                activeWorkflow = wf
            }

            markCurrentStepCompleted()

        case 1: // Auto-categorize safe (high confidence)
            let items = step.proposedItems.filter { $0.isApproved && $0.action != nil }

            if items.isEmpty {
                updateCurrentStep { s in
                    s.resultMessage = "No high-confidence fixes to apply"
                }
                markCurrentStepCompleted()
                return
            }

            var executed = 0
            var failed = 0
            for item in items {
                guard let action = item.action else { continue }
                let result = await AIActionExecutor.execute(action, store: &store)
                if result.success {
                    executed += 1
                    recordAction(action: action, result: result, isAutoExecuted: true)
                } else {
                    failed += 1
                }
            }

            updateCurrentStep { s in
                s.executedCount = executed
                s.failedCount = failed
                s.resultMessage = "Auto-categorized \(executed) transaction(s)"
                if failed > 0 {
                    s.detailLines.append("\(failed) failed")
                }
            }
            markCurrentStepCompleted()

        case 2: // Review uncertain (pause for approval)
            let items = step.proposedItems
            if items.isEmpty || items.allSatisfy({ $0.action == nil }) {
                updateCurrentStep { s in
                    s.resultMessage = "No uncertain items to review"
                }
                markCurrentStepCompleted()
                return
            }

            updateCurrentStep { s in
                s.resultMessage = "Review \(items.count) uncertain categorization(s)"
            }
            pauseForApproval(message: "Toggle items you want to apply, then continue.")

        case 3: // Apply reviewed
            guard let reviewStep = activeWorkflow?.steps[safe: 2] else {
                markCurrentStepCompleted()
                return
            }

            let approved = reviewStep.proposedItems.filter { $0.isApproved && $0.action != nil }
            let skippedN = reviewStep.proposedItems.count - approved.count

            var executed = 0
            var failed = 0
            for item in approved {
                guard let action = item.action else { continue }
                let result = await AIActionExecutor.execute(action, store: &store)
                if result.success {
                    executed += 1
                    recordAction(action: action, result: result, isAutoExecuted: false)
                } else {
                    failed += 1
                }
            }

            updateCurrentStep { s in
                s.executedCount = executed
                s.skippedCount = skippedN
                s.failedCount = failed
                s.resultMessage = "Applied \(executed) categorization(s)"
                if skippedN > 0 { s.detailLines.append("\(skippedN) skipped") }
                if failed > 0 { s.detailLines.append("\(failed) failed") }
            }
            markCurrentStepCompleted()

        case 4: // Summary
            let totalExecuted = (activeWorkflow?.steps ?? [])
                .reduce(0) { $0 + $1.executedCount }
            let totalSkipped = (activeWorkflow?.steps ?? [])
                .reduce(0) { $0 + $1.skippedCount }

            updateCurrentStep { s in
                s.resultMessage = "Cleanup complete!"
                s.detailLines = [
                    "\(totalExecuted) transaction(s) categorized",
                    "\(totalSkipped) skipped"
                ]
            }
            markCurrentStepCompleted()

        default:
            markCurrentStepCompleted()
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Budget Rescue — Step Handlers
    // ══════════════════════════════════════════════════════════

    private func executeBudgetRescueStep(stepIndex: Int, store: inout Store) async throws {
        guard let workflow = activeWorkflow else { return }
        let step = workflow.steps[stepIndex]
        let month = store.selectedMonth
        let monthKey = Store.monthKey(month)

        switch stepIndex {
        case 0: // Analyze
            let budget = store.budgetsByMonth[monthKey] ?? 0
            let spent = store.spent(for: month)
            let expenses = monthTransactions(store: store, month: month)
                .filter { $0.type == .expense }

            // Category breakdown
            var catSpending: [(key: String, title: String, spent: Int, budget: Int)] = []
            var catTotals: [String: Int] = [:]
            for t in expenses {
                catTotals[t.category.storageKey, default: 0] += t.amount
            }

            let catBudgets = store.categoryBudgetsByMonth[monthKey] ?? [:]

            for (catKey, amount) in catTotals.sorted(by: { $0.value > $1.value }) {
                let catTitle = Category(storageKey: catKey)?.title ?? catKey
                let catBudget = catBudgets[catKey] ?? 0
                catSpending.append((key: catKey, title: catTitle, spent: amount, budget: catBudget))
            }

            // Find over-budget categories
            let overBudget = catSpending.filter { $0.budget > 0 && $0.spent > $0.budget }

            var lines: [String] = []
            if budget > 0 {
                let pct = spent * 100 / max(budget, 1)
                lines.append("Budget: \(fmtCents(budget)) | Spent: \(fmtCents(spent)) (\(pct)%)")
                if spent > budget {
                    lines.append("Over budget by \(fmtCents(spent - budget))")
                }
            } else {
                lines.append("No budget set. Total spending: \(fmtCents(spent))")
            }

            if !overBudget.isEmpty {
                lines.append("")
                lines.append("Over-budget categories:")
                for cat in overBudget {
                    let over = cat.spent - cat.budget
                    lines.append("  \(cat.title): \(fmtCents(cat.spent)) / \(fmtCents(cat.budget)) (+\(fmtCents(over)))")
                }
            }

            lines.append("")
            lines.append("Top spending:")
            for cat in catSpending.prefix(5) {
                lines.append("  \(cat.title): \(fmtCents(cat.spent))")
            }

            updateCurrentStep { s in
                s.resultMessage = budget > 0 && spent > budget
                    ? "Over budget by \(fmtCents(spent - budget))"
                    : "Budget analysis complete"
                s.detailLines = lines
            }

            // Build rescue proposals for step 1
            var proposals: [ProposedItem] = []
            let essentialKeys = Set(["rent", "bills", "health"])

            for cat in catSpending where !essentialKeys.contains(cat.key) {
                let suggestedBudget: Int
                if cat.budget > 0 && cat.spent > cat.budget {
                    // Over-budget: suggest halfway between current budget and actual spend
                    suggestedBudget = (cat.budget + cat.spent) / 2
                } else if cat.budget == 0 && budget > 0 {
                    // No category budget: suggest based on actual spending + 10% buffer
                    suggestedBudget = Int(Double(cat.spent) * 1.1)
                } else {
                    continue
                }

                proposals.append(ProposedItem(
                    id: UUID(),
                    summary: "Set \(cat.title) budget to \(fmtCents(suggestedBudget))",
                    detail: "Currently: \(fmtCents(cat.spent)) spent" +
                        (cat.budget > 0 ? " / \(fmtCents(cat.budget)) budgeted" : " (no budget)"),
                    isApproved: true,
                    isHighConfidence: true,
                    action: AIAction(
                        type: .setCategoryBudget,
                        params: AIAction.ActionParams(
                            budgetAmount: suggestedBudget,
                            budgetMonth: monthKey,
                            budgetCategory: cat.key
                        )
                    ),
                    amountCents: suggestedBudget,
                    categoryKey: cat.key
                ))
            }

            // Also suggest overall budget adjustment if over
            if budget > 0 && spent > budget {
                let nextMonthBudget = Int(Double(spent) * 1.1) // 10% above actual
                if let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: month) {
                    let nextKey = Store.monthKey(nextMonth)
                    proposals.append(ProposedItem(
                        id: UUID(),
                        summary: "Set next month's budget to \(fmtCents(nextMonthBudget))",
                        detail: "Based on actual spending + 10% buffer",
                        isApproved: true,
                        isHighConfidence: true,
                        action: AIAction(
                            type: .setBudget,
                            params: AIAction.ActionParams(
                                budgetAmount: nextMonthBudget,
                                budgetMonth: nextKey
                            )
                        ),
                        amountCents: nextMonthBudget
                    ))
                }
            }

            // Store proposals in step 1
            if var wf = activeWorkflow, wf.steps.count > 1 {
                wf.steps[1].proposedItems = proposals
                activeWorkflow = wf
            }

            markCurrentStepCompleted()

        case 1: // Prepare rescue plan (review + approve)
            let proposals = step.proposedItems
            if proposals.isEmpty {
                updateCurrentStep { s in
                    s.resultMessage = "No budget adjustments needed"
                    s.detailLines = ["Your spending looks on track."]
                }
                markCurrentStepCompleted()
                return
            }

            updateCurrentStep { s in
                s.resultMessage = "\(proposals.count) budget adjustment(s) proposed"
            }
            pauseForApproval(message: "Review the changes below, then approve to continue.")

        case 2: // Apply changes
            guard let reviewStep = activeWorkflow?.steps[safe: 1] else {
                markCurrentStepCompleted()
                return
            }

            let approved = reviewStep.proposedItems.filter { $0.isApproved && $0.action != nil }
            let skippedN = reviewStep.proposedItems.count - approved.count

            var executed = 0
            var failed = 0
            for item in approved {
                guard let action = item.action else { continue }
                let result = await AIActionExecutor.execute(action, store: &store)
                if result.success {
                    executed += 1
                    recordAction(action: action, result: result, isAutoExecuted: false)
                } else {
                    failed += 1
                }
            }

            updateCurrentStep { s in
                s.executedCount = executed
                s.skippedCount = skippedN
                s.failedCount = failed
                s.resultMessage = "Applied \(executed) budget change(s)"
                if skippedN > 0 { s.detailLines.append("\(skippedN) skipped") }
                if failed > 0 { s.detailLines.append("\(failed) failed") }
            }
            markCurrentStepCompleted()

        case 3: // Summary
            let totalExecuted = (activeWorkflow?.steps ?? []).reduce(0) { $0 + $1.executedCount }
            updateCurrentStep { s in
                s.resultMessage = "Budget rescue complete!"
                s.detailLines = ["\(totalExecuted) budget change(s) applied"]
            }
            markCurrentStepCompleted()

        default:
            markCurrentStepCompleted()
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Monthly Close — Step Handlers
    // ══════════════════════════════════════════════════════════

    private func executeMonthlyCloseStep(stepIndex: Int, store: inout Store) async throws {
        guard let workflow = activeWorkflow else { return }
        let step = workflow.steps[stepIndex]
        let month = store.selectedMonth
        let monthKey = Store.monthKey(month)
        let cal = Calendar.current

        switch stepIndex {
        case 0: // Cleanup check
            let allTxns = monthTransactions(store: store, month: month)
            let uncategorized = allTxns.filter { $0.category == .other }
            let expenses = allTxns.filter { $0.type == .expense }

            // Detect anomalies: transactions significantly larger than category average
            var anomalies: [String] = []
            var catAmounts: [String: [Int]] = [:]
            for t in expenses { catAmounts[t.category.title, default: []].append(t.amount) }
            for (cat, amounts) in catAmounts where amounts.count >= 3 {
                let avg = amounts.reduce(0, +) / amounts.count
                let outliers = amounts.filter { $0 > avg * 3 }
                if !outliers.isEmpty {
                    anomalies.append("\(cat): \(outliers.count) unusually large transaction(s)")
                }
            }

            // Build categorization proposals for step 1
            var autoFixItems: [ProposedItem] = []
            for txn in uncategorized {
                if let suggestion = suggestCategory(for: txn), suggestion.confidence >= 0.75 {
                    autoFixItems.append(ProposedItem(
                        id: UUID(),
                        summary: "\(txn.note.isEmpty ? "Unknown" : txn.note) → \(suggestion.category.title)",
                        detail: fmtCents(txn.amount),
                        isApproved: true,
                        isHighConfidence: true,
                        action: AIAction(
                            type: .editTransaction,
                            params: AIAction.ActionParams(
                                category: suggestion.category.storageKey,
                                transactionId: txn.id.uuidString
                            )
                        )
                    ))
                }
            }

            // Populate step 1
            if var wf = activeWorkflow, wf.steps.count > 1 {
                wf.steps[1].proposedItems = autoFixItems
                activeWorkflow = wf
            }

            var lines: [String] = [
                "\(allTxns.count) transaction(s) this month",
                "\(uncategorized.count) uncategorized"
            ]
            if !autoFixItems.isEmpty {
                lines.append("\(autoFixItems.count) can be auto-fixed")
            }
            if !anomalies.isEmpty {
                lines.append("")
                lines.append("Anomalies detected:")
                lines.append(contentsOf: anomalies.map { "  ⚠️ \($0)" })
            }

            updateCurrentStep { s in
                s.resultMessage = uncategorized.isEmpty
                    ? "All transactions categorized"
                    : "\(uncategorized.count) uncategorized found"
                s.detailLines = lines
            }
            markCurrentStepCompleted()

        case 1: // Auto-fix
            let items = step.proposedItems.filter { $0.isApproved && $0.action != nil }
            if items.isEmpty {
                updateCurrentStep { s in
                    s.resultMessage = "Nothing to auto-fix"
                }
                markCurrentStepCompleted()
                return
            }

            var executed = 0
            var failed = 0
            for item in items {
                guard let action = item.action else { continue }
                let result = await AIActionExecutor.execute(action, store: &store)
                if result.success {
                    executed += 1
                    recordAction(action: action, result: result, isAutoExecuted: true)
                } else {
                    failed += 1
                }
            }

            updateCurrentStep { s in
                s.executedCount = executed
                s.failedCount = failed
                s.resultMessage = "Auto-fixed \(executed) transaction(s)"
            }
            markCurrentStepCompleted()

        case 2: // Month review (spending summary)
            let budget = store.budgetsByMonth[monthKey] ?? 0
            let spent = store.spent(for: month)
            let income = store.income(for: month)
            let remaining = store.remaining(for: month)

            let expenses = monthTransactions(store: store, month: month)
                .filter { $0.type == .expense }
            var catTotals: [String: Int] = [:]
            for t in expenses { catTotals[t.category.title, default: 0] += t.amount }
            let sorted = catTotals.sorted { $0.value > $1.value }

            var lines: [String] = []
            if budget > 0 {
                let pct = spent * 100 / max(budget, 1)
                lines.append("Budget: \(fmtCents(budget)) | Spent: \(fmtCents(spent)) (\(pct)%)")
            } else {
                lines.append("Total spent: \(fmtCents(spent))")
            }
            if income > 0 { lines.append("Income: \(fmtCents(income))") }
            lines.append("Remaining: \(fmtCents(remaining))")
            lines.append("")
            lines.append("Top categories:")
            for (cat, amount) in sorted.prefix(5) {
                lines.append("  \(cat): \(fmtCents(amount))")
            }

            // Prepare next month budget proposal for step 3
            var proposals: [ProposedItem] = []
            if let nextMonth = cal.date(byAdding: .month, value: 1, to: month) {
                let nextKey = Store.monthKey(nextMonth)
                let existingNext = store.budgetsByMonth[nextKey]

                if existingNext == nil || existingNext == 0 {
                    // Suggest budget based on this month
                    let suggested: Int
                    if budget > 0 && spent <= budget {
                        suggested = budget // Keep same
                    } else if budget > 0 {
                        suggested = Int(Double(spent) * 1.05) // 5% above actual
                    } else {
                        suggested = Int(Double(spent) * 1.1) // 10% above actual
                    }

                    if suggested > 0 {
                        proposals.append(ProposedItem(
                            id: UUID(),
                            summary: "Set next month's budget: \(fmtCents(suggested))",
                            detail: budget > 0
                                ? "Current: \(fmtCents(budget)) | Actual: \(fmtCents(spent))"
                                : "Based on this month's spending + buffer",
                            isApproved: true,
                            isHighConfidence: true,
                            action: AIAction(
                                type: .setBudget,
                                params: AIAction.ActionParams(
                                    budgetAmount: suggested,
                                    budgetMonth: nextKey
                                )
                            ),
                            amountCents: suggested
                        ))
                    }

                    // Suggest category budgets for top categories
                    for (cat, amount) in sorted.prefix(4) {
                        let catKey = expenses.first { $0.category.title == cat }?.category.storageKey ?? cat.lowercased()
                        let suggestedCat = Int(Double(amount) * 1.05)
                        proposals.append(ProposedItem(
                            id: UUID(),
                            summary: "\(cat) budget: \(fmtCents(suggestedCat))",
                            detail: "Spent \(fmtCents(amount)) this month",
                            isApproved: false, // Off by default — user opts in
                            isHighConfidence: false,
                            action: AIAction(
                                type: .setCategoryBudget,
                                params: AIAction.ActionParams(
                                    budgetAmount: suggestedCat,
                                    budgetMonth: nextKey,
                                    budgetCategory: catKey
                                )
                            ),
                            amountCents: suggestedCat,
                            categoryKey: catKey
                        ))
                    }
                }
            }

            // Store in step 3
            if var wf = activeWorkflow, wf.steps.count > 3 {
                wf.steps[3].proposedItems = proposals
                activeWorkflow = wf
            }

            updateCurrentStep { s in
                s.resultMessage = budget > 0
                    ? "Spent \(spent * 100 / max(budget, 1))% of budget"
                    : "Month spending: \(fmtCents(spent))"
                s.detailLines = lines
            }
            markCurrentStepCompleted()

        case 3: // Next month budget (review)
            let proposals = step.proposedItems
            if proposals.isEmpty {
                updateCurrentStep { s in
                    s.resultMessage = "Next month budget already set"
                }
                markCurrentStepCompleted()
                return
            }

            updateCurrentStep { s in
                s.resultMessage = "\(proposals.count) budget suggestion(s)"
            }
            pauseForApproval(message: "Review budget suggestions for next month.")

        case 4: // Apply budget
            guard let reviewStep = activeWorkflow?.steps[safe: 3] else {
                markCurrentStepCompleted()
                return
            }

            let approved = reviewStep.proposedItems.filter { $0.isApproved && $0.action != nil }
            let skippedN = reviewStep.proposedItems.count - approved.count

            var executed = 0
            var failed = 0
            for item in approved {
                guard let action = item.action else { continue }
                let result = await AIActionExecutor.execute(action, store: &store)
                if result.success {
                    executed += 1
                    recordAction(action: action, result: result, isAutoExecuted: false)
                } else {
                    failed += 1
                }
            }

            updateCurrentStep { s in
                s.executedCount = executed
                s.skippedCount = skippedN
                s.failedCount = failed
                s.resultMessage = "Applied \(executed) budget change(s)"
            }
            markCurrentStepCompleted()

        case 5: // Summary
            let autoFixed = activeWorkflow?.steps[safe: 1]?.executedCount ?? 0
            let budgetChanges = activeWorkflow?.steps[safe: 4]?.executedCount ?? 0
            let budget = store.budgetsByMonth[monthKey] ?? 0
            let spent = store.spent(for: month)

            var lines: [String] = []
            if autoFixed > 0 { lines.append("\(autoFixed) transaction(s) auto-categorized") }
            if budgetChanges > 0 { lines.append("\(budgetChanges) budget change(s) applied") }
            if budget > 0 {
                let saved = max(0, budget - spent)
                if saved > 0 { lines.append("Saved \(fmtCents(saved)) this month") }
            }
            if lines.isEmpty { lines.append("Month reviewed — no changes needed") }

            updateCurrentStep { s in
                s.resultMessage = "Month closed!"
                s.detailLines = lines
            }
            markCurrentStepCompleted()

        default:
            markCurrentStepCompleted()
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Subscription Review — Step Handlers
    // ══════════════════════════════════════════════════════════

    private func executeSubscriptionStep(stepIndex: Int, store: inout Store) async throws {
        switch stepIndex {
        case 0: // Scan
            let subs = SubscriptionEngine.shared.subscriptions.filter { $0.status == .active }
            let recurring = store.recurringTransactions

            var lines: [String] = [
                "\(subs.count) active subscription(s)",
                "\(recurring.count) recurring transaction(s)"
            ]

            let totalMonthly = subs.reduce(0) { $0 + $1.monthlyCost }
            if totalMonthly > 0 {
                lines.append("Total: \(fmtCents(totalMonthly))/month")
            }

            lines.append("")
            for sub in subs.prefix(8) {
                lines.append("  \(sub.merchantName): \(fmtCents(sub.expectedAmount))/\(sub.billingCycle.rawValue)")
            }

            // Build review items for step 1
            var proposals: [ProposedItem] = []
            for sub in subs {
                proposals.append(ProposedItem(
                    id: UUID(),
                    summary: "\(sub.merchantName) — \(fmtCents(sub.expectedAmount))/\(sub.billingCycle.rawValue)",
                    detail: "Active since detection",
                    isApproved: false,  // User must opt-in to cancel
                    isHighConfidence: false
                ))
            }

            if var wf = activeWorkflow, wf.steps.count > 1 {
                wf.steps[1].proposedItems = proposals
                activeWorkflow = wf
            }

            updateCurrentStep { s in
                s.resultMessage = "\(subs.count) subscription(s) found"
                s.detailLines = lines
            }
            markCurrentStepCompleted()

        case 1: // Review
            let proposals = activeWorkflow?.steps[safe: 1]?.proposedItems ?? []
            if proposals.isEmpty {
                updateCurrentStep { s in
                    s.resultMessage = "No subscriptions to review"
                }
                markCurrentStepCompleted()
                return
            }

            updateCurrentStep { s in
                s.resultMessage = "Review your subscriptions"
            }
            pauseForApproval(message: "Flag subscriptions you want to reconsider.")

        case 2: // Summary
            let flagged = activeWorkflow?.steps[safe: 1]?.proposedItems.filter(\.isApproved).count ?? 0
            updateCurrentStep { s in
                s.resultMessage = "Review complete!"
                s.detailLines = flagged > 0
                    ? ["\(flagged) subscription(s) flagged for action"]
                    : ["No changes — all subscriptions look good"]
            }
            markCurrentStepCompleted()

        default:
            markCurrentStepCompleted()
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Helpers
    // ══════════════════════════════════════════════════════════

    private func monthTransactions(store: Store, month: Date) -> [Transaction] {
        let cal = Calendar.current
        return store.transactions.filter {
            cal.isDate($0.date, equalTo: month, toGranularity: .month)
        }
    }

    private func suggestCategory(for txn: Transaction) -> (category: Category, confidence: Double)? {
        // Try merchant memory first (highest confidence)
        if let result = merchantMemory.suggestCategory(for: txn.note),
           let cat = Category(storageKey: result.category) {
            return (cat, result.confidence)
        }
        // Fall back to keyword-based suggester
        return categorySuggester.suggestWithConfidence(note: txn.note)
    }

    /// Record an executed action to the audit history.
    private func recordAction(action: AIAction, result: AIActionExecutor.ExecutionResult, isAutoExecuted: Bool) {
        guard let workflow = activeWorkflow else { return }
        actionHistory.record(
            action: action,
            result: result,
            trustDecision: nil,     // Workflow engine manages trust via step structure
            classification: nil,
            groupId: workflow.groupId,
            groupLabel: workflow.title,
            isAutoExecuted: isAutoExecuted
        )
    }

    private func skipRemainingSteps() {
        guard var workflow = activeWorkflow else { return }
        for i in (workflow.currentStepIndex + 1)..<workflow.steps.count {
            if workflow.steps[i].status == .pending {
                workflow.steps[i].status = .skipped
            }
        }
        workflow.status = .completed
        workflow.completedAt = Date()
        workflow.updatedAt = Date()
        activeWorkflow = workflow
    }

    private func fmtCents(_ cents: Int) -> String {
        let isNegative = cents < 0
        let abs = abs(cents)
        let str = String(format: "$%.2f", Double(abs) / 100.0)
        return isNegative ? "-\(str)" : str
    }

    private func fmtDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: - Safe Array Subscript
// ══════════════════════════════════════════════════════════════

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
