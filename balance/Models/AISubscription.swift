import Foundation

// ============================================================
// MARK: - AISubscription Models (Phase 3a — iOS port)
// ============================================================
//
// Value-type subscription domain ported from macOS Centmond.
// macOS uses SwiftData `@Model` classes with relationships;
// iOS uses Codable structs stored on `Store`, with UUID refs.
// Amounts are Int cents (iOS convention), not Decimal.
//
// MIGRATION TARGET (Subscription Rebuild — Phase 1+9, 2026-04-27):
// `DetectedSubscription` is the canonical subscription model. The
// Subscription Rebuild went 1–9 covering the model, persistence,
// detection quality, full UI, notifications, dashboard card, AI
// integration, and cleanup. This file and the AISubscription-typed
// services below remain only because they're called by AI/forecast
// code that has unrelated heavy uncommitted work. They will be
// deleted in a follow-up commit once those callers redirect at the
// canonical model.
//
// REPLACEMENT POINTERS — when you migrate a caller:
//   • AISubscription                     → DetectedSubscription
//   • AISubscriptionCharge               → DetectedSubscription.chargeHistory[].ChargeRecord
//   • AISubscriptionPriceChange          → DetectedSubscription.priceChangePercent /
//                                          .priceChangeAmount (derived; ≥3 charges)
//   • Store.aiSubscriptions              → SubscriptionEngine.shared.subscriptions
//   • Store.aiSubscriptionCharges        → record.chargeHistory
//   • Store.aiSubscriptionPriceChanges   → derived per record (no separate array)
//   • SubscriptionForecast               → (use SubscriptionEngine.upcomingRenewals
//                                          and the snapshot's billingCycle math
//                                          via DetectedSubscription.effectiveCadenceDays)
//   • SubscriptionNotificationScheduler  → SubscriptionAlertScheduler (Phase 6a)
//   • AISubscription.merchantKey(for:)   → DetectedSubscription.merchantKey(for:)
//                                          (same canonicalization, kept identical)
//
// Do NOT add new call sites against AISubscription.
//
// ============================================================

// MARK: - Billing cycle

enum AIBillingCycle: String, Codable, Hashable, CaseIterable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case semiannual
    case annual
    case custom

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .semiannual: return "Every 6 months"
        case .annual: return "Yearly"
        case .custom: return "Custom"
        }
    }

    /// Standard cadence in days — used by detector reconciliation and the
    /// upcoming-charges calendar so `.custom` doesn't have to special-case
    /// every call site.
    var standardDays: Int? {
        switch self {
        case .weekly: return 7
        case .biweekly: return 14
        case .monthly: return 30
        case .quarterly: return 91
        case .semiannual: return 182
        case .annual: return 365
        case .custom: return nil
        }
    }
}

// MARK: - Status

enum AISubscriptionStatus: String, Codable, Hashable, CaseIterable {
    case active
    case trial
    case paused
    case cancelled
}

// MARK: - Source / Provenance

enum AISubscriptionSource: String, Codable, Hashable, CaseIterable {
    case manual       // user-added via the sheet
    case detected     // confirmed from a detector candidate
    case imported     // brought in via CSV / reconciliation backfill
}

// MARK: - Subscription

struct AISubscription: Identifiable, Codable, Hashable {
    let id: UUID
    var serviceName: String
    var merchantKey: String
    var categoryName: String
    var amount: Int                 // cents, iOS convention
    var currency: String
    var billingCycle: AIBillingCycle
    var customCadenceDays: Int?
    var nextPaymentDate: Date
    var lastChargeDate: Date?
    var firstChargeDate: Date?
    var status: AISubscriptionStatus

    // Trial tracking — kept as a flag for detector provenance without
    // forcing `status == .trial`.
    var isTrial: Bool
    var trialEndsAt: Date?

    // Detection provenance.
    var source: AISubscriptionSource
    var autoDetected: Bool
    var detectionConfidence: Double

    /// Late-night impulse-signup flag (22:00–04:00 local). Not critical —
    /// feeds the optimizer so a "you signed up at 2 AM" badge can render.
    var wasImpulseSignup: Bool

    // Display & lifecycle
    var colorHex: String?
    var iconSymbol: String?
    var notes: String?
    var cancellationURL: String?

    var createdAt: Date
    var updatedAt: Date

    // References — UUID instead of SwiftData relationships.
    var accountId: UUID?

    init(
        id: UUID = UUID(),
        serviceName: String,
        categoryName: String = "AISubscriptions",
        amount: Int,
        currency: String = "USD",
        billingCycle: AIBillingCycle = .monthly,
        customCadenceDays: Int? = nil,
        nextPaymentDate: Date,
        lastChargeDate: Date? = nil,
        firstChargeDate: Date? = nil,
        status: AISubscriptionStatus = .active,
        isTrial: Bool = false,
        trialEndsAt: Date? = nil,
        source: AISubscriptionSource = .manual,
        autoDetected: Bool = false,
        detectionConfidence: Double = 0,
        wasImpulseSignup: Bool = false,
        colorHex: String? = nil,
        iconSymbol: String? = nil,
        notes: String? = nil,
        cancellationURL: String? = nil,
        accountId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.serviceName = serviceName
        self.merchantKey = Self.merchantKey(for: serviceName)
        self.categoryName = categoryName
        self.amount = amount
        self.currency = currency
        self.billingCycle = billingCycle
        self.customCadenceDays = customCadenceDays
        self.nextPaymentDate = nextPaymentDate
        self.lastChargeDate = lastChargeDate
        self.firstChargeDate = firstChargeDate
        self.status = status
        self.isTrial = isTrial
        self.trialEndsAt = trialEndsAt
        self.source = source
        self.autoDetected = autoDetected
        self.detectionConfidence = detectionConfidence
        self.wasImpulseSignup = wasImpulseSignup
        self.colorHex = colorHex
        self.iconSymbol = iconSymbol
        self.notes = notes
        self.cancellationURL = cancellationURL
        self.accountId = accountId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Derived

    /// Annual cost in cents.
    var annualCost: Int {
        switch billingCycle {
        case .weekly: return amount * 52
        case .biweekly: return amount * 26
        case .monthly: return amount * 12
        case .quarterly: return amount * 4
        case .semiannual: return amount * 2
        case .annual: return amount
        case .custom:
            let days = max(customCadenceDays ?? 30, 1)
            return Int((Double(amount) * 365.0 / Double(days)).rounded())
        }
    }

    var monthlyCost: Int { annualCost / 12 }

    /// Effective cadence in days — `.custom` yields its configured value,
    /// falling back to 30 if unset.
    var effectiveCadenceDays: Int {
        billingCycle.standardDays ?? max(customCadenceDays ?? 30, 1)
    }

    /// True when the next expected charge is more than 3 days overdue.
    /// Reconciliation (3b) advances `nextPaymentDate` whenever a charge lands;
    /// anything that stays past-due means the merchant didn't bill, the user
    /// paused, or the charge came in under a different merchant string.
    var isPastDue: Bool {
        guard status == .active || status == .trial else { return false }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) else {
            return false
        }
        return nextPaymentDate < cutoff
    }

    // MARK: - Merchant key

    /// Canonical key for matching incoming transactions. Lowercased,
    /// punctuation-stripped, whitespace-collapsed.
    static func merchantKey(for serviceName: String) -> String {
        let trimmed = serviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mapped = trimmed.unicodeScalars.map { scalar -> Character in
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        return String(mapped)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}

// MARK: - AISubscriptionCharge

/// A single charge attached to a AISubscription. Ties back to a Transaction
/// via `transactionId` so the ledger and the subscription history stay
/// in sync without duplicating amount data.
struct AISubscriptionCharge: Identifiable, Codable, Hashable {
    let id: UUID
    var subscriptionId: UUID
    var date: Date
    var amount: Int              // cents
    var currency: String
    var transactionId: UUID?
    var matchedAutomatically: Bool
    var matchConfidence: Double
    var notes: String?
    /// Set by reconciliation when a charge lands inside the duplicate window
    /// of a prior charge on the same subscription. UI can surface a badge.
    var isFlaggedDuplicate: Bool

    init(
        id: UUID = UUID(),
        subscriptionId: UUID,
        date: Date,
        amount: Int,
        currency: String = "USD",
        transactionId: UUID? = nil,
        matchedAutomatically: Bool = true,
        matchConfidence: Double = 0,
        notes: String? = nil,
        isFlaggedDuplicate: Bool = false
    ) {
        self.id = id
        self.subscriptionId = subscriptionId
        self.date = date
        self.amount = amount
        self.currency = currency
        self.transactionId = transactionId
        self.matchedAutomatically = matchedAutomatically
        self.matchConfidence = matchConfidence
        self.notes = notes
        self.isFlaggedDuplicate = isFlaggedDuplicate
    }
}

// MARK: - AISubscriptionPriceChange

/// Logged when reconciliation sees a charge whose amount differs from the
/// subscription's current `amount` by more than `priceChangeThreshold`.
struct AISubscriptionPriceChange: Identifiable, Codable, Hashable {
    let id: UUID
    var subscriptionId: UUID
    var observedAt: Date
    var oldAmount: Int            // cents
    var newAmount: Int            // cents
    var percentChange: Double     // signed fraction (0.1 = +10%)
    /// Set to true once the user has seen / tapped through the price-change
    /// notification. The notification scheduler skips acknowledged rows.
    var acknowledged: Bool

    init(
        id: UUID = UUID(),
        subscriptionId: UUID,
        observedAt: Date = Date(),
        oldAmount: Int,
        newAmount: Int,
        acknowledged: Bool = false
    ) {
        self.id = id
        self.subscriptionId = subscriptionId
        self.observedAt = observedAt
        self.oldAmount = oldAmount
        self.newAmount = newAmount
        self.percentChange = oldAmount == 0 ? 0 : (Double(newAmount - oldAmount) / Double(oldAmount))
        self.acknowledged = acknowledged
    }
}
