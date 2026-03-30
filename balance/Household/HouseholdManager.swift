import Foundation
import Combine

// ============================================================
// MARK: - Household Manager
// ============================================================
// Singleton managing the household state, split expenses,
// settlements, and shared budgets.
//
// PERSISTENCE MODEL: LOCAL-FIRST WRITE, CLOUD-AUTHORITATIVE READ
//   - User edits → saved to UserDefaults immediately (never lost)
//   - User edits → pushed to Supabase after local save
//   - On pull: cloud data replaces local for all household state
//   - Offline: local edits accumulate safely in UserDefaults
//
// Single-user mode: household == nil → all features hidden.
// ============================================================

@MainActor
class HouseholdManager: ObservableObject {

    static let shared = HouseholdManager()

    // MARK: - Published State

    @Published var household: Household?
    @Published var sharedBudgets: [SharedBudget] = []
    @Published var splitExpenses: [SplitExpense] = []
    @Published var settlements: [Settlement] = []
    @Published var sharedGoals: [SharedGoal] = []
    @Published var pendingInvites: [HouseholdInvite] = []
    @Published var isLoading: Bool = false
    @Published var isSyncing: Bool = false

    private var userId: String = ""
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let supabase = SupabaseManager.shared

    private init() {}

    // ============================================================
    // MARK: - Lifecycle
    // ============================================================

    func load(userId: String) {
        self.userId = userId
        // Load from local UserDefaults immediately (fast, offline-safe)
        household = loadData("household_\(userId)")
        sharedBudgets = loadData("shared_budgets_\(userId)") ?? []
        splitExpenses = loadData("split_expenses_\(userId)") ?? []
        settlements = loadData("settlements_\(userId)") ?? []
        sharedGoals = loadData("shared_goals_\(userId)") ?? []
        pendingInvites = loadData("household_invites_\(userId)") ?? []

        // Then pull from cloud in background (cloud-authoritative)
        Task { await pullFromCloud() }
    }

    func save() {
        guard !userId.isEmpty else { return }
        // Always save locally first (instant, offline-safe)
        saveData(household, key: "household_\(userId)")
        saveData(sharedBudgets, key: "shared_budgets_\(userId)")
        saveData(splitExpenses, key: "split_expenses_\(userId)")
        saveData(settlements, key: "settlements_\(userId)")
        saveData(sharedGoals, key: "shared_goals_\(userId)")
        saveData(pendingInvites, key: "household_invites_\(userId)")

        // Push to cloud in background (non-blocking)
        Task { await pushToCloud() }
    }

    // ============================================================
    // MARK: - Household CRUD
    // ============================================================

    func createHousehold(name: String, ownerName: String, ownerEmail: String) {
        let owner = HouseholdMember(
            userId: userId,
            displayName: ownerName,
            email: ownerEmail,
            role: .owner,
            sharedAccountIds: nil,
            shareTransactions: true
        )
        household = Household(
            name: name,
            createdBy: userId,
            members: [owner]
        )
        save()
        AnalyticsManager.shared.track(.householdCreated)
    }

    func updateHouseholdName(_ name: String) {
        household?.name = name
        household?.updatedAt = Date()
        save()
    }

    func deleteHousehold() {
        household = nil
        sharedBudgets = []
        splitExpenses = []
        settlements = []
        sharedGoals = []
        pendingInvites = []
        save()
    }

    // ============================================================
    // MARK: - Invites
    // ============================================================

    func generateInvite(role: HouseholdRole = .partner) -> HouseholdInvite? {
        guard let h = household else { return nil }
        let invite = HouseholdInvite(
            householdId: h.id,
            invitedBy: userId,
            inviteCode: h.inviteCode,
            role: role
        )
        pendingInvites.append(invite)
        save()
        return invite
    }

    func joinHousehold(code: String, displayName: String, email: String) -> Bool {
        // Legacy local-only join: matches code against local household.
        // For cloud join, use joinHouseholdViaCloud() instead.
        guard var h = household, h.inviteCode.uppercased() == code.uppercased() else {
            return false
        }
        // Check not already a member
        guard h.member(for: userId) == nil else { return true }

        let member = HouseholdMember(
            userId: userId,
            displayName: displayName,
            email: email,
            role: .partner,
            shareTransactions: true
        )
        h.members.append(member)
        h.updatedAt = Date()
        household = h
        save()
        AnalyticsManager.shared.track(.householdJoined)
        return true
    }

    func removeMember(userId targetId: String) {
        guard var h = household, h.createdBy == userId else { return }
        h.members.removeAll { $0.userId == targetId }
        h.updatedAt = Date()
        household = h
        save()
    }

    func updateMemberRole(userId targetId: String, role: HouseholdRole) {
        guard var h = household, h.canEdit(userId: userId) else { return }
        if let idx = h.members.firstIndex(where: { $0.userId == targetId }) {
            h.members[idx].role = role
            h.updatedAt = Date()
            household = h
            save()
        }
    }

    // ============================================================
    // MARK: - Privacy / Visibility
    // ============================================================

    func updatePrivacy(shareTransactions: Bool, sharedAccountIds: [String]?) {
        guard var h = household,
              let idx = h.members.firstIndex(where: { $0.userId == userId }) else { return }
        h.members[idx].shareTransactions = shareTransactions
        h.members[idx].sharedAccountIds = sharedAccountIds
        h.updatedAt = Date()
        household = h
        save()
    }

    /// Whether this user is in a household.
    var isInHousehold: Bool { household != nil }

    /// Current member record.
    var currentMember: HouseholdMember? { household?.member(for: userId) }

    // ============================================================
    // MARK: - Shared Budgets
    // ============================================================

    func setSharedBudget(monthKey: String, amount: Int, splitRule: SplitRule = .equal) {
        guard let h = household else { return }
        if let idx = sharedBudgets.firstIndex(where: { $0.householdId == h.id && $0.monthKey == monthKey }) {
            sharedBudgets[idx].totalAmount = amount
            sharedBudgets[idx].splitRule = splitRule
            sharedBudgets[idx].updatedAt = Date()
        } else {
            let sb = SharedBudget(
                householdId: h.id,
                monthKey: monthKey,
                totalAmount: amount,
                splitRule: splitRule
            )
            sharedBudgets.append(sb)
        }
        save()
    }

    func sharedBudget(for monthKey: String) -> SharedBudget? {
        guard let h = household else { return nil }
        return sharedBudgets.first(where: { $0.householdId == h.id && $0.monthKey == monthKey })
    }

    // ============================================================
    // MARK: - Split Expenses
    // ============================================================

    func addSplitExpense(
        amount: Int,
        paidBy: String,
        splitRule: SplitRule,
        customSplits: [MemberSplit] = [],
        category: String = "other",
        note: String = "",
        date: Date = Date(),
        transactionId: UUID = UUID()
    ) {
        guard let h = household else { return }
        let expense = SplitExpense(
            householdId: h.id,
            transactionId: transactionId,
            amount: amount,
            paidBy: paidBy,
            splitRule: splitRule,
            customSplits: customSplits,
            category: category,
            note: note,
            date: date
        )
        splitExpenses.append(expense)
        save()
    }

    func removeSplitExpense(id: UUID) {
        splitExpenses.removeAll { $0.id == id }
        save()
    }

    /// Remove all split expenses linked to a transaction (cleanup on delete).
    func removeSplitExpenses(forTransaction transactionId: UUID) {
        let before = splitExpenses.count
        splitExpenses.removeAll { $0.transactionId == transactionId }
        if splitExpenses.count != before { save() }
    }

    /// Remove all split expenses linked to a set of transactions (batch delete).
    func removeSplitExpenses(forTransactions transactionIds: Set<UUID>) {
        let before = splitExpenses.count
        splitExpenses.removeAll { transactionIds.contains($0.transactionId) }
        if splitExpenses.count != before { save() }
    }

    func markExpenseSettled(id: UUID) {
        if let idx = splitExpenses.firstIndex(where: { $0.id == id }) {
            splitExpenses[idx].isSettled = true
            splitExpenses[idx].settledAt = Date()
            save()
        }
    }

    /// Unsettled expenses for current household.
    var unsettledExpenses: [SplitExpense] {
        guard let h = household else { return [] }
        return splitExpenses.filter { $0.householdId == h.id && !$0.isSettled }
    }

    /// Net balance between two members.
    /// Positive = fromUser owes toUser.
    func netBalance(fromUser: String, toUser: String) -> Int {
        guard let h = household else { return 0 }
        let members = h.members
        var balance: Int = 0

        for expense in unsettledExpenses {
            let splits = expense.splits(members: members)
            if expense.paidBy == toUser {
                // toUser paid → fromUser owes their share
                let fromShare = splits.first(where: { $0.userId == fromUser })?.amount ?? 0
                balance += fromShare
            } else if expense.paidBy == fromUser {
                // fromUser paid → toUser owes their share
                let toShare = splits.first(where: { $0.userId == toUser })?.amount ?? 0
                balance -= toShare
            }
        }
        return balance
    }

    // ============================================================
    // MARK: - Settlements
    // ============================================================

    func settleUp(fromUser: String, toUser: String, amount: Int, note: String = "") {
        guard let h = household else { return }
        // Mark matching expenses as settled
        let expenseIds = unsettledExpenses
            .filter { $0.paidBy == toUser || $0.paidBy == fromUser }
            .map { $0.id }

        let settlement = Settlement(
            householdId: h.id,
            fromUserId: fromUser,
            toUserId: toUser,
            amount: amount,
            note: note.isEmpty ? "Settlement" : note,
            relatedExpenseIds: expenseIds
        )
        settlements.append(settlement)

        // Mark related expenses as settled
        for eid in expenseIds {
            markExpenseSettled(id: eid)
        }
        save()
    }

    // ============================================================
    // MARK: - Shared Goals
    // ============================================================

    func addSharedGoal(name: String, icon: String = "star.fill", targetAmount: Int) {
        guard let h = household, h.canEdit(userId: userId) else { return }
        let goal = SharedGoal(
            householdId: h.id,
            name: name,
            icon: icon,
            targetAmount: targetAmount,
            createdBy: userId
        )
        sharedGoals.append(goal)
        save()
    }

    func updateSharedGoal(id: UUID, name: String? = nil, icon: String? = nil, targetAmount: Int? = nil) {
        guard let h = household, h.canEdit(userId: userId) else { return }
        guard let idx = sharedGoals.firstIndex(where: { $0.id == id && $0.householdId == h.id }) else { return }
        if let name = name { sharedGoals[idx].name = name }
        if let icon = icon { sharedGoals[idx].icon = icon }
        if let targetAmount = targetAmount { sharedGoals[idx].targetAmount = targetAmount }
        sharedGoals[idx].updatedAt = Date()
        save()
    }

    func contributeToSharedGoal(id: UUID, amount: Int) {
        guard let h = household else { return }
        guard let idx = sharedGoals.firstIndex(where: { $0.id == id && $0.householdId == h.id }) else { return }
        sharedGoals[idx].currentAmount += amount
        sharedGoals[idx].updatedAt = Date()
        save()
    }

    func removeSharedGoal(id: UUID) {
        guard let h = household, h.canEdit(userId: userId) else { return }
        sharedGoals.removeAll { $0.id == id && $0.householdId == h.id }
        save()
    }

    /// Active (non-completed) shared goals for the current household.
    var activeSharedGoals: [SharedGoal] {
        guard let h = household else { return [] }
        return sharedGoals.filter { $0.householdId == h.id && !$0.isCompleted }
    }

    // ============================================================
    // MARK: - Summary / Analytics
    // ============================================================

    /// Total shared spending this month.
    func sharedSpending(monthKey: String) -> Int {
        guard let h = household else { return 0 }
        return splitExpenses
            .filter { $0.householdId == h.id && Store.monthKey($0.date) == monthKey }
            .reduce(0) { $0 + $1.amount }
    }

    /// Per-member spending this month.
    func memberSpending(monthKey: String) -> [String: Int] {
        guard let h = household else { return [:] }
        var result: [String: Int] = [:]
        for expense in splitExpenses where expense.householdId == h.id && Store.monthKey(expense.date) == monthKey {
            let splits = expense.splits(members: h.members)
            for s in splits {
                result[s.userId, default: 0] += s.amount
            }
        }
        return result
    }

    /// Category breakdown for shared expenses.
    func sharedCategoryBreakdown(monthKey: String) -> [String: Int] {
        guard let h = household else { return [:] }
        var result: [String: Int] = [:]
        for expense in splitExpenses where expense.householdId == h.id && Store.monthKey(expense.date) == monthKey {
            result[expense.category, default: 0] += expense.amount
        }
        return result
    }

    // ============================================================
    // MARK: - Transaction ↔ Household Linking
    // ============================================================

    /// Whether a transaction is linked to a split expense.
    func isSplitTransaction(_ transactionId: UUID) -> Bool {
        splitExpenses.contains { $0.transactionId == transactionId }
    }

    /// The split expense linked to a transaction, if any.
    func splitExpense(for transactionId: UUID) -> SplitExpense? {
        splitExpenses.first { $0.transactionId == transactionId }
    }

    /// All transaction IDs that are part of split expenses (cached set for fast lookup).
    var splitTransactionIds: Set<UUID> {
        Set(splitExpenses.map { $0.transactionId })
    }

    // ============================================================
    // MARK: - Dashboard Snapshot
    // ============================================================

    /// Total unsettled amount across all open split expenses.
    var totalUnsettledAmount: Int {
        unsettledExpenses.reduce(0) { $0 + $1.amount }
    }

    /// Total amount the current user owes across all members.
    func totalOwed(currentUserId uid: String) -> Int {
        guard let h = household else { return 0 }
        var total = 0
        for member in h.members where member.userId != uid {
            let balance = netBalance(fromUser: uid, toUser: member.userId)
            if balance > 0 { total += balance }
        }
        return total
    }

    /// Total amount owed TO the current user across all members.
    func totalOwedToYou(currentUserId uid: String) -> Int {
        guard let h = household else { return 0 }
        var total = 0
        for member in h.members where member.userId != uid {
            let balance = netBalance(fromUser: uid, toUser: member.userId)
            if balance < 0 { total += abs(balance) }
        }
        return total
    }

    /// Whether the shared budget for the given month is over-budget.
    func isOverBudget(monthKey: String) -> Bool {
        guard let sb = sharedBudget(for: monthKey), sb.totalAmount > 0 else { return false }
        return sharedSpending(monthKey: monthKey) > sb.totalAmount
    }

    /// How much is left in the shared budget (negative = over).
    func sharedBudgetRemaining(monthKey: String) -> Int? {
        guard let sb = sharedBudget(for: monthKey), sb.totalAmount > 0 else { return nil }
        return sb.totalAmount - sharedSpending(monthKey: monthKey)
    }

    /// Shared budget utilization ratio (0.0–1.0+). Nil if no budget set.
    func sharedBudgetUtilization(monthKey: String) -> Double? {
        guard let sb = sharedBudget(for: monthKey), sb.totalAmount > 0 else { return nil }
        return Double(sharedSpending(monthKey: monthKey)) / Double(sb.totalAmount)
    }

    /// Recent split expenses (last N, across all months).
    func recentSplitExpenses(limit: Int = 3) -> [SplitExpense] {
        guard let h = household else { return [] }
        return splitExpenses
            .filter { $0.householdId == h.id }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    /// Recent settlements (last N).
    func recentSettlements(limit: Int = 3) -> [Settlement] {
        guard let h = household else { return [] }
        return settlements
            .filter { $0.householdId == h.id }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    /// Dashboard snapshot combining all key household metrics.
    func dashboardSnapshot(monthKey: String, currentUserId uid: String) -> HouseholdSnapshot {
        let spending = sharedSpending(monthKey: monthKey)
        let budget = sharedBudget(for: monthKey)
        let budgetAmount = budget?.totalAmount ?? 0
        let utilization = sharedBudgetUtilization(monthKey: monthKey)
        let unsettled = unsettledExpenses.count
        let unsettledTotal = totalUnsettledAmount
        let youOwe = totalOwed(currentUserId: uid)
        let owedToYou = totalOwedToYou(currentUserId: uid)
        let activeGoals = activeSharedGoals
        let overBudget = isOverBudget(monthKey: monthKey)

        return HouseholdSnapshot(
            memberCount: household?.memberCount ?? 0,
            hasPartner: household?.partner != nil,
            sharedSpending: spending,
            sharedBudget: budgetAmount,
            budgetUtilization: utilization,
            isOverBudget: overBudget,
            unsettledCount: unsettled,
            unsettledAmount: unsettledTotal,
            youOwe: youOwe,
            owedToYou: owedToYou,
            activeSharedGoalCount: activeGoals.count,
            topGoal: activeGoals.sorted(by: { $0.progress > $1.progress }).first,
            totalGoalProgress: activeGoals.isEmpty ? 0 :
                activeGoals.reduce(0) { $0 + $1.currentAmount } * 100 /
                max(1, activeGoals.reduce(0) { $0 + $1.targetAmount }),
            pendingInviteCount: pendingInvites.filter { !$0.isExpired && $0.status == .pending }.count
        )
    }

    // ============================================================
    // MARK: - Cloud Sync
    // ============================================================

    /// Pull household data from Supabase and replace local state.
    /// Called on load and can be triggered manually for refresh.
    func pullFromCloud() async {
        guard !userId.isEmpty else { return }
        guard supabase.currentUser != nil else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            guard let cloudData = try await supabase.pullHouseholdData(userId: userId.lowercased()) else {
                // No household in cloud — keep local state as-is
                SecureLogger.debug("No household found in cloud for user")
                return
            }

            // Cloud-authoritative: replace local state
            household = cloudData.household
            splitExpenses = cloudData.splitExpenses
            settlements = cloudData.settlements
            sharedBudgets = cloudData.sharedBudgets
            sharedGoals = cloudData.sharedGoals

            // Persist to UserDefaults for offline access
            saveLocal()

            SecureLogger.info("Household pulled from cloud: \(cloudData.splitExpenses.count) splits, \(cloudData.settlements.count) settlements")
        } catch {
            SecureLogger.error("Household cloud pull failed", error)
        }
    }

    /// Push current local household data to Supabase.
    /// Called after every local save.
    private func pushToCloud() async {
        guard !userId.isEmpty else { return }
        guard supabase.currentUser != nil else { return }
        guard let h = household else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await supabase.pushHouseholdData(
                household: h,
                members: h.members,
                splitExpenses: splitExpenses,
                settlements: settlements,
                sharedBudgets: sharedBudgets,
                sharedGoals: sharedGoals
            )
            SecureLogger.info("Household pushed to cloud")
        } catch {
            SecureLogger.error("Household cloud push failed", error)
            // Local data is safe in UserDefaults — will retry on next save
        }
    }

    /// Join a household by invite code via cloud lookup.
    func joinHouseholdViaCloud(code: String, displayName: String, email: String) async -> Bool {
        guard !userId.isEmpty, supabase.currentUser != nil else { return false }

        do {
            // Look up household by invite code in Supabase
            guard let remoteHousehold = try await supabase.findHouseholdByInviteCode(code) else {
                SecureLogger.info("No household found for invite code")
                return false
            }

            // Check not already a member
            let existingMembers = try await supabase.loadHouseholdMembers(householdId: remoteHousehold.id)
            if existingMembers.contains(where: { $0.userId.lowercased() == userId.lowercased() }) {
                // Already a member — just pull data
                await pullFromCloud()
                return true
            }

            // Add self as a member
            let member = HouseholdMember(
                userId: userId,
                displayName: displayName,
                email: email,
                role: .partner,
                shareTransactions: true
            )
            try await supabase.saveHouseholdMember(member, householdId: remoteHousehold.id)

            // Pull the full household state
            await pullFromCloud()

            AnalyticsManager.shared.track(.householdJoined)
            SecureLogger.info("Joined household via cloud")
            return true
        } catch {
            SecureLogger.error("Cloud join failed", error)
            return false
        }
    }

    // ============================================================
    // MARK: - Persistence Helpers
    // ============================================================

    /// Save to UserDefaults only (no cloud push). Used by pullFromCloud.
    private func saveLocal() {
        guard !userId.isEmpty else { return }
        saveData(household, key: "household_\(userId)")
        saveData(sharedBudgets, key: "shared_budgets_\(userId)")
        saveData(splitExpenses, key: "split_expenses_\(userId)")
        saveData(settlements, key: "settlements_\(userId)")
        saveData(sharedGoals, key: "shared_goals_\(userId)")
        saveData(pendingInvites, key: "household_invites_\(userId)")
    }

    private func saveData<T: Encodable>(_ value: T, key: String) {
        if let data = try? encoder.encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadData<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}
