import Foundation

// MARK: - Account Type

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case cash
    case bank
    case creditCard = "credit_card"
    case savings
    case investment
    case loan
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .cash: return "Cash"
        case .bank: return "Bank Account"
        case .creditCard: return "Credit Card"
        case .savings: return "Savings"
        case .investment: return "Investment"
        case .loan: return "Loan"
        }
    }
    
    var iconName: String {
        switch self {
        case .cash: return "banknote"
        case .bank: return "building.columns"
        case .creditCard: return "creditcard"
        case .savings: return "dollarsign.circle"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .loan: return "arrow.left.arrow.right"
        }
    }
    
    /// Assets increase net worth, liabilities decrease it
    var isAsset: Bool {
        switch self {
        case .cash, .bank, .savings, .investment:
            return true
        case .creditCard, .loan:
            return false
        }
    }
    
    var isLiability: Bool { !isAsset }
}

// MARK: - Account Model

struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: AccountType
    var currentBalance: Double
    var currency: String
    var institutionName: String?
    var creditLimit: Double?
    var interestRate: Double?
    var isArchived: Bool
    let createdAt: Date
    var updatedAt: Date
    var userId: UUID
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case currentBalance = "current_balance"
        case currency
        case institutionName = "institution_name"
        case creditLimit = "credit_limit"
        case interestRate = "interest_rate"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userId = "user_id"
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        currentBalance: Double = 0,
        currency: String = UserDefaults.standard.string(forKey: "app.currency") ?? "EUR",
        institutionName: String? = nil,
        creditLimit: Double? = nil,
        interestRate: Double? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        userId: UUID
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.currentBalance = currentBalance
        self.currency = currency
        self.institutionName = institutionName
        self.creditLimit = creditLimit
        self.interestRate = interestRate
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userId = userId
    }
    
    /// Absolute balance for net worth calculation
    var effectiveBalance: Double {
        type.isAsset ? currentBalance : -abs(currentBalance)
    }
    
    /// Available credit for credit cards
    var availableCredit: Double? {
        guard type == .creditCard, let limit = creditLimit else { return nil }
        return limit - abs(currentBalance)
    }
}

// MARK: - Balance Snapshot

struct AccountBalanceSnapshot: Identifiable, Codable, Hashable {
    let id: UUID
    let accountId: UUID
    let balance: Double
    let snapshotDate: Date
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case balance
        case snapshotDate = "snapshot_date"
        case createdAt = "created_at"
    }
    
    init(
        id: UUID = UUID(),
        accountId: UUID,
        balance: Double,
        snapshotDate: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.balance = balance
        self.snapshotDate = snapshotDate
        self.createdAt = createdAt
    }
}

// MARK: - Net Worth Data

struct NetWorthDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let totalAssets: Double
    let totalLiabilities: Double
    var netWorth: Double { totalAssets - totalLiabilities }
}

struct NetWorthSummary {
    let totalAssets: Double
    let totalLiabilities: Double
    let netWorth: Double
    let changeFromLastMonth: Double
    let changePercentage: Double
    
    static let empty = NetWorthSummary(
        totalAssets: 0, totalLiabilities: 0, netWorth: 0,
        changeFromLastMonth: 0, changePercentage: 0
    )
}
