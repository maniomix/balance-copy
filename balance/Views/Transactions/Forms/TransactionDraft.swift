import SwiftUI
import Combine

// MARK: - Source

/// Where this draft was opened from. Lets the commit pipeline route side-effects
/// (Live Activity refresh, analytics, AI confirm-card patches) without each
/// call site re-implementing them.
enum TransactionDraftSource: Equatable {
    case manual          // user tapped "+" anywhere in the app
    case dashboardFAB
    case accountDetail
    case aiConfirm       // pre-filled by an AI action card
    case appIntent       // Back Tap / Shortcuts / Live Activity refresh
}

// MARK: - Mode

enum TransactionDraftMode: Equatable {
    /// Brand-new transaction.
    case add
    /// Editing an existing transaction. Stores the original so the commit
    /// pipeline can compute a delta (balance, goal contribution, audit).
    case edit(original: Transaction)

    var isEdit: Bool {
        if case .edit = self { return true }
        return false
    }
}

// MARK: - Validation

enum DraftValidationIssue: Equatable {
    case amountMissing
    case amountNonPositive
    case categoryMissing      // expense with no real category (feedback_require_category)
    case accountMissing       // user has accounts but didn't pick one
    case noteTooLong
    case attachmentTooLarge

    var message: String {
        switch self {
        case .amountMissing:      return "Enter an amount."
        case .amountNonPositive:  return "Amount must be greater than zero."
        case .categoryMissing:    return "Pick a category."
        case .accountMissing:     return "Pick an account."
        case .noteTooLong:        return "Note is too long."
        case .attachmentTooLarge: return "Attachment is too large."
        }
    }
}

enum DraftValidation: Equatable {
    case ok
    case invalid([DraftValidationIssue])

    var isOK: Bool {
        if case .ok = self { return true }
        return false
    }

    var firstIssue: DraftValidationIssue? {
        if case .invalid(let issues) = self { return issues.first }
        return nil
    }
}

// MARK: - Draft

/// Plain value type holding every editable field of a transaction. Both the
/// Add and Edit flows bind to a single `TransactionDraft` so the form is one
/// implementation, not two.
///
/// Source-of-truth note: `amountText` is the user-facing field; the integer
/// cents value is derived via `amountCents`. We don't persist `amountText`.
struct TransactionDraft {
    // Identity (carried through edits, fresh for adds)
    var id: UUID

    // Hero fields
    var amountText: String
    var type: TransactionType
    var category: Category
    var date: Date
    var note: String

    // Details
    var paymentMethod: PaymentMethod
    var accountId: UUID?
    var linkedGoalId: UUID?

    // Attachment
    var attachmentData: Data?
    var attachmentType: AttachmentType?

    // Carried-through fields (edit only — UI never exposes them in this sheet)
    var isFlagged: Bool
    var transferGroupId: UUID?

    // Provenance
    var source: TransactionDraftSource

    // MARK: Derived

    var amountCents: Int { DS.Format.cents(from: amountText) }

    var hasAttachment: Bool { attachmentData != nil && attachmentType != nil }

    /// Transfers are managed elsewhere (Accounts rebuild). The Add/Edit sheet
    /// must refuse to mutate the transfer leg's amount/type/account; show
    /// read-only state instead.
    var isTransferLeg: Bool { transferGroupId != nil }

    // MARK: Init — fresh

    /// Build an empty draft for the Add flow. `initialMonth` controls the
    /// default date: today if we're in the current month, otherwise the 1st of
    /// the displayed month (preserves the existing AddTransactionSheet rule).
    static func newDraft(
        initialMonth: Date,
        source: TransactionDraftSource,
        accountId: UUID? = nil,
        linkedGoalId: UUID? = nil,
        type: TransactionType = .expense
    ) -> TransactionDraft {
        let cal = Calendar.current
        let now = Date()
        let date: Date = {
            if cal.isDate(initialMonth, equalTo: now, toGranularity: .month) {
                return now
            }
            let comps = cal.dateComponents([.year, .month], from: initialMonth)
            return cal.date(from: DateComponents(
                year: comps.year, month: comps.month, day: 1, hour: 12
            )) ?? initialMonth
        }()

        return TransactionDraft(
            id: UUID(),
            amountText: "",
            type: type,
            category: type == .income ? .other : .groceries,
            date: date,
            note: type == .income ? "Income" : "",
            paymentMethod: .card,
            accountId: accountId,
            linkedGoalId: linkedGoalId,
            attachmentData: nil,
            attachmentType: nil,
            isFlagged: false,
            transferGroupId: nil,
            source: source
        )
    }

    // MARK: Init — from existing

    /// Hydrate a draft from an existing transaction for the Edit flow.
    static func from(_ tx: Transaction, source: TransactionDraftSource = .manual) -> TransactionDraft {
        TransactionDraft(
            id: tx.id,
            amountText: String(format: "%.2f", Double(tx.amount) / 100.0),
            type: tx.type,
            category: tx.category,
            date: tx.date,
            note: tx.note,
            paymentMethod: tx.paymentMethod,
            accountId: tx.accountId,
            linkedGoalId: tx.linkedGoalId,
            attachmentData: tx.attachmentData,
            attachmentType: tx.attachmentType,
            isFlagged: tx.isFlagged,
            transferGroupId: tx.transferGroupId,
            source: source
        )
    }

    // MARK: Build

    /// Materialise the draft into a `Transaction`. Stamps `lastModified = now`.
    func buildTransaction() -> Transaction {
        Transaction(
            id: id,
            amount: amountCents,
            date: date,
            category: category,
            note: note,
            paymentMethod: paymentMethod,
            type: type,
            attachmentData: attachmentData,
            attachmentType: attachmentType,
            accountId: accountId,
            isFlagged: isFlagged,
            linkedGoalId: type == .income ? linkedGoalId : nil,
            lastModified: Date(),
            transferGroupId: transferGroupId
        )
    }

    // MARK: Validation

    /// Whether the chosen category counts as a "real" pick for an expense.
    /// Per `feedback_require_category`, expenses must not silently default to
    /// `.other`. Income may stay on `.other` (it's effectively uncategorised).
    private var hasRealCategory: Bool {
        switch category {
        case .other: return false
        default:     return true
        }
    }

    private static let maxNoteLength = 280
    private static let maxAttachmentBytes = 10 * 1024 * 1024 // 10 MB

    func validate(hasAccounts: Bool) -> DraftValidation {
        var issues: [DraftValidationIssue] = []

        if amountText.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.amountMissing)
        } else if amountCents <= 0 {
            issues.append(.amountNonPositive)
        }

        if type == .expense && !hasRealCategory {
            issues.append(.categoryMissing)
        }

        // Soft requirement: only enforce account when the user has any accounts.
        // Households with zero accounts are still allowed to log transactions.
        if hasAccounts && accountId == nil {
            issues.append(.accountMissing)
        }

        if note.count > Self.maxNoteLength {
            issues.append(.noteTooLong)
        }

        if let data = attachmentData, data.count > Self.maxAttachmentBytes {
            issues.append(.attachmentTooLarge)
        }

        return issues.isEmpty ? .ok : .invalid(issues)
    }
}

// MARK: - Diff (for edit pipeline)

/// Summary of which fields the user changed during an edit. Phase 4's commit
/// pipeline reads this to decide which side-effects to fan out (balance touch,
/// goal contribution swap, audit entry, merchant-memory correction).
struct TransactionDraftDiff: Equatable {
    var amountChanged: Bool
    var typeChanged: Bool
    var categoryChanged: Bool
    var dateChanged: Bool
    var noteChanged: Bool
    var paymentMethodChanged: Bool
    var accountChanged: Bool
    var goalChanged: Bool
    var attachmentChanged: Bool

    var isEmpty: Bool {
        !(amountChanged || typeChanged || categoryChanged || dateChanged ||
          noteChanged || paymentMethodChanged || accountChanged ||
          goalChanged || attachmentChanged)
    }

    static func between(original: Transaction, draft: TransactionDraft) -> TransactionDraftDiff {
        TransactionDraftDiff(
            amountChanged:        original.amount != draft.amountCents,
            typeChanged:          original.type != draft.type,
            categoryChanged:      original.category != draft.category,
            dateChanged:          original.date != draft.date,
            noteChanged:          original.note != draft.note,
            paymentMethodChanged: original.paymentMethod != draft.paymentMethod,
            accountChanged:       original.accountId != draft.accountId,
            goalChanged:          original.linkedGoalId != draft.linkedGoalId,
            attachmentChanged:    original.attachmentData != draft.attachmentData
                                  || original.attachmentType != draft.attachmentType
        )
    }
}

// MARK: - Store

/// Observable wrapper that owns the draft and exposes derived state to the UI.
/// The Add and Edit sheets each instantiate one of these and pass it to the
/// shared form view.
///
/// Phase 1 deliberately does *not* implement `commit()` — Phase 4 builds the
/// fan-out pipeline on top of this state. Today the existing sheets keep their
/// own save paths; this store is purely additive.
@MainActor
final class TransactionDraftStore: ObservableObject {
    @Published var draft: TransactionDraft
    /// Mutable so the unified `TransactionSheet` can flip `.add` placeholder
    /// → `.edit(original:)` after `.onAppear` hydrates from `store.transactions`.
    /// (We can't read the bound `Store` from the sheet's `init`.)
    @Published var mode: TransactionDraftMode

    /// Snapshot of the draft at construction time — used to compute `isDirty`
    /// without requiring the store's owner to remember initial values.
    private let initialDraft: TransactionDraft

    // Phase 3 — opt-in suggestions surfaced as banners / chips. Recomputed by
    // `refreshSuggestions(in:)` whenever the form's bound `Store` changes or
    // the user edits the note/amount/type.
    @Published var merchantSuggestion: MerchantSuggestion?
    @Published var allocationHint: AllocationHint?

    /// Tracks merchant-suggestion dismissals so we don't re-show the same
    /// chip after the user explicitly rejects it. Keyed by the merchant
    /// display string we showed.
    private var dismissedMerchantKeys: Set<String> = []

    init(mode: TransactionDraftMode, initial: TransactionDraft) {
        self.mode = mode
        self.draft = initial
        self.initialDraft = initial
    }

    // MARK: Derived

    var isDirty: Bool {
        switch mode {
        case .add:
            // For adds, "dirty" means the user has typed an amount or note.
            return !draft.amountText.isEmpty
                || !draft.note.isEmpty
                || draft.attachmentData != nil
        case .edit(let original):
            return !TransactionDraftDiff.between(original: original, draft: draft).isEmpty
        }
    }

    var diff: TransactionDraftDiff? {
        if case .edit(let original) = mode {
            return TransactionDraftDiff.between(original: original, draft: draft)
        }
        return nil
    }

    func validate(hasAccounts: Bool) -> DraftValidation {
        draft.validate(hasAccounts: hasAccounts)
    }

    func canSave(hasAccounts: Bool) -> Bool {
        validate(hasAccounts: hasAccounts).isOK
    }

    // MARK: Mutators (kept centralised so future phases can hook them)

    /// Switching expense ↔ income has cascading defaults that already lived in
    /// `TransactionFormCard.segmentButton`. Moving the rule here means the
    /// shared form, AI confirm cards, and App Intents all get the same
    /// behavior for free.
    func setType(_ newType: TransactionType) {
        guard newType != draft.type else { return }
        draft.type = newType
        if newType == .income {
            draft.category = .other
            if draft.note.isEmpty { draft.note = "Income" }
        } else {
            if draft.note == "Income" { draft.note = "" }
            draft.linkedGoalId = nil
            // Don't reset category — the user may have typed an amount with a
            // real category already picked; only the income → expense path
            // would have forced it to .other.
            if case .other = draft.category { draft.category = .groceries }
        }
    }

    func clearAttachment() {
        draft.attachmentData = nil
        draft.attachmentType = nil
    }

    // MARK: - Phase 3: defaults & suggestions

    /// Seed empty fields from the user's history. Only fills slots the caller
    /// hasn't explicitly chosen — never overwrites a non-default value. Call
    /// once after constructing an `.add` draft (e.g. from a presenting sheet's
    /// `onAppear`) and avoid calling it on `.edit` drafts.
    func applyDefaults(from store: Store) {
        guard case .add = mode else { return }

        if draft.accountId == nil {
            draft.accountId = TransactionDraftDefaults.lastUsedAccount(in: store)
        }
        // Only override payment if the default-init value is still in place.
        // We can't *know* the user didn't intend `.card`, so the heuristic is:
        // if the draft was just minted and accountId was just filled, refresh
        // payment to the most-used for that account.
        draft.paymentMethod = TransactionDraftDefaults.mostUsedPayment(
            forAccount: draft.accountId,
            in: store
        )
    }

    /// Recompute merchant + allocation suggestions for the current draft state.
    /// The form view wires this to `.onChange(of: draft.note)` /
    /// `draft.amountText` / `draft.type`. Cheap enough to call eagerly —
    /// `MerchantSuggestionEngine` short-circuits on notes shorter than 3 chars.
    func refreshSuggestions(in store: Store) {
        // Merchant — suppressed once the user has dismissed it for this note.
        let suggestion = MerchantSuggestionEngine.suggestion(for: draft.note, in: store)
        if let s = suggestion, dismissedMerchantKeys.contains(s.merchantDisplay) {
            merchantSuggestion = nil
        } else {
            merchantSuggestion = suggestion?.isWorthShowing == true ? suggestion : nil
        }

        // Allocation — income only.
        allocationHint = AllocationHintEngine.hint(for: draft, in: store)
    }

    /// User accepted the current merchant suggestion: copy its category /
    /// payment / amount into the draft. Amount is only filled if empty so we
    /// don't clobber a number the user already typed.
    func applyMerchantSuggestion() {
        guard let s = merchantSuggestion else { return }
        draft.category = s.category
        if let payment = s.suggestedPayment {
            draft.paymentMethod = payment
        }
        if draft.amountText.isEmpty, let cents = s.suggestedAmountCents, cents > 0 {
            draft.amountText = String(format: "%.2f", Double(cents) / 100.0)
        }
        merchantSuggestion = nil
    }

    /// User dismissed the suggestion. Don't re-show it for this merchant
    /// during the rest of the editing session.
    func dismissMerchantSuggestion() {
        if let s = merchantSuggestion {
            dismissedMerchantKeys.insert(s.merchantDisplay)
        }
        merchantSuggestion = nil
    }
}
