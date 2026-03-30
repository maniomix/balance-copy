import Foundation
import SwiftUI

// ============================================================
// MARK: - Transaction Review Models
// ============================================================
//
// Models for the transaction review / data cleaning system.
//
// ReviewItem represents a single flagged issue that needs
// the user's attention. Each item links to one or more
// transactions and carries a suggested action.
// ============================================================

// MARK: - Review Type

enum ReviewType: String, Codable, CaseIterable, Identifiable {
    case uncategorized
    case possibleDuplicate = "possible_duplicate"
    case spendingSpike = "spending_spike"
    case recurringCandidate = "recurring_candidate"
    case merchantNormalization = "merchant_normalization"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .uncategorized: return "Uncategorized"
        case .possibleDuplicate: return "Possible Duplicate"
        case .spendingSpike: return "Spending Spike"
        case .recurringCandidate: return "Recurring Candidate"
        case .merchantNormalization: return "Merchant Naming"
        }
    }

    var icon: String {
        switch self {
        case .uncategorized: return "tag.slash"
        case .possibleDuplicate: return "doc.on.doc"
        case .spendingSpike: return "chart.line.uptrend.xyaxis"
        case .recurringCandidate: return "repeat"
        case .merchantNormalization: return "textformat.abc"
        }
    }

    var color: Color {
        switch self {
        case .uncategorized: return DS.Colors.warning
        case .possibleDuplicate: return DS.Colors.danger
        case .spendingSpike: return Color(hexValue: 0x9B59B6)
        case .recurringCandidate: return DS.Colors.accent
        case .merchantNormalization: return Color(hexValue: 0x1ABC9C)
        }
    }
}

// MARK: - Review Priority

enum ReviewPriority: Int, Codable, Comparable {
    case low = 0
    case medium = 1
    case high = 2

    static func < (lhs: ReviewPriority, rhs: ReviewPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var color: Color {
        switch self {
        case .low: return DS.Colors.subtext
        case .medium: return DS.Colors.warning
        case .high: return DS.Colors.danger
        }
    }
}

// MARK: - Review Status

enum ReviewStatus: String, Codable {
    case pending
    case resolved
    case dismissed
}

// MARK: - Suggested Action

enum SuggestedAction: String, Codable {
    case assignCategory = "assign_category"
    case markDuplicate = "mark_duplicate"
    case ignore
    case createRecurring = "create_recurring"
    case mergeMerchant = "merge_merchant"
    case reviewAmount = "review_amount"

    var displayName: String {
        switch self {
        case .assignCategory: return "Assign Category"
        case .markDuplicate: return "Mark as Duplicate"
        case .ignore: return "Dismiss"
        case .createRecurring: return "Create Recurring"
        case .mergeMerchant: return "Normalize Name"
        case .reviewAmount: return "Review Amount"
        }
    }

    var icon: String {
        switch self {
        case .assignCategory: return "tag"
        case .markDuplicate: return "xmark.bin"
        case .ignore: return "hand.raised"
        case .createRecurring: return "repeat"
        case .mergeMerchant: return "pencil"
        case .reviewAmount: return "exclamationmark.circle"
        }
    }
}

// MARK: - Review Item

struct ReviewItem: Identifiable, Hashable {
    let id: UUID
    let transactionIds: [UUID]       // one or more linked transactions
    let type: ReviewType
    let priority: ReviewPriority
    let reason: String               // human-readable explanation
    let suggestedAction: SuggestedAction
    let createdAt: Date
    var resolvedAt: Date?
    var status: ReviewStatus

    // Context data for the review action
    let merchantName: String?        // for normalization issues
    let suggestedCategory: Category? // for uncategorized
    let duplicateGroupId: UUID?      // groups duplicates together
    let spikeAmount: Int?            // cents — the spike amount
    let spikeAverage: Int?           // cents — the category average

    /// Deterministic key derived from review type + sorted transaction IDs.
    /// Used for dismissal persistence — survives queue rebuilds because
    /// the same underlying issue always produces the same key.
    let stableKey: String

    init(
        id: UUID = UUID(),
        transactionIds: [UUID],
        type: ReviewType,
        priority: ReviewPriority,
        reason: String,
        suggestedAction: SuggestedAction,
        createdAt: Date = Date(),
        resolvedAt: Date? = nil,
        status: ReviewStatus = .pending,
        merchantName: String? = nil,
        suggestedCategory: Category? = nil,
        duplicateGroupId: UUID? = nil,
        spikeAmount: Int? = nil,
        spikeAverage: Int? = nil
    ) {
        self.id = id
        self.transactionIds = transactionIds
        self.type = type
        self.priority = priority
        self.reason = reason
        self.suggestedAction = suggestedAction
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.status = status
        self.merchantName = merchantName
        self.suggestedCategory = suggestedCategory
        self.duplicateGroupId = duplicateGroupId
        self.spikeAmount = spikeAmount
        self.spikeAverage = spikeAverage

        // Stable key: type + sorted transaction UUIDs
        // Same issue always produces the same key across detect() calls
        self.stableKey = type.rawValue + ":" + transactionIds.map { $0.uuidString }.sorted().joined(separator: "|")
    }

    // Hashable
    static func == (lhs: ReviewItem, rhs: ReviewItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
