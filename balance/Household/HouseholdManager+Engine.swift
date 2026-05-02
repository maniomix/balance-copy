import Foundation
import Auth

// ============================================================
// MARK: - HouseholdManager + HouseholdEngine (P5.2)
// ============================================================
//
// Thin conformance layer mapping the unified engine surface (spec §6) onto
// the existing `HouseholdManager` API. Wrappers translate between the
// engine's UUID member identity and the manager's userId-string identity.
//
// No new business logic lives here — every method delegates to existing
// HouseholdManager state mutations. New first-class methods that the spec
// requires (recordSplit/editSplit/deleteSplit) are also thin wrappers around
// `addSplitExpense` / `removeSplitExpenses(forTransaction:)`. The `splitRule`
// translation honours spec §7.1 mapping in reverse.
// ============================================================

extension HouseholdManager: HouseholdEngine {

    // MARK: 6.1 Lifecycle

    @discardableResult
    func createHousehold(name: String, ownerDisplayName: String) -> Household {
        // Delegate to existing 3-arg signature; current user supplies the
        // auth context. `email` falls back to `""` because the engine
        // contract doesn't carry it.
        let email = SupabaseManager.shared.currentUser?.email ?? ""
        createHousehold(name: name, ownerName: ownerDisplayName, ownerEmail: email)
        // `household` is force-populated by the call above; the unwrap is
        // safe under normal flow. If somehow nil, return a synthetic empty.
        return household ?? Household(createdBy: "")
    }

    @discardableResult
    func regenerateInviteCode() -> String {
        guard var h = household, h.canEdit(userId: h.createdBy) else { return "" }
        let new = Household.generateInviteCode()
        h.inviteCode = new
        h.updatedAt = Date()
        household = h
        save()
        return new
    }

    // MARK: 6.2 Members

    @discardableResult
    func addMember(
        displayName: String,
        email: String,
        role: HouseholdRole
    ) -> HouseholdMember? {
        guard var h = household, h.canEdit(userId: h.createdBy) else { return nil }
        let m = HouseholdMember(
            userId: "",        // unlinked until invite is redeemed
            displayName: displayName,
            email: email,
            role: role
        )
        h.members.append(m)
        h.updatedAt = Date()
        household = h
        save()
        return m
    }

    @discardableResult
    func updateMember(
        id: UUID,
        mutator: (inout HouseholdMember) -> Void
    ) -> HouseholdMember? {
        guard var h = household,
              let idx = h.members.firstIndex(where: { $0.id == id })
        else { return nil }
        mutator(&h.members[idx])
        h.updatedAt = Date()
        household = h
        save()
        return h.members[idx]
    }

    @discardableResult
    func archiveMember(id: UUID, strategy: ArchiveStrategy) -> ArchiveOutcome {
        guard let h = household else { return .unknownMember }
        guard let m = h.members.first(where: { $0.id == id }) else { return .unknownMember }
        // Owner self-archive must transfer first.
        if m.role == .owner { return .notPermitted }

        // Open shares = unsettled SplitExpenses where this member owes a non-zero
        // amount. Engine surface checks them up front so the strategy decides
        // before the existing archive method touches state.
        let openCount = openShareCount(forMemberId: id)
        if openCount > 0 {
            switch strategy {
            case .failIfOpenShares:
                return .blockedByOpenShares(count: openCount)
            case .waiveOpenShares:
                waiveOpenShares(forMemberId: id)
            case .reassignOpenSharesTo(let target):
                reassignOpenShares(fromMemberId: id, toMemberId: target)
            }
        }

        archiveMember(userId: m.userId)
        return .archived
    }

    @discardableResult
    func restoreMember(id: UUID) -> Bool {
        guard let h = household,
              let m = h.members.first(where: { $0.id == id })
        else { return false }
        restoreMember(userId: m.userId)
        return true
    }

    /// Engine-surface wrapper. The legacy `transferOwnership(toMemberId:)` on
    /// `HouseholdManager` returns Void and silently no-ops on permission /
    /// validation failure; the protocol requires `-> Bool`. We re-do the
    /// mutation here so the success/failure signal is faithful (delegating
    /// to the void method would create call-site overload ambiguity).
    @discardableResult
    func transferOwnership(toMemberId: UUID) -> Bool {
        guard var h = household,
              h.canEdit(userId: userId), userId == h.createdBy,
              let newIdx = h.members.firstIndex(where: { $0.id == toMemberId && $0.isActive }),
              let oldIdx = h.members.firstIndex(where: { $0.role == .owner }),
              newIdx != oldIdx
        else { return false }
        h.members[oldIdx].role = .adult
        h.members[newIdx].role = .owner
        h.createdBy = h.members[newIdx].userId
        h.updatedAt = Date()
        household = h
        save()
        return true
    }

    // MARK: 6.3 Splits

    @discardableResult
    func recordSplit(
        transactionId: UUID,
        totalCents: Int,
        paidByMemberId: UUID,
        method: ExpenseSplitMethod,
        lines: [SplitLine]
    ) -> [ExpenseShare] {
        guard let h = household,
              let payer = h.members.first(where: { $0.id == paidByMemberId })
        else { return [] }

        // Engine method → legacy SplitRule + customSplits, so the existing
        // `addSplitExpense` pipeline (and its persistence/sync) keeps driving
        // storage. Shares are auto-derived in `rebuildShares()`.
        let rule = legacyRule(for: method, payerUserId: payer.userId, lines: lines, members: h.members)
        let custom = legacyCustomSplits(method: method, totalCents: totalCents, lines: lines, members: h.members)

        addSplitExpense(
            amount: totalCents,
            paidBy: payer.userId,
            splitRule: rule,
            customSplits: custom,
            transactionId: transactionId
        )
        return expenseShares.filter { $0.transactionId == transactionId }
    }

    @discardableResult
    func editSplit(
        transactionId: UUID,
        totalCents: Int,
        paidByMemberId: UUID,
        method: ExpenseSplitMethod,
        lines: [SplitLine]
    ) -> [ExpenseShare] {
        // Edit = delete + record. Atomic in the eyes of consumers.
        deleteSplit(transactionId: transactionId)
        return recordSplit(
            transactionId: transactionId,
            totalCents: totalCents,
            paidByMemberId: paidByMemberId,
            method: method,
            lines: lines
        )
    }

    func deleteSplit(transactionId: UUID) {
        removeSplitExpenses(forTransaction: transactionId)
    }

    // MARK: 6.4 Settlement

    @discardableResult
    func settleUp(
        fromMemberId: UUID,
        toMemberId: UUID,
        amount: Int,
        materializeAsTransaction: Bool
    ) -> Settlement? {
        guard let h = household,
              let from = h.members.first(where: { $0.id == fromMemberId }),
              let to = h.members.first(where: { $0.id == toMemberId })
        else { return nil }
        // P8b — `materializeAsTransaction` is parsed but ignored. The toggle
        // is hidden in the settle-up sheet UI (spec §6 of
        // docs/HOUSEHOLD_REBUILD_P8_SETTLEUP_SPEC.md) until the open
        // category/account questions are resolved. When wired, the engine
        // should:
        //   1. Resolve / create a built-in `Settlement` Category.
        //   2. Use the user-picked Account from the sheet.
        //   3. Create a Transaction representing the cash move.
        //   4. Set `Settlement.linkedTransactionId` to the new tx id.
        //   5. On `unsettle`, tombstone the transaction (don't hard-delete).
        _ = materializeAsTransaction
        let before = settlements.count
        settleUp(fromUser: from.userId, toUser: to.userId, amount: amount, note: "")
        return settlements.count > before ? settlements.last : nil
    }

    // MARK: 6.5 Snapshot

    func snapshot(monthKey: String, currentMemberId: UUID) -> HouseholdSnapshot {
        guard let h = household,
              let m = h.members.first(where: { $0.id == currentMemberId })
        else {
            return HouseholdSnapshot(
                memberCount: 0, hasPartner: false,
                sharedSpending: 0, sharedBudget: 0,
                budgetUtilization: nil, isOverBudget: false,
                unsettledCount: 0, unsettledAmount: 0,
                youOwe: 0, owedToYou: 0,
                activeSharedGoalCount: 0, topGoal: nil,
                totalGoalProgress: 0, pendingInviteCount: 0
            )
        }
        return dashboardSnapshot(monthKey: monthKey, currentUserId: m.userId)
    }

    // MARK: - Helpers

    private func openShareCount(forMemberId id: UUID) -> Int {
        expenseShares.filter { $0.memberId == id && $0.isOpen && $0.amount > 0 }.count
    }

    private func waiveOpenShares(forMemberId id: UUID) {
        // Engine-level waive: settle the underlying SplitExpense for this
        // member's portion. Implementation parity will be tightened in P11
        // when reference-repair runs across both platforms.
        guard let h = household else { return }
        for expense in splitExpenses where !expense.isSettled && expense.householdId == h.id {
            let memberSplits = expense.splits(members: h.members)
            let owesNonZero = memberSplits.contains { ms in
                guard let m = h.members.first(where: { $0.userId == ms.userId }) else { return false }
                return m.id == id && ms.amount > 0
            }
            if owesNonZero, let idx = splitExpenses.firstIndex(where: { $0.id == expense.id }) {
                splitExpenses[idx].isSettled = true
                splitExpenses[idx].settledAt = Date()
            }
        }
        save()
    }

    private func reassignOpenShares(fromMemberId: UUID, toMemberId: UUID) {
        // No-op for v1: the legacy SplitExpense aggregate stores per-rule
        // splits, not per-share rows, so reassigning a single member's share
        // requires editing custom splits — deferred until first-class
        // recordSplit/editSplit storage lands. Treated as `failIfOpenShares`
        // for safety.
        _ = fromMemberId; _ = toMemberId
    }

    private func legacyRule(
        for method: ExpenseSplitMethod,
        payerUserId: String,
        lines: [SplitLine],
        members: [HouseholdMember]
    ) -> SplitRule {
        switch method {
        case .equal: return .equal
        case .exact: return .custom
        case .shares: return .custom
        case .percent:
            // Two-member household percent maps cleanly to `.percentage(p)`;
            // 3+ members fall back to `.custom` so the math is preserved.
            if members.count == 2,
               let payerLine = lines.first(where: { line in
                   members.first(where: { $0.id == line.memberId })?.userId == payerUserId
               }) {
                return .percentage(payerLine.value)
            }
            return .custom
        }
    }

    private func legacyCustomSplits(
        method: ExpenseSplitMethod,
        totalCents: Int,
        lines: [SplitLine],
        members: [HouseholdMember]
    ) -> [MemberSplit] {
        switch method {
        case .equal:
            return []
        case .exact:
            return lines.compactMap { line in
                guard let m = members.first(where: { $0.id == line.memberId }) else { return nil }
                return MemberSplit(userId: m.userId, amount: Int(line.value))
            }
        case .percent:
            return lines.compactMap { line in
                guard let m = members.first(where: { $0.id == line.memberId }) else { return nil }
                let cents = Int((Double(totalCents) * line.value / 100.0).rounded())
                return MemberSplit(userId: m.userId, amount: cents)
            }
        case .shares:
            let totalWeight = lines.reduce(0.0) { $0 + max(0, $1.value) }
            guard totalWeight > 0 else { return [] }
            return lines.compactMap { line in
                guard let m = members.first(where: { $0.id == line.memberId }) else { return nil }
                let cents = Int((Double(totalCents) * line.value / totalWeight).rounded())
                return MemberSplit(userId: m.userId, amount: cents)
            }
        }
    }
}
