import Foundation
import SwiftUI

// ============================================================
// MARK: - Detected Subscription Model
// ============================================================
//
// Represents a detected or manually-added subscription/recurring
// service charge. Tracks merchant, amount, billing cycle,
// and provides insight labels for the user.
//
// All amounts are in cents (Int) for precision.
// ============================================================

// MARK: - Billing Cycle

enum BillingCycle: String, Codable, CaseIterable, Identifiable {
    case weekly
    case monthly
    case yearly
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .weekly: return "calendar.badge.clock"
        case .monthly: return "calendar"
        case .yearly: return "calendar.badge.checkmark"
        case .custom: return "calendar.badge.exclamationmark"
        }
    }

    /// Approximate days in this billing cycle
    var approximateDays: Int {
        switch self {
        case .weekly: return 7
        case .monthly: return 30
        case .yearly: return 365
        case .custom: return 30
        }
    }

    /// Convert amount to monthly equivalent (cents).
    /// Uses precise conversion: weekly × 52 / 12, yearly rounds to nearest cent.
    func toMonthly(amount: Int) -> Int {
        switch self {
        case .weekly: return (amount * 52 + 6) / 12   // round to nearest
        case .monthly: return amount
        case .yearly: return (amount + 6) / 12         // round to nearest
        case .custom: return amount
        }
    }

    /// Convert amount to yearly equivalent (cents)
    func toYearly(amount: Int) -> Int {
        switch self {
        case .weekly: return amount * 52
        case .monthly: return amount * 12
        case .yearly: return amount
        case .custom: return amount * 12
        }
    }
}

// MARK: - Subscription Status

enum SubscriptionStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case paused
    case suspectedUnused = "suspected_unused"
    case cancelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .suspectedUnused: return "Maybe Unused"
        case .cancelled: return "Cancelled"
        }
    }

    var icon: String {
        switch self {
        case .active: return "checkmark.circle.fill"
        case .paused: return "pause.circle.fill"
        case .suspectedUnused: return "questionmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .active: return DS.Colors.positive
        case .paused: return DS.Colors.warning
        case .suspectedUnused: return Color(hexValue: 0x9B59B6)
        case .cancelled: return DS.Colors.subtext
        }
    }
}

// MARK: - Insight Label

enum SubscriptionInsight: String, Codable, Identifiable {
    case priceIncreased = "price_increased"
    case upcomingRenewal = "upcoming_renewal"
    case maybeUnused = "maybe_unused"
    case duplicateRisk = "duplicate_risk"
    case missedCharge = "missed_charge"
    case newlyDetected = "newly_detected"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .priceIncreased: return "Price Increased"
        case .upcomingRenewal: return "Upcoming Renewal"
        case .maybeUnused: return "Maybe Unused"
        case .duplicateRisk: return "Duplicate Risk"
        case .missedCharge: return "Missed Charge"
        case .newlyDetected: return "Newly Detected"
        }
    }

    var icon: String {
        switch self {
        case .priceIncreased: return "arrow.up.circle.fill"
        case .upcomingRenewal: return "bell.fill"
        case .maybeUnused: return "questionmark.circle.fill"
        case .duplicateRisk: return "doc.on.doc.fill"
        case .missedCharge: return "exclamationmark.triangle.fill"
        case .newlyDetected: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .priceIncreased: return DS.Colors.danger
        case .upcomingRenewal: return DS.Colors.accent
        case .maybeUnused: return Color(hexValue: 0x9B59B6)
        case .duplicateRisk: return DS.Colors.warning
        case .missedCharge: return DS.Colors.danger
        case .newlyDetected: return DS.Colors.positive
        }
    }
}

// MARK: - Detected Subscription

struct DetectedSubscription: Identifiable, Codable, Hashable {
    let id: UUID
    var merchantName: String
    var category: Category
    var expectedAmount: Int         // cents — average/typical charge
    var lastAmount: Int             // cents — most recent charge
    var billingCycle: BillingCycle
    var nextRenewalDate: Date?
    var lastChargeDate: Date?
    var status: SubscriptionStatus
    var linkedTransactionIds: [UUID]
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    // Detection metadata
    var isAutoDetected: Bool
    var confidenceScore: Double     // 0.0–1.0 detection confidence
    var chargeHistory: [ChargeRecord]
    var detectedIntervalDays: Int   // actual median interval from detection (for next-renewal)

    init(
        id: UUID = UUID(),
        merchantName: String,
        category: Category = .bills,
        expectedAmount: Int,
        lastAmount: Int = 0,
        billingCycle: BillingCycle = .monthly,
        nextRenewalDate: Date? = nil,
        lastChargeDate: Date? = nil,
        status: SubscriptionStatus = .active,
        linkedTransactionIds: [UUID] = [],
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isAutoDetected: Bool = true,
        confidenceScore: Double = 0.0,
        chargeHistory: [ChargeRecord] = [],
        detectedIntervalDays: Int = 0
    ) {
        self.id = id
        self.merchantName = merchantName
        self.category = category
        self.expectedAmount = expectedAmount
        self.lastAmount = lastAmount > 0 ? lastAmount : expectedAmount
        self.billingCycle = billingCycle
        self.nextRenewalDate = nextRenewalDate
        self.lastChargeDate = lastChargeDate
        self.status = status
        self.linkedTransactionIds = linkedTransactionIds
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isAutoDetected = isAutoDetected
        self.confidenceScore = confidenceScore
        self.chargeHistory = chargeHistory
        self.detectedIntervalDays = detectedIntervalDays > 0 ? detectedIntervalDays : billingCycle.approximateDays
    }

    // MARK: - Computed

    /// Monthly cost equivalent in cents
    var monthlyCost: Int {
        billingCycle.toMonthly(amount: expectedAmount)
    }

    /// Yearly cost equivalent in cents
    var yearlyCost: Int {
        billingCycle.toYearly(amount: expectedAmount)
    }

    /// Days until next renewal (nil if unknown)
    var daysUntilRenewal: Int? {
        guard let next = nextRenewalDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: next).day
    }

    /// Whether a meaningful price increase was detected (>2% of previous charge)
    var hasPriceIncrease: Bool {
        guard chargeHistory.count >= 2 else { return false }
        let sorted = chargeHistory.sorted { $0.date < $1.date }
        guard let prev = sorted.dropLast().last, let last = sorted.last else { return false }
        guard prev.amount > 0 else { return false }
        let increaseRatio = Double(last.amount - prev.amount) / Double(prev.amount)
        return increaseRatio > 0.02 // >2% increase
    }

    /// Price increase amount in cents (positive = went up)
    var priceChangeAmount: Int? {
        guard chargeHistory.count >= 2 else { return nil }
        let sorted = chargeHistory.sorted { $0.date < $1.date }
        guard let prev = sorted.dropLast().last, let last = sorted.last else { return nil }
        let diff = last.amount - prev.amount
        return diff != 0 ? diff : nil
    }

    /// Price increase as a percentage (e.g. 5.2 means 5.2% increase)
    var priceChangePercent: Double? {
        guard chargeHistory.count >= 2 else { return nil }
        let sorted = chargeHistory.sorted { $0.date < $1.date }
        guard let prev = sorted.dropLast().last, let last = sorted.last else { return nil }
        guard prev.amount > 0 else { return nil }
        let pct = Double(last.amount - prev.amount) / Double(prev.amount) * 100.0
        return abs(pct) >= 0.5 ? pct : nil // only report if ≥0.5%
    }

    /// Whether this subscription is likely unused (no recent interaction hints)
    var isLikelyUnused: Bool {
        status == .suspectedUnused
    }

    /// Days since the most recent charge (nil if no history)
    var daysSinceLastCharge: Int? {
        guard let last = lastChargeDate else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }

    /// Whether the expected next charge was missed (past due by >5 days)
    var hasMissedCharge: Bool {
        guard let next = nextRenewalDate, status == .active else { return false }
        let days = Calendar.current.dateComponents([.day], from: next, to: Date()).day ?? 0
        return days > 5 // overdue by more than 5 days
    }
}

// MARK: - Charge Record

struct ChargeRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let transactionId: UUID
    let amount: Int         // cents
    let date: Date

    init(id: UUID = UUID(), transactionId: UUID, amount: Int, date: Date) {
        self.id = id
        self.transactionId = transactionId
        self.amount = amount
        self.date = date
    }
}
