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
    var targetAmount: Int          // cents
    var currentAmount: Int         // cents
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
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, currency, icon, notes
        case targetAmount = "target_amount"
        case currentAmount = "current_amount"
        case targetDate = "target_date"
        case linkedAccountId = "linked_account_id"
        case colorToken = "color_token"
        case isCompleted = "is_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userId = "user_id"
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
        userId: String
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
    
    /// Monthly saving needed to hit target date.
    /// For overdue goals, returns the full remaining amount (needs immediate attention).
    /// For goals with no deadline, returns nil.
    var requiredMonthlySaving: Int? {
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
    var amount: Int               // cents
    var note: String?
    var source: ContributionSource
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, amount, note, source
        case goalId = "goal_id"
        case createdAt = "created_at"
    }
    
    init(
        id: UUID = UUID(),
        goalId: UUID,
        amount: Int,
        note: String? = nil,
        source: ContributionSource = .manual,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.goalId = goalId
        self.amount = amount
        self.note = note
        self.source = source
        self.createdAt = createdAt
    }
    
    enum ContributionSource: String, Codable {
        case manual
        case transaction
        case transfer
    }
}
