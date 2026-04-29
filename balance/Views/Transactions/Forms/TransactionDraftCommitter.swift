import Foundation

// MARK: - Draft Commit Pipeline
//
// Phase 4 of the Add Transaction rebuild. A single funnel between the form
// (`TransactionDraftStore`) and the underlying mutation layer
// (`TransactionService`). Wraps validation, the actual store write, and the
// fan-out of secondary side-effects:
//
//   - merchant memory learning (passive on add, correction on edit)
//   - few-shot learning correction
//   - AI memory store correction tracking
//   - analytics events
//   - haptics
//   - Live Activity refresh
//   - allocation rule proposals (income only)
//
// Existing call sites still talk to `TransactionService` directly — Phase 6
// flips them over to this committer. Until then this file is purely additive.
//
// IMPORTANT: this layer never auto-applies allocation proposals. Per
// `feedback_confirm_every_action`, we hand them back in the result and the
// caller surfaces an approval sheet.

enum DraftCommitResult {
    /// Transaction saved. No further user-facing follow-up needed.
    case saved
    /// Transaction saved AND there are allocation rule proposals the caller
    /// should present to the user. Income flows hit this path when matching
    /// rules exist.
    case savedWithProposals([AllocationProposal])
    /// Edit ran but the diff was empty (or the original is gone). The caller
    /// should dismiss without showing success feedback.
    case noChange
    /// In-memory mutation succeeded but UserDefaults write failed. Caller
    /// should surface a "Save failed" alert; data lives only in memory.
    case localSaveFailed
    /// Pre-flight validation rejected the draft. Caller can highlight the
    /// fields named in the issue list.
    case validationFailed([DraftValidationIssue])
}

@MainActor
enum TransactionDraftCommitter {

    /// Commit the draft owned by `draftStore` into `appStore`. The store is
    /// `inout` because `TransactionService` is `inout` — both the in-memory
    /// mutation and the persistence are synchronous; balance/goal side-effects
    /// dispatched by `TransactionService` may still be in flight at return.
    @discardableResult
    static func commit(
        draftStore: TransactionDraftStore,
        appStore: inout Store
    ) -> DraftCommitResult {
        let hasAccounts = !AccountManager.shared.accounts.isEmpty
        switch draftStore.validate(hasAccounts: hasAccounts) {
        case .invalid(let issues):
            return .validationFailed(issues)
        case .ok:
            break
        }

        switch draftStore.mode {
        case .add:
            return commitAdd(draftStore: draftStore, appStore: &appStore)
        case .edit(let original):
            return commitEdit(original: original,
                              draftStore: draftStore,
                              appStore: &appStore)
        }
    }

    // MARK: - Add

    private static func commitAdd(
        draftStore: TransactionDraftStore,
        appStore: inout Store
    ) -> DraftCommitResult {
        let tx = draftStore.draft.buildTransaction()
        let result = TransactionService.performAdd(tx, store: &appStore)

        switch result {
        case .localSaveFailed:
            return .localSaveFailed
        case .noChange:
            // performAdd never returns .noChange (always mutates), but stay safe.
            return .noChange
        case .savedLocally:
            fireAddSideEffects(tx: tx, draftStore: draftStore, appStore: appStore)
            return resolveAddFollowups(tx: tx, in: appStore)
        }
    }

    private static func fireAddSideEffects(
        tx: Transaction,
        draftStore: TransactionDraftStore,
        appStore: Store
    ) {
        // Passive merchant memory — only learns from non-empty notes.
        if !tx.note.isEmpty {
            AIMerchantMemory.shared.learnFromTransaction(
                note: tx.note,
                category: tx.category.storageKey,
                amount: tx.amount
            )
        }

        Haptics.transactionAdded()
        AnalyticsManager.shared.track(.transactionAdded(isExpense: tx.type == .expense))
        AnalyticsManager.shared.checkFirstTransaction()

        BudgetLiveActivityManager.shared.refresh(store: appStore)
    }

    /// For income drafts, surface allocation rule proposals so the caller can
    /// open the existing approval sheet. Mirrors the pre-Phase-4 behavior in
    /// `AddTransactionSheet.saveTransaction`.
    private static func resolveAddFollowups(
        tx: Transaction,
        in appStore: Store
    ) -> DraftCommitResult {
        guard tx.type == .income else { return .saved }

        let alreadyAllocated = tx.linkedGoalId != nil ? tx.amount : 0
        let proposals = AllocationRuleEngine.proposals(
            for: tx,
            alreadyAllocated: alreadyAllocated,
            goals: GoalManager.shared.goals,
            in: appStore
        )
        return proposals.isEmpty ? .saved : .savedWithProposals(proposals)
    }

    // MARK: - Edit

    private static func commitEdit(
        original: Transaction,
        draftStore: TransactionDraftStore,
        appStore: inout Store
    ) -> DraftCommitResult {
        let diff = TransactionDraftDiff.between(original: original, draft: draftStore.draft)
        if diff.isEmpty { return .noChange }

        let new = draftStore.draft.buildTransaction()
        let result = TransactionService.performEdit(old: original, new: new, store: &appStore)

        switch result {
        case .noChange:
            return .noChange
        case .localSaveFailed:
            return .localSaveFailed
        case .savedLocally:
            fireEditSideEffects(old: original, new: new, diff: diff, appStore: appStore)
            return .saved
        }
    }

    private static func fireEditSideEffects(
        old: Transaction,
        new: Transaction,
        diff: TransactionDraftDiff,
        appStore: Store
    ) {
        // Phase 7: learn from category corrections — only when the user changed
        // the category AND the original had a note we can key off.
        if diff.categoryChanged && !old.note.isEmpty {
            AIMerchantMemory.shared.learnCorrection(
                merchantNote: old.note,
                correctCategory: new.category.storageKey
            )
            AIMemoryStore.shared.recordCorrection(
                merchant: old.note,
                fromCategory: old.category.storageKey,
                toCategory: new.category.storageKey
            )
            AIFewShotLearning.shared.recordCorrection(
                userMessage: old.note,
                originalAction: AIAction(
                    type: .addTransaction,
                    params: AIAction.ActionParams(
                        amount: old.amount,
                        category: old.category.storageKey,
                        note: old.note
                    )
                ),
                correctedCategory: new.category.storageKey
            )
        }

        Haptics.success()
        AnalyticsManager.shared.track(.transactionEdited)
        BudgetLiveActivityManager.shared.refresh(store: appStore)
    }
}
