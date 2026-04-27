import Foundation

// ============================================================
// MARK: - Household / Shared Finance Models
// ============================================================
// Phase 8: Couples & shared finance mode.
// All amounts in cents (Int) — consistent with the rest of the app.
// ============================================================

// MARK: - Household

struct Household: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdBy: String             // userId of creator
    var members: [HouseholdMember]
    var inviteCode: String            // 6-char code for inviting partner
    /// Optional sub-groups (e.g. "Parents", "Kids"). Future per-group budgets.
    var groups: [HouseholdGroup]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "Our Household",
        createdBy: String,
        members: [HouseholdMember] = [],
        inviteCode: String = Household.generateInviteCode(),
        groups: [HouseholdGroup] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdBy = createdBy
        self.members = members
        self.inviteCode = inviteCode
        self.groups = groups
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, createdBy, members, inviteCode, groups, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdBy = try c.decode(String.self, forKey: .createdBy)
        members = try c.decode([HouseholdMember].self, forKey: .members)
        inviteCode = try c.decode(String.self, forKey: .inviteCode)
        groups = (try? c.decode([HouseholdGroup].self, forKey: .groups)) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    static func generateInviteCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).compactMap { _ in chars.randomElement() })
    }

    // Convenience
    var owner: HouseholdMember? { members.first(where: { $0.role == .owner }) }
    var partner: HouseholdMember? { members.first(where: { $0.role == .partner }) }
    var viewers: [HouseholdMember] { members.filter { $0.role == .viewer } }
    var memberCount: Int { members.count }
    /// Active (non-archived) members — excludes archived ledger-history keepers.
    var activeMembers: [HouseholdMember] { members.filter { $0.isActive } }

    func member(for userId: String) -> HouseholdMember? {
        members.first(where: { $0.userId == userId })
    }

    func canEdit(userId: String) -> Bool {
        guard let m = member(for: userId) else { return false }
        return m.role.canEditBudgets
    }

    func canView(userId: String) -> Bool {
        member(for: userId) != nil
    }
}

// MARK: - Group

/// Optional sub-group of members (e.g. "Parents", "Kids"). Ported from macOS.
/// Purely descriptive for v1; future per-group budgets will reference `id`.
struct HouseholdGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// Hex color without `#` (e.g. "3DB9FC"). Free-form; UI decides rendering.
    var colorHex: String
    var memberIds: [UUID]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "3DB9FC",
        memberIds: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.memberIds = memberIds
        self.createdAt = createdAt
    }
}

// MARK: - Member

struct HouseholdMember: Identifiable, Codable, Hashable {
    let id: UUID
    var userId: String
    var displayName: String
    var email: String
    var role: HouseholdRole
    var joinedAt: Date
    /// Which account IDs this member has chosen to share.
    /// Empty = all accounts private. nil = share all.
    var sharedAccountIds: [String]?
    /// If false, personal transactions aren't visible to other members.
    var shareTransactions: Bool
    /// Archived members are hidden from pickers but kept for ledger history.
    var isActive: Bool
    var archivedAt: Date?
    /// HouseholdGroup.id values this member belongs to.
    var groupIds: [UUID]

    init(
        id: UUID = UUID(),
        userId: String,
        displayName: String,
        email: String = "",
        role: HouseholdRole,
        joinedAt: Date = Date(),
        sharedAccountIds: [String]? = nil,
        shareTransactions: Bool = true,
        isActive: Bool = true,
        archivedAt: Date? = nil,
        groupIds: [UUID] = []
    ) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.email = email
        self.role = role
        self.joinedAt = joinedAt
        self.sharedAccountIds = sharedAccountIds
        self.shareTransactions = shareTransactions
        self.isActive = isActive
        self.archivedAt = archivedAt
        self.groupIds = groupIds
    }

    enum CodingKeys: String, CodingKey {
        case id, userId, displayName, email, role, joinedAt
        case sharedAccountIds, shareTransactions
        case isActive, archivedAt, groupIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        userId = try c.decode(String.self, forKey: .userId)
        displayName = try c.decode(String.self, forKey: .displayName)
        email = (try? c.decode(String.self, forKey: .email)) ?? ""
        role = try c.decode(HouseholdRole.self, forKey: .role)
        joinedAt = try c.decode(Date.self, forKey: .joinedAt)
        sharedAccountIds = try? c.decode([String]?.self, forKey: .sharedAccountIds)
        shareTransactions = (try? c.decode(Bool.self, forKey: .shareTransactions)) ?? true
        isActive = (try? c.decode(Bool.self, forKey: .isActive)) ?? true
        archivedAt = try? c.decode(Date?.self, forKey: .archivedAt)
        groupIds = (try? c.decode([UUID].self, forKey: .groupIds)) ?? []
    }
}

enum HouseholdRole: String, Codable, CaseIterable, Hashable {
    case owner
    case partner
    case adult
    case child
    case viewer

    var displayName: String {
        switch self {
        case .owner: return "Owner"
        case .partner: return "Partner"
        case .adult: return "Adult"
        case .child: return "Child"
        case .viewer: return "Viewer"
        }
    }

    var icon: String {
        switch self {
        case .owner: return "crown.fill"
        case .partner: return "heart.fill"
        case .adult: return "person.fill"
        case .child: return "figure.child"
        case .viewer: return "eye.fill"
        }
    }

    /// Budgets / settings / shared goals. Children and viewers can't edit.
    var canEditBudgets: Bool {
        switch self {
        case .owner, .partner, .adult: return true
        case .child, .viewer: return false
        }
    }

    /// Adding personal or split expenses. Only viewers are blocked.
    var canAddExpenses: Bool { self != .viewer }

    /// Add / remove / role-change other members. Owner only.
    var canManageMembers: Bool { self == .owner }
}

// MARK: - Share Status

/// Lifecycle of a split expense's share. Placeholder for future
/// partial-settlement states. For v1 it mirrors `SplitExpense.isSettled`.
enum ShareStatus: String, Codable, Hashable {
    case owed
    case settled
}

// MARK: - Shared Budget

struct SharedBudget: Identifiable, Codable, Hashable {
    let id: UUID
    var householdId: UUID
    var monthKey: String              // YYYY-MM
    var totalAmount: Int              // cents
    var splitRule: SplitRule
    var categoryBudgets: [String: Int] // Category.storageKey -> cents
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        householdId: UUID,
        monthKey: String,
        totalAmount: Int,
        splitRule: SplitRule = .equal,
        categoryBudgets: [String: Int] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.monthKey = monthKey
        self.totalAmount = totalAmount
        self.splitRule = splitRule
        self.categoryBudgets = categoryBudgets
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Split Expense

struct SplitExpense: Identifiable, Codable, Hashable {
    let id: UUID
    var householdId: UUID
    var transactionId: UUID           // links to the Transaction in Store
    var amount: Int                   // total amount in cents
    var paidBy: String                // userId who paid
    var splitRule: SplitRule
    var customSplits: [MemberSplit]   // only used when splitRule == .custom
    var category: String              // Category.storageKey
    var note: String
    var date: Date
    var isSettled: Bool
    var settledAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        householdId: UUID,
        transactionId: UUID = UUID(),
        amount: Int,
        paidBy: String,
        splitRule: SplitRule = .equal,
        customSplits: [MemberSplit] = [],
        category: String = "other",
        note: String = "",
        date: Date = Date(),
        isSettled: Bool = false,
        settledAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.transactionId = transactionId
        self.amount = amount
        self.paidBy = paidBy
        self.splitRule = splitRule
        self.customSplits = customSplits
        self.category = category
        self.note = note
        self.date = date
        self.isSettled = isSettled
        self.settledAt = settledAt
        self.createdAt = createdAt
    }

    /// Current lifecycle state. Derived from `isSettled` for v1.
    var status: ShareStatus { isSettled ? .settled : .owed }

    /// Compute how much each member owes / is owed.
    func splits(members: [HouseholdMember]) -> [MemberSplit] {
        switch splitRule {
        case .equal:
            let count = max(1, members.count)
            let perPerson: Int = amount / count
            let remainder: Int = amount - (perPerson * count)
            return members.enumerated().map { idx, m in
                let share = perPerson + (idx == 0 ? remainder : 0)
                return MemberSplit(userId: m.userId, amount: share)
            }

        case .custom:
            return customSplits

        case .paidByMe:
            // Full amount on payer, 0 on others
            return members.map { m in
                MemberSplit(
                    userId: m.userId,
                    amount: m.userId == paidBy ? amount : 0
                )
            }

        case .paidByPartner:
            // Full amount on non-payer
            return members.map { m in
                MemberSplit(
                    userId: m.userId,
                    amount: m.userId != paidBy ? amount : 0
                )
            }

        case .percentage(let pct):
            let myShare: Int = Int(Double(amount) * pct / 100.0)
            let theirShare: Int = amount - myShare
            return members.map { m in
                MemberSplit(
                    userId: m.userId,
                    amount: m.userId == paidBy ? myShare : theirShare
                )
            }
        }
    }

    /// How much payer is owed back from others.
    func payerOwed(members: [HouseholdMember]) -> Int {
        let allSplits = splits(members: members)
        let payerShare = allSplits.first(where: { $0.userId == paidBy })?.amount ?? 0
        return amount - payerShare
    }
}

struct MemberSplit: Codable, Hashable, Identifiable {
    var id: String { userId }
    var userId: String
    var amount: Int                   // cents this member owes
}

// MARK: - Split Rule

enum SplitRule: Codable, Hashable {
    case equal                        // 50/50
    case custom                       // manual amounts
    case paidByMe                     // I cover all
    case paidByPartner                // partner covers all
    case percentage(Double)           // e.g. 60 = I pay 60%, partner 40%

    var displayName: String {
        switch self {
        case .equal: return "50/50"
        case .custom: return "Custom"
        case .paidByMe: return "I paid"
        case .paidByPartner: return "Partner paid"
        case .percentage(let p): return "\(Int(p))/\(100 - Int(p))"
        }
    }

    var icon: String {
        switch self {
        case .equal: return "equal.circle.fill"
        case .custom: return "slider.horizontal.3"
        case .paidByMe: return "person.fill"
        case .paidByPartner: return "person.2.fill"
        case .percentage: return "chart.pie.fill"
        }
    }
}

// MARK: - Settlement

struct Settlement: Identifiable, Codable, Hashable {
    let id: UUID
    var householdId: UUID
    var fromUserId: String            // who pays
    var toUserId: String              // who receives
    var amount: Int                   // cents
    var note: String
    var date: Date
    var relatedExpenseIds: [UUID]     // which SplitExpenses are being settled
    var createdAt: Date

    init(
        id: UUID = UUID(),
        householdId: UUID,
        fromUserId: String,
        toUserId: String,
        amount: Int,
        note: String = "Settlement",
        date: Date = Date(),
        relatedExpenseIds: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.amount = amount
        self.note = note
        self.date = date
        self.relatedExpenseIds = relatedExpenseIds
        self.createdAt = createdAt
    }
}

// MARK: - Household Invite

struct HouseholdInvite: Identifiable, Codable, Hashable {
    let id: UUID
    var householdId: UUID
    var invitedBy: String             // userId
    var inviteCode: String
    var role: HouseholdRole
    var status: InviteStatus
    var createdAt: Date
    var expiresAt: Date

    init(
        id: UUID = UUID(),
        householdId: UUID,
        invitedBy: String,
        inviteCode: String,
        role: HouseholdRole = .partner,
        status: InviteStatus = .pending,
        createdAt: Date = Date(),
        expiresAt: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date().addingTimeInterval(7 * 24 * 3600)
    ) {
        self.id = id
        self.householdId = householdId
        self.invitedBy = invitedBy
        self.inviteCode = inviteCode
        self.role = role
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    var isExpired: Bool { Date() > expiresAt }
}

enum InviteStatus: String, Codable, Hashable {
    case pending
    case accepted
    case declined
    case expired
}

// MARK: - Household Snapshot (Dashboard)

struct HouseholdSnapshot {
    let memberCount: Int
    let hasPartner: Bool
    let sharedSpending: Int          // cents this month
    let sharedBudget: Int            // cents budget this month (0 = not set)
    let budgetUtilization: Double?   // 0.0–1.0+ (nil = no budget)
    let isOverBudget: Bool
    let unsettledCount: Int
    let unsettledAmount: Int         // total cents unsettled
    let youOwe: Int                  // cents you owe others
    let owedToYou: Int               // cents others owe you
    let activeSharedGoalCount: Int
    let topGoal: SharedGoal?
    let totalGoalProgress: Int       // 0–100 overall progress %
    let pendingInviteCount: Int

    var hasAlerts: Bool {
        isOverBudget || unsettledCount > 3 || youOwe > 0 || !hasPartner
    }

    var urgentSummary: String? {
        if isOverBudget {
            return "Shared spending is over budget"
        }
        if youOwe > 0 {
            return "You have an unsettled balance"
        }
        if unsettledCount > 3 {
            return "\(unsettledCount) expenses need settling"
        }
        if !hasPartner && memberCount <= 1 {
            return "Invite your partner to get started"
        }
        return nil
    }
}

// MARK: - Shared Goal

struct SharedGoal: Identifiable, Codable, Hashable {
    let id: UUID
    var householdId: UUID
    var name: String
    var icon: String                  // SF Symbol name
    var targetAmount: Int             // cents
    var currentAmount: Int            // cents
    var createdBy: String             // userId
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        householdId: UUID,
        name: String,
        icon: String = "star.fill",
        targetAmount: Int,
        currentAmount: Int = 0,
        createdBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.name = name
        self.icon = icon
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(1.0, Double(currentAmount) / Double(targetAmount))
    }

    var isCompleted: Bool { currentAmount >= targetAmount }

    /// Remaining amount to reach the target (cents).
    var remainingAmount: Int {
        max(0, targetAmount - currentAmount)
    }

    /// Progress as an integer percentage (0–100).
    var progressPercent: Int {
        Int(progress * 100)
    }
}
