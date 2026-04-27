import Foundation

// ============================================================
// MARK: - Review Item (Phase 6b — iOS port)
// ============================================================
//
// Unified row in the Review Queue. Value type, Codable so the queue
// can be cached; amounts stored as `Int` cents matching iOS
// convention.
//
// Ported from macOS Centmond. iOS subsets the reason codes: several
// macOS reasons (`pendingTxn`, `staleCleared`, `negativeIncome`,
// `unreviewedTransfer`, `unlinkedRecurring`) require data shapes
// iOS doesn't have (Transaction status/transfer, txn→template
// backlink). Those enum cases are defined for forward compatibility
// but never emitted by the current iOS detectors.
// ============================================================

enum ReviewReasonCode: String, CaseIterable, Codable, Sendable {
    case uncategorizedTxn
    case pendingTxn
    case unusualAmount
    case duplicateCandidate
    case missingAccount
    case unlinkedRecurring
    case unlinkedSubscription
    case unreviewedTransfer
    case futureDated
    case negativeIncome
    case staleCleared

    var title: String {
        switch self {
        case .uncategorizedTxn:     return "Needs category"
        case .pendingTxn:           return "Pending"
        case .unusualAmount:        return "Unusual amount"
        case .duplicateCandidate:   return "Possible duplicate"
        case .missingAccount:       return "Missing account"
        case .unlinkedRecurring:    return "Unlinked recurring"
        case .unlinkedSubscription: return "Unlinked subscription"
        case .unreviewedTransfer:   return "Unreviewed transfer"
        case .futureDated:          return "Future-dated"
        case .negativeIncome:       return "Negative income"
        case .staleCleared:         return "Stale cleared"
        }
    }

    var icon: String {
        switch self {
        case .uncategorizedTxn:     return "questionmark.circle.fill"
        case .pendingTxn:           return "clock.fill"
        case .unusualAmount:        return "exclamationmark.triangle.fill"
        case .duplicateCandidate:   return "doc.on.doc.fill"
        case .missingAccount:       return "building.columns"
        case .unlinkedRecurring:    return "arrow.triangle.2.circlepath"
        case .unlinkedSubscription: return "repeat.circle.fill"
        case .unreviewedTransfer:   return "arrow.left.arrow.right"
        case .futureDated:          return "calendar.badge.exclamationmark"
        case .negativeIncome:       return "arrow.down.right.circle.fill"
        case .staleCleared:         return "hourglass"
        }
    }
}

enum ReviewSeverity: Int, Comparable, Codable, Sendable {
    case low = 0
    case suggested = 1
    case blocker = 2

    static func < (a: ReviewSeverity, b: ReviewSeverity) -> Bool { a.rawValue < b.rawValue }
}

/// One row in the Review Queue. iOS uses `Int` cents + UUID refs
/// (no SwiftData relationships).
struct ReviewQueueItem: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let reason: ReviewReasonCode
    let severity: ReviewSeverity

    /// Primary subject — most reasons are transaction-bound.
    let transactionId: UUID?
    let recurringTemplateId: UUID?
    let subscriptionId: UUID?

    /// Stable key for dedupe + dismissal lookup.
    /// Convention: "<reasonCode>:<subjectID>[:<suffix>]".
    let dedupeKey: String

    /// Date used for secondary sort after severity (usually tx date).
    let sortDate: Date

    /// Magnitude used for tertiary sort (higher first); zero skips.
    let amountMagnitude: Int  // cents

    /// Full dismissal key used by the Store-side dismiss list.
    var dismissalKey: String { "review:\(dedupeKey)" }
}
