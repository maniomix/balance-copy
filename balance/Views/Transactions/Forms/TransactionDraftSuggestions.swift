import Foundation

// MARK: - Defaults
//
// Phase 3 of the Add Transaction rebuild. Smart defaults sourced from the
// user's transaction history + merchant memory + allocation rule engine.
//
// All entry points are pure functions / struct values so the draft store can
// recompute them deterministically. The store decides when to apply them
// (on draft creation) vs. when to surface them as opt-in suggestions
// (as the user types).

enum TransactionDraftDefaults {

    /// The most recently used account across the user's transactions. The Add
    /// flow seeds the draft with this account so the user doesn't have to pick
    /// every time. Returns nil if no transactions reference an account.
    static func lastUsedAccount(in store: Store) -> UUID? {
        for tx in store.transactions.sorted(by: { $0.date > $1.date }) {
            if let id = tx.accountId { return id }
        }
        return nil
    }

    /// The payment method the user picks most often *for the given account*.
    /// Falls back to overall most-used, then `.card`. Restricting by account
    /// matters because users often map cash to one wallet and card to another.
    static func mostUsedPayment(forAccount accountId: UUID?, in store: Store) -> PaymentMethod {
        let scoped: [Transaction]
        if let accountId = accountId {
            scoped = store.transactions.filter { $0.accountId == accountId }
        } else {
            scoped = store.transactions
        }

        var counts: [PaymentMethod: Int] = [:]
        for tx in scoped {
            counts[tx.paymentMethod, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? .card
    }
}

// MARK: - Merchant suggestion

/// What the merchant memory + history lookup would auto-fill if the user
/// accepted it. Surfaced as an opt-in chip — never applied silently
/// (per `feedback_confirm_every_action` we don't auto-mutate user input).
struct MerchantSuggestion: Equatable {
    let merchantDisplay: String
    let category: Category
    let suggestedAmountCents: Int?      // nil if memory has no learned amount
    let suggestedPayment: PaymentMethod?
    let confidence: Double              // 0.0 ... 1.0

    /// Whether this suggestion is strong enough to bother showing. Merchant
    /// memory's `confidence` already encodes correction count + recency, so
    /// we just gate on a floor.
    var isWorthShowing: Bool { confidence >= 0.55 }
}

@MainActor
enum MerchantSuggestionEngine {

    /// Look up a merchant suggestion for the given note. Combines:
    ///   1. `AIMerchantMemory` (Phase 6 corrections — highest signal)
    ///   2. Last-N transactions with the same note (history fallback)
    /// Returns nil for empty notes or notes shorter than 3 chars
    /// (avoids matching "a" or "ok" against a million history rows).
    static func suggestion(for rawNote: String, in store: Store) -> MerchantSuggestion? {
        let note = rawNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count >= 3 else { return nil }

        // 1. Merchant memory (corrections beat history)
        if let profile = AIMerchantMemory.shared.lookup(note),
           let category = Category(storageKey: profile.category) {
            let payment = mostRecentPayment(forNote: note, in: store)
            return MerchantSuggestion(
                merchantDisplay: profile.displayName,
                category: category,
                suggestedAmountCents: profile.defaultAmount,
                suggestedPayment: payment,
                confidence: profile.confidence
            )
        }

        // 2. History fallback — same note seen ≥2 times in past 90 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date.distantPast
        let matches = store.transactions.filter {
            $0.date >= cutoff &&
            $0.note.localizedCaseInsensitiveCompare(note) == .orderedSame
        }
        guard matches.count >= 2 else { return nil }

        // Pick the most common category among matches.
        var catCounts: [Category: Int] = [:]
        for tx in matches { catCounts[tx.category, default: 0] += 1 }
        guard let topCategory = catCounts.max(by: { $0.value < $1.value })?.key else { return nil }

        let avgAmount = matches.reduce(0) { $0 + $1.amount } / matches.count
        let payment = matches.last?.paymentMethod
        let confidence = min(0.55 + Double(matches.count) * 0.05, 0.85)

        return MerchantSuggestion(
            merchantDisplay: matches.last?.note ?? note,
            category: topCategory,
            suggestedAmountCents: avgAmount > 0 ? avgAmount : nil,
            suggestedPayment: payment,
            confidence: confidence
        )
    }

    private static func mostRecentPayment(forNote note: String, in store: Store) -> PaymentMethod? {
        store.transactions
            .filter { $0.note.localizedCaseInsensitiveCompare(note) == .orderedSame }
            .sorted(by: { $0.date > $1.date })
            .first?
            .paymentMethod
    }
}

// MARK: - Allocation hint
//
// For income drafts, surface a *pre-save* glimpse of the rule engine's
// proposals so the user knows contributions are coming. The actual
// allocation sheet still fires post-save (per existing flow); this hint
// is informational so users don't think their goals were ignored.

struct AllocationHint: Equatable {
    let proposalCount: Int
    let totalCents: Int
    let topGoalName: String?

    var summary: String {
        guard proposalCount > 0 else { return "" }
        let amount = DS.Format.currency(totalCents)
        if proposalCount == 1, let goal = topGoalName {
            return "Rules will offer \(amount) to \(goal) after save."
        }
        return "Rules will offer \(amount) across \(proposalCount) goals after save."
    }
}

@MainActor
enum AllocationHintEngine {

    /// Build a pre-save hint for an income draft. Mirrors the same engine
    /// that runs post-save so the preview matches reality.
    static func hint(for draft: TransactionDraft, in store: Store) -> AllocationHint? {
        guard draft.type == .income, draft.amountCents > 0 else { return nil }

        let preview = draft.buildTransaction()
        let alreadyAllocated = draft.linkedGoalId != nil ? preview.amount : 0

        let proposals = AllocationRuleEngine.proposals(
            for: preview,
            alreadyAllocated: alreadyAllocated,
            goals: GoalManager.shared.goals,
            in: store
        )
        guard !proposals.isEmpty else { return nil }

        let total = proposals.reduce(0) { $0 + $1.amount }
        let top = proposals.first?.goal.name
        return AllocationHint(
            proposalCount: proposals.count,
            totalCents: total,
            topGoalName: top
        )
    }
}
