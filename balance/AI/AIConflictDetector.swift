import Foundation

// ============================================================
// MARK: - AI Conflict Detector
// ============================================================
//
// Phase 4 deliverable: detects potential conflicts, duplicates,
// and safety issues BEFORE actions are executed.
//
// Runs after parsing, before trust classification.
// Returns warnings (proceed with caution) or blocks (don't execute).
//
// ============================================================

/// Result of conflict detection.
struct ConflictResult {
    let warnings: [ConflictWarning]
    let blocks: [ConflictBlock]

    var hasIssues: Bool { !warnings.isEmpty || !blocks.isEmpty }
    var isBlocked: Bool { !blocks.isEmpty }

    /// Combine all user-facing messages.
    var summaryText: String {
        var lines: [String] = []
        for block in blocks {
            lines.append("⛔ \(block.message)")
        }
        for warning in warnings {
            lines.append("⚠️ \(warning.message)")
        }
        return lines.joined(separator: "\n")
    }
}

struct ConflictWarning {
    let type: WarningType
    let message: String
    let actionIndex: Int?  // Which action triggered this, nil if global

    enum WarningType {
        case duplicateTransaction   // Same amount+category+date already exists
        case budgetExceeded         // This transaction would exceed budget
        case largeAmount            // Unusually large amount
        case recentSimilar          // Very similar action was just done
        case goalOvercontribution   // Contribution exceeds remaining goal target
        case futureDate             // Transaction date is in the future
        case oldDate                // Transaction date is >1 year ago
    }
}

struct ConflictBlock {
    let type: BlockType
    let message: String
    let actionIndex: Int?

    enum BlockType {
        case missingTransactionId   // Edit/delete without valid ID
        case transactionNotFound    // ID doesn't match any transaction
        case goalNotFound           // Goal name doesn't match
        case subscriptionNotFound   // Subscription not found for cancel
        case accountNotFound        // Account name doesn't match
        case zeroAmount             // Amount is 0
        case incompleteContext      // Not enough data to safely proceed
    }
}

@MainActor
enum AIConflictDetector {

    // MARK: - Detect

    /// Analyze proposed actions against current app state.
    static func detect(
        actions: [AIAction],
        store: Store
    ) -> ConflictResult {
        var warnings: [ConflictWarning] = []
        var blocks: [ConflictBlock] = []

        for (index, action) in actions.enumerated() {
            let p = action.params

            switch action.type {

            // ── Transactions ──

            case .addTransaction, .splitTransaction:
                // Zero amount
                if let amount = p.amount, amount == 0 {
                    blocks.append(ConflictBlock(
                        type: .zeroAmount,
                        message: "Transaction amount can't be zero.",
                        actionIndex: index
                    ))
                }

                // Duplicate check
                if let amount = p.amount {
                    let date = resolveDate(p.date)
                    let cat = p.category ?? ""
                    let isDuplicate = store.transactions.contains { txn in
                        txn.amount == amount &&
                        txn.category.storageKey == cat &&
                        Calendar.current.isDate(txn.date, inSameDayAs: date)
                    }
                    if isDuplicate {
                        warnings.append(ConflictWarning(
                            type: .duplicateTransaction,
                            message: "A similar transaction already exists today (\(formatCents(amount)) in \(cat)).",
                            actionIndex: index
                        ))
                    }
                }

                // Budget exceeded check
                if let amount = p.amount, p.transactionType != "income" {
                    let monthKey = currentMonthKey()
                    if let budget = store.budgetsByMonth[monthKey], budget > 0 {
                        let currentSpent = store.spent(for: Date())
                        if currentSpent + amount > budget {
                            let over = currentSpent + amount - budget
                            warnings.append(ConflictWarning(
                                type: .budgetExceeded,
                                message: "This would put you \(formatCents(over)) over budget.",
                                actionIndex: index
                            ))
                        }
                    }
                }

                // Large amount (>$10,000)
                if let amount = p.amount, amount > 1_000_000 {
                    warnings.append(ConflictWarning(
                        type: .largeAmount,
                        message: "Large amount: \(formatCents(amount)).",
                        actionIndex: index
                    ))
                }

                // Future date
                if let dateStr = p.date {
                    let date = resolveDate(dateStr)
                    if date > Date().addingTimeInterval(86400) {
                        warnings.append(ConflictWarning(
                            type: .futureDate,
                            message: "Transaction date is in the future.",
                            actionIndex: index
                        ))
                    }
                }

                // Very old date (>1 year)
                if let dateStr = p.date {
                    let date = resolveDate(dateStr)
                    if date < Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date() {
                        warnings.append(ConflictWarning(
                            type: .oldDate,
                            message: "Transaction date is over a year ago.",
                            actionIndex: index
                        ))
                    }
                }

            case .editTransaction:
                if p.transactionId == nil {
                    blocks.append(ConflictBlock(
                        type: .missingTransactionId,
                        message: "Can't edit: no transaction specified.",
                        actionIndex: index
                    ))
                } else if let idStr = p.transactionId, let uuid = UUID(uuidString: idStr) {
                    if !store.transactions.contains(where: { $0.id == uuid }) {
                        blocks.append(ConflictBlock(
                            type: .transactionNotFound,
                            message: "Transaction not found for editing.",
                            actionIndex: index
                        ))
                    }
                }

            case .deleteTransaction:
                if p.transactionId == nil {
                    blocks.append(ConflictBlock(
                        type: .missingTransactionId,
                        message: "Can't delete: no transaction specified.",
                        actionIndex: index
                    ))
                } else if let idStr = p.transactionId, let uuid = UUID(uuidString: idStr) {
                    if !store.transactions.contains(where: { $0.id == uuid }) {
                        blocks.append(ConflictBlock(
                            type: .transactionNotFound,
                            message: "Transaction not found for deletion.",
                            actionIndex: index
                        ))
                    }
                }

            // ── Budget ──

            case .setBudget, .adjustBudget:
                if let amount = p.budgetAmount, amount == 0 {
                    warnings.append(ConflictWarning(
                        type: .largeAmount,
                        message: "Setting budget to $0 will effectively remove it.",
                        actionIndex: index
                    ))
                }

            case .setCategoryBudget:
                if p.budgetCategory == nil {
                    blocks.append(ConflictBlock(
                        type: .incompleteContext,
                        message: "No category specified for category budget.",
                        actionIndex: index
                    ))
                }

            // ── Goals ──

            case .addContribution:
                if let goalName = p.goalName {
                    let goal = GoalManager.shared.goals.first(where: {
                        $0.name.localizedCaseInsensitiveCompare(goalName) == .orderedSame
                    })
                    if goal == nil {
                        blocks.append(ConflictBlock(
                            type: .goalNotFound,
                            message: "Goal \"\(goalName)\" not found.",
                            actionIndex: index
                        ))
                    } else if let goal, let contrib = p.contributionAmount {
                        let remaining = goal.targetAmount - goal.currentAmount
                        if contrib > remaining && remaining > 0 {
                            warnings.append(ConflictWarning(
                                type: .goalOvercontribution,
                                message: "This exceeds the remaining \(formatCents(remaining)) for \"\(goalName)\".",
                                actionIndex: index
                            ))
                        }
                    }
                }

            case .updateGoal:
                if let goalName = p.goalName {
                    if !GoalManager.shared.goals.contains(where: {
                        $0.name.localizedCaseInsensitiveCompare(goalName) == .orderedSame
                    }) {
                        blocks.append(ConflictBlock(
                            type: .goalNotFound,
                            message: "Goal \"\(goalName)\" not found.",
                            actionIndex: index
                        ))
                    }
                }

            // ── Subscriptions ──

            case .cancelSubscription:
                if let name = p.subscriptionName {
                    if !SubscriptionEngine.shared.subscriptions.contains(where: {
                        $0.merchantName.localizedCaseInsensitiveCompare(name) == .orderedSame
                    }) {
                        blocks.append(ConflictBlock(
                            type: .subscriptionNotFound,
                            message: "Subscription \"\(name)\" not found.",
                            actionIndex: index
                        ))
                    }
                }

            // ── Accounts ──

            case .updateBalance:
                if let name = p.accountName {
                    if !AccountManager.shared.accounts.contains(where: {
                        $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                    }) {
                        blocks.append(ConflictBlock(
                            type: .accountNotFound,
                            message: "Account \"\(name)\" not found.",
                            actionIndex: index
                        ))
                    }
                }

            // ── Transfers ──
            case .transfer:
                if p.fromAccount == nil || p.toAccount == nil {
                    blocks.append(ConflictBlock(
                        type: .incompleteContext,
                        message: "Transfer needs both source and destination accounts.",
                        actionIndex: index
                    ))
                } else {
                    if let from = p.fromAccount,
                       !AccountManager.shared.accounts.contains(where: {
                           $0.name.localizedCaseInsensitiveCompare(from) == .orderedSame
                       }) {
                        blocks.append(ConflictBlock(
                            type: .accountNotFound,
                            message: "Source account \"\(from)\" not found.",
                            actionIndex: index
                        ))
                    }
                    if let to = p.toAccount,
                       !AccountManager.shared.accounts.contains(where: {
                           $0.name.localizedCaseInsensitiveCompare(to) == .orderedSame
                       }) {
                        blocks.append(ConflictBlock(
                            type: .accountNotFound,
                            message: "Destination account \"\(to)\" not found.",
                            actionIndex: index
                        ))
                    }
                }

            // ── Recurring ──
            case .cancelRecurring:
                if let name = p.recurringName ?? p.subscriptionName {
                    // Will be checked at execution time
                    _ = name
                }

            // ── Analysis & creation (no conflict checks needed) ──
            case .analyze, .compare, .forecast, .advice,
                 .createGoal, .addSubscription, .addRecurring, .editRecurring:
                break
            }

            // ── Cross-action: recent similar check ──
            let recentRecords = AIActionHistory.shared.records.prefix(5)
            for record in recentRecords {
                if record.action.type == action.type.rawValue,
                   record.action.amountCents == p.amount,
                   record.action.category == p.category,
                   record.executedAt.timeIntervalSinceNow > -60 { // Within last minute
                    warnings.append(ConflictWarning(
                        type: .recentSimilar,
                        message: "A very similar action was just executed.",
                        actionIndex: index
                    ))
                    break
                }
            }
        }

        return ConflictResult(warnings: warnings, blocks: blocks)
    }

    // MARK: - Dry Run

    /// Dry-run: simulate execution without mutating state.
    /// Returns a preview of what WOULD happen.
    static func dryRun(
        actions: [AIAction],
        store: Store
    ) -> [DryRunPreview] {
        var previews: [DryRunPreview] = []

        for action in actions {
            let p = action.params
            var preview = DryRunPreview(actionType: action.type.rawValue)

            switch action.type {
            case .addTransaction:
                let amount = p.amount ?? 0
                let monthKey = currentMonthKey()
                let currentSpent = store.spent(for: Date())
                let budget = store.budgetsByMonth[monthKey] ?? 0

                preview.beforeState = "Spent: \(formatCents(currentSpent))"
                preview.afterState = "Spent: \(formatCents(currentSpent + amount))"
                if budget > 0 {
                    let remaining = budget - currentSpent
                    let newRemaining = budget - (currentSpent + amount)
                    preview.impact = "Budget remaining: \(formatCents(remaining)) → \(formatCents(newRemaining))"
                }

            case .setBudget, .adjustBudget:
                let monthKey = currentMonthKey()
                let oldBudget = store.budgetsByMonth[monthKey] ?? 0
                let newBudget = p.budgetAmount ?? 0
                preview.beforeState = "Budget: \(formatCents(oldBudget))"
                preview.afterState = "Budget: \(formatCents(newBudget))"
                let diff = newBudget - oldBudget
                preview.impact = diff >= 0 ? "Increase of \(formatCents(diff))" : "Decrease of \(formatCents(abs(diff)))"

            case .addContribution:
                if let goalName = p.goalName,
                   let goal = GoalManager.shared.goals.first(where: {
                       $0.name.localizedCaseInsensitiveCompare(goalName) == .orderedSame
                   }),
                   let contrib = p.contributionAmount {
                    let pctBefore = goal.progressPercent
                    let pctAfter = min(100, Int(Double(goal.currentAmount + contrib) / Double(goal.targetAmount) * 100))
                    preview.beforeState = "\(goal.name): \(pctBefore)%"
                    preview.afterState = "\(goal.name): \(pctAfter)%"
                    preview.impact = "\(formatCents(contrib)) added"
                }

            default:
                preview.beforeState = "Current state"
                preview.afterState = "After \(action.type.rawValue)"
            }

            preview.isReversible = isReversible(action.type)
            previews.append(preview)
        }

        return previews
    }

    /// Whether an action type can be undone.
    static func isReversible(_ type: AIAction.ActionType) -> Bool {
        switch type {
        case .addTransaction, .editTransaction, .deleteTransaction,
             .splitTransaction, .setBudget, .adjustBudget, .setCategoryBudget,
             .createGoal, .addContribution, .addSubscription,
             .addRecurring, .editRecurring:
            return true
        case .cancelSubscription, .cancelRecurring, .updateGoal,
             .updateBalance, .transfer:
            return false // Harder to reverse cleanly
        case .analyze, .compare, .forecast, .advice:
            return true // No-op, nothing to reverse
        }
    }

    // MARK: - Helpers

    private static func resolveDate(_ raw: String?) -> Date {
        guard let raw else { return Date() }
        if raw.lowercased() == "today" { return Date() }
        if raw.lowercased() == "yesterday" {
            return Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: raw) ?? Date()
    }

    private static func currentMonthKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }

    private static func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}

/// Preview of what an action WOULD do (for dry-run mode).
struct DryRunPreview {
    let actionType: String
    var beforeState: String = ""
    var afterState: String = ""
    var impact: String = ""
    var isReversible: Bool = true
}
