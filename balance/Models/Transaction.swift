import SwiftUI

// MARK: - Transaction Type

enum TransactionType: String, Codable, Hashable, CaseIterable {
    case expense = "expense"
    case income = "income"

    var icon: String {
        switch self {
        case .expense: return "minus"
        case .income: return "plus"
        }
    }

    var color: Color {
        switch self {
        case .expense: return DS.Colors.danger
        case .income: return DS.Colors.positive
        }
    }

    var title: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        }
    }
}

// MARK: - Payment Method

enum PaymentMethod: String, Codable, Hashable, CaseIterable {
    case cash = "cash"
    case card = "card"

    var icon: String {
        switch self {
        case .cash: return "banknote"
        case .card: return "creditcard.fill"
        }
    }

    var displayName: String {
        switch self {
        case .cash: return "Cash"
        case .card: return "Card"
        }
    }

    var tint: Color {
        switch self {
        case .cash: return Color(hexValue: 0x34C78C)  // Soft green
        case .card: return Color(hexValue: 0x4559F5)  // Refined blue
        }
    }

    var tintSecondary: Color {
        switch self {
        case .cash: return Color(hexValue: 0x2BA571)  // Deeper green
        case .card: return Color(hexValue: 0x3344CC)  // Deeper blue
        }
    }

    var accentColor: Color {
        switch self {
        case .cash: return Color(hexValue: 0x34C78C)
        case .card: return Color(hexValue: 0x4559F5)
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .cash:
            return [Color(hexValue: 0x34C78C), Color(hexValue: 0x2BA571)]
        case .card:
            return [Color(hexValue: 0x4559F5), Color(hexValue: 0x6C63FF)]
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .cash:
            return LinearGradient(
                colors: [Color(hexValue: 0x34C78C), Color(hexValue: 0x2BA571)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .card:
            return LinearGradient(
                colors: [Color(hexValue: 0x4559F5), Color(hexValue: 0x6C63FF)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Attachment Type

enum AttachmentType: String, Codable, Hashable {
    case image
    case pdf
    case other
}

// MARK: - Transaction

struct Transaction: Identifiable, Hashable, Codable {
    let id: UUID
    var amount: Int
    var date: Date
    var category: Category
    var note: String
    var paymentMethod: PaymentMethod
    var type: TransactionType
    var attachmentData: Data?
    var attachmentType: AttachmentType?
    var accountId: UUID?
    var isFlagged: Bool
    var linkedGoalId: UUID?
    var lastModified: Date

    init(id: UUID = UUID(), amount: Int, date: Date, category: Category, note: String, paymentMethod: PaymentMethod = .card, type: TransactionType = .expense, attachmentData: Data? = nil, attachmentType: AttachmentType? = nil, accountId: UUID? = nil, isFlagged: Bool = false, linkedGoalId: UUID? = nil, lastModified: Date = Date()) {
        self.id = id
        self.amount = amount
        self.date = date
        self.category = category
        self.note = note
        self.paymentMethod = paymentMethod
        self.type = type
        self.attachmentData = attachmentData
        self.attachmentType = attachmentType
        self.accountId = accountId
        self.isFlagged = isFlagged
        self.linkedGoalId = linkedGoalId
        self.lastModified = lastModified
    }

    enum CodingKeys: String, CodingKey {
        case id, amount, date, category, note, paymentMethod, type, attachmentData, attachmentType, accountId, isFlagged, linkedGoalId, lastModified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        amount = try container.decode(Int.self, forKey: .amount)
        date = try container.decode(Date.self, forKey: .date)
        category = try container.decode(Category.self, forKey: .category)
        note = try container.decode(String.self, forKey: .note)

        // Old data compatibility
        paymentMethod = try container.decodeIfPresent(PaymentMethod.self, forKey: .paymentMethod) ?? .card
        type = try container.decodeIfPresent(TransactionType.self, forKey: .type) ?? .expense
        attachmentData = try container.decodeIfPresent(Data.self, forKey: .attachmentData)
        attachmentType = try container.decodeIfPresent(AttachmentType.self, forKey: .attachmentType)
        accountId = try container.decodeIfPresent(UUID.self, forKey: .accountId)
        isFlagged = try container.decodeIfPresent(Bool.self, forKey: .isFlagged) ?? false
        linkedGoalId = try container.decodeIfPresent(UUID.self, forKey: .linkedGoalId)
        lastModified = try container.decodeIfPresent(Date.self, forKey: .lastModified) ?? date
    }
}

// MARK: - Recurring Frequency

enum RecurringFrequency: String, Codable, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case yearly = "yearly"

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    var icon: String {
        switch self {
        case .daily: return "sun.max"
        case .weekly: return "calendar.badge.clock"
        case .monthly: return "calendar"
        case .yearly: return "calendar.badge.checkmark"
        }
    }
}
