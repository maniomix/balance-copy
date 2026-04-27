import Foundation

// MARK: - Goal Type

enum GoalType: String, Codable, CaseIterable, Identifiable {
    case emergencyFund = "emergency_fund"
    case vacation
    case tax
    case gadget
    case car
    case home
    case custom
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .emergencyFund: return "Emergency Fund"
        case .vacation: return "Vacation"
        case .tax: return "Tax"
        case .gadget: return "Gadget"
        case .car: return "Car"
        case .home: return "Home"
        case .custom: return "Custom"
        }
    }
    
    var defaultIcon: String {
        switch self {
        case .emergencyFund: return "shield.fill"
        case .vacation: return "airplane"
        case .tax: return "doc.text.fill"
        case .gadget: return "laptopcomputer"
        case .car: return "car.fill"
        case .home: return "house.fill"
        case .custom: return "star.fill"
        }
    }
    
    var defaultColor: String {
        switch self {
        case .emergencyFund: return "positive"
        case .vacation: return "accent"
        case .tax: return "warning"
        case .gadget: return "accent"
        case .car: return "subtext"
        case .home: return "positive"
        case .custom: return "accent"
        }
    }
}

// MARK: - Goal Model

struct Goal: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: GoalType
    var targetAmount: Int          // cents — current target (user-editable)
    var currentAmount: Int         // cents — denorm cache; truth is Σ contributions
    var currency: String
    var targetDate: Date?
    var linkedAccountId: UUID?
    var icon: String
    var colorToken: String
    var notes: String?
    var isCompleted: Bool
    let createdAt: Date
    var updatedAt: Date
    var userId: String

    // Phase 1.5 additions
    var priority: Int              // user-orderable; 0 = default, higher = sorted first
    var isArchived: Bool           // hidden from active list, not deleted
    var pausedAt: Date?            // if set, ignored by allocation rules and pace calc
    var categoryStorageKey: String?// optional Category link for round-up rules
    var originalTargetAmount: Int  // immutable snapshot of target at creation
    var householdId: UUID?         // set when shared (Phase 8)

    enum CodingKeys: String, CodingKey {
        case id, name, type, currency, icon, notes, priority
        case targetAmount = "target_amount"
        case currentAmount = "current_amount"
        case targetDate = "target_date"
        case linkedAccountId = "linked_account_id"
        case colorToken = "color_token"
        case isCompleted = "is_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userId = "user_id"
        case isArchived = "is_archived"
        case pausedAt = "paused_at"
        case categoryStorageKey = "category_storage_key"
        case originalTargetAmount = "original_target_amount"
        case householdId = "household_id"
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: GoalType,
        targetAmount: Int,
        currentAmount: Int = 0,
        currency: String = "EUR",
        targetDate: Date? = nil,
        linkedAccountId: UUID? = nil,
        icon: String? = nil,
        colorToken: String? = nil,
        notes: String? = nil,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        userId: String,
        priority: Int = 0,
        isArchived: Bool = false,
        pausedAt: Date? = nil,
        categoryStorageKey: String? = nil,
        originalTargetAmount: Int? = nil,
        householdId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.currency = currency
        self.targetDate = targetDate
        self.linkedAccountId = linkedAccountId
        self.icon = icon ?? type.defaultIcon
        self.colorToken = colorToken ?? type.defaultColor
        self.notes = notes
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userId = userId
        self.priority = priority
        self.isArchived = isArchived
        self.pausedAt = pausedAt
        self.categoryStorageKey = categoryStorageKey
        self.originalTargetAmount = originalTargetAmount ?? targetAmount
        self.householdId = householdId
    }

    // Backfill-tolerant decoder: rows predating Phase 1.5 lack the new columns.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.type = try c.decode(GoalType.self, forKey: .type)
        self.targetAmount = try c.decode(Int.self, forKey: .targetAmount)
        self.currentAmount = try c.decode(Int.self, forKey: .currentAmount)
        self.currency = try c.decode(String.self, forKey: .currency)
        self.targetDate = try c.decodeIfPresent(Date.self, forKey: .targetDate)
        self.linkedAccountId = try c.decodeIfPresent(UUID.self, forKey: .linkedAccountId)
        self.icon = try c.decode(String.self, forKey: .icon)
        self.colorToken = try c.decode(String.self, forKey: .colorToken)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.isCompleted = try c.decode(Bool.self, forKey: .isCompleted)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        self.userId = try c.decode(String.self, forKey: .userId)
        self.priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        self.isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        self.pausedAt = try c.decodeIfPresent(Date.self, forKey: .pausedAt)
        self.categoryStorageKey = try c.decodeIfPresent(String.self, forKey: .categoryStorageKey)
        self.originalTargetAmount = try c.decodeIfPresent(Int.self, forKey: .originalTargetAmount) ?? self.targetAmount
        self.householdId = try c.decodeIfPresent(UUID.self, forKey: .householdId)
    }
    
    // MARK: - Computed
    
    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(Double(currentAmount) / Double(targetAmount), 1.0)
    }
    
    var progressPercent: Int {
        Int(progress * 100)
    }
    
    var remainingAmount: Int {
        max(0, targetAmount - currentAmount)
    }
    
    /// True if this goal should be skipped by allocation rules and pace calculations.
    var isInactive: Bool {
        isArchived || pausedAt != nil || isCompleted
    }

    /// Monthly saving needed to hit target date.
    /// For overdue goals, returns the full remaining amount (needs immediate attention).
    /// For goals with no deadline, paused, or archived: nil.
    var requiredMonthlySaving: Int? {
        guard !isInactive else { return nil }
        guard let target = targetDate else { return nil }
        let remaining = remainingAmount
        guard remaining > 0 else { return 0 }
        let months = Calendar.current.dateComponents([.month], from: Date(), to: target).month ?? 0
        guard months > 0 else { return remaining } // overdue: full amount needed now
        return (remaining + months - 1) / months // round up so user doesn't undershoot
    }

    /// Months remaining until target date (negative if overdue, nil if no deadline)
    var monthsToTarget: Int? {
        guard let target = targetDate else { return nil }
        return Calendar.current.dateComponents([.month], from: Date(), to: target).month
    }

    /// Whether this goal's deadline has passed without completion
    var isOverdue: Bool {
        guard let target = targetDate, !isCompleted else { return false }
        return target < Date()
    }

    /// Estimated completion date based on average contribution pace
    func estimatedCompletion(averageMonthly: Int) -> Date? {
        guard averageMonthly > 0, remainingAmount > 0 else { return nil }
        let monthsNeeded = Int(ceil(Double(remainingAmount) / Double(averageMonthly)))
        return Calendar.current.date(byAdding: .month, value: monthsNeeded, to: Date())
    }

    /// Whether the estimated completion date will miss the target date
    func willMissDeadline(averageMonthly: Int) -> Bool {
        guard let target = targetDate, !isCompleted else { return false }
        guard let est = estimatedCompletion(averageMonthly: averageMonthly) else {
            // No contributions yet — will miss if deadline exists and remaining > 0
            return remainingAmount > 0
        }
        return est > target
    }

    /// Shortfall: how much extra per month is needed beyond current pace to hit deadline.
    /// Returns nil if no deadline, 0 if on track or ahead.
    func monthlyShortfall(averageMonthly: Int) -> Int? {
        guard let required = requiredMonthlySaving else { return nil }
        let gap = required - averageMonthly
        return max(0, gap)
    }

    /// On track / behind / ahead
    var trackingStatus: TrackingStatus {
        guard let target = targetDate else { return .noTarget }
        guard !isCompleted else { return .completed }

        // If overdue, always behind
        if target < Date() { return .behind }

        let totalDays = Calendar.current.dateComponents([.day], from: createdAt, to: target).day ?? 1
        let elapsedDays = Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
        guard totalDays > 0 else { return .behind }

        let expectedProgress = Double(elapsedDays) / Double(totalDays)
        let diff = progress - expectedProgress

        if diff >= 0.05 { return .ahead }
        if diff <= -0.05 { return .behind }
        return .onTrack
    }
    
    enum TrackingStatus {
        case ahead, onTrack, behind, completed, noTarget

        var label: String {
            switch self {
            case .ahead: return "Ahead"
            case .onTrack: return "On track"
            case .behind: return "Behind"
            case .completed: return "Completed"
            case .noTarget: return "No deadline"
            }
        }

        var icon: String {
            switch self {
            case .ahead: return "arrow.up.right"
            case .onTrack: return "checkmark.circle"
            case .behind: return "exclamationmark.triangle"
            case .completed: return "checkmark.circle.fill"
            case .noTarget: return "clock"
            }
        }

        var colorToken: String {
            switch self {
            case .ahead: return "positive"
            case .onTrack: return "accent"
            case .behind: return "danger"
            case .completed: return "positive"
            case .noTarget: return "subtext"
            }
        }
    }

    /// Days until target date (nil if no target)
    var daysRemaining: Int? {
        guard let target = targetDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: target).day
    }

    /// Required weekly saving to hit target date
    var requiredWeeklySaving: Int? {
        guard let target = targetDate else { return nil }
        let remaining = remainingAmount
        guard remaining > 0 else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: target).day ?? 0
        guard days > 0 else { return remaining }
        let weeks = max(1, days / 7)
        return remaining / weeks
    }
}

// MARK: - Goal Contribution

struct GoalContribution: Identifiable, Codable, Hashable {
    let id: UUID
    let goalId: UUID
    var amount: Int               // cents (negative = withdrawal)
    var note: String?
    var source: ContributionSource
    let createdAt: Date

    // Phase 1.5 additions
    var linkedTransactionId: UUID?  // for source == .transaction / .roundUp
    var linkedRuleId: UUID?         // for source == .allocationRule
    var isReversed: Bool            // soft-undo flag
    var reversedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, amount, note, source
        case goalId = "goal_id"
        case createdAt = "created_at"
        case linkedTransactionId = "linked_transaction_id"
        case linkedRuleId = "linked_rule_id"
        case isReversed = "is_reversed"
        case reversedAt = "reversed_at"
    }

    init(
        id: UUID = UUID(),
        goalId: UUID,
        amount: Int,
        note: String? = nil,
        source: ContributionSource = .manual,
        createdAt: Date = Date(),
        linkedTransactionId: UUID? = nil,
        linkedRuleId: UUID? = nil,
        isReversed: Bool = false,
        reversedAt: Date? = nil
    ) {
        self.id = id
        self.goalId = goalId
        self.amount = amount
        self.note = note
        self.source = source
        self.createdAt = createdAt
        self.linkedTransactionId = linkedTransactionId
        self.linkedRuleId = linkedRuleId
        self.isReversed = isReversed
        self.reversedAt = reversedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.goalId = try c.decode(UUID.self, forKey: .goalId)
        self.amount = try c.decode(Int.self, forKey: .amount)
        self.note = try c.decodeIfPresent(String.self, forKey: .note)
        self.source = (try? c.decode(ContributionSource.self, forKey: .source)) ?? .manual
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.linkedTransactionId = try c.decodeIfPresent(UUID.self, forKey: .linkedTransactionId)
        self.linkedRuleId = try c.decodeIfPresent(UUID.self, forKey: .linkedRuleId)
        self.isReversed = try c.decodeIfPresent(Bool.self, forKey: .isReversed) ?? false
        self.reversedAt = try c.decodeIfPresent(Date.self, forKey: .reversedAt)
    }

    enum ContributionSource: String, Codable {
        case manual
        case transaction
        case transfer
        case allocationRule = "allocation_rule"
        case aiAction = "ai_action"
        case roundUp = "round_up"
    }
}
