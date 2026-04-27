import Foundation

// ============================================================
// MARK: - Goal Allocation Rule (Phase 4b — iOS port)
// ============================================================
//
// A user-configured rule that translates an income transaction into a
// proposed `AIGoalContribution`. Ported from macOS Centmond as a Codable
// struct; relationship to Goal is a UUID ref (`goalId`) instead of
// SwiftData's `@Relationship`.
//
// `AllocationRuleEngine` evaluates active rules against a new income
// transaction and returns capped proposals. The caller shows a preview
// sheet, and confirmed proposals flow through `GoalContributionService`
// with `kind: .autoRule`.
// ============================================================

/// How an allocation rule translates an income transaction into a goal
/// contribution. Phase 4b ships `percentOfIncome` and `fixedPerIncome`;
/// `fixedMonthly` (time-driven) and `roundUpExpense` (expense-driven) are
/// reserved names so future phases can extend without migration.
enum AllocationRuleType: String, Codable, CaseIterable {
    case percentOfIncome
    case fixedPerIncome
    case fixedMonthly      // reserved — time-driven
    case roundUpExpense    // reserved — expense-driven

    var isIncomeDriven: Bool {
        self == .percentOfIncome || self == .fixedPerIncome
    }

    var displayName: String {
        switch self {
        case .percentOfIncome: return "Percent of income"
        case .fixedPerIncome:  return "Fixed per income"
        case .fixedMonthly:    return "Fixed monthly"
        case .roundUpExpense:  return "Round-up from expense"
        }
    }
}

/// Which income transactions a rule matches.
enum AllocationRuleSource: String, Codable, CaseIterable {
    case allIncome
    case category
    case payee

    var displayName: String {
        switch self {
        case .allIncome: return "All income"
        case .category:  return "Category"
        case .payee:     return "Payee"
        }
    }
}

struct GoalAllocationRule: Identifiable, Codable, Hashable {
    let id: UUID
    var goalId: UUID
    var name: String
    var type: AllocationRuleType
    /// Meaning depends on `type`:
    ///   - `.percentOfIncome`: whole-percent (e.g. 10 → 10% of the income)
    ///   - `.fixedPerIncome`:  absolute cents (e.g. 5_000 → $50)
    ///   - reserved types: unused
    var amount: Int
    var source: AllocationRuleSource
    /// Category storage key when `source == .category`, or payee string
    /// when `source == .payee`. Nil for `.allIncome`.
    var sourceMatch: String?
    var priority: Int
    var isActive: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        goalId: UUID,
        name: String,
        type: AllocationRuleType,
        amount: Int,
        source: AllocationRuleSource = .allIncome,
        sourceMatch: String? = nil,
        priority: Int = 0,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.goalId = goalId
        self.name = name
        self.type = type
        self.amount = amount
        self.source = source
        self.sourceMatch = sourceMatch
        self.priority = priority
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
