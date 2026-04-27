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
    case biweekly
    case monthly
    case quarterly
    case semiannual
    case yearly
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .semiannual: return "Every 6 months"
        case .yearly: return "Yearly"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .weekly: return "calendar.badge.clock"
        case .biweekly: return "calendar.badge.clock"
        case .monthly: return "calendar"
        case .quarterly: return "calendar"
        case .semiannual: return "calendar"
        case .yearly: return "calendar.badge.checkmark"
        case .custom: return "calendar.badge.exclamationmark"
        }
    }

    /// Approximate days in this billing cycle. `.custom` returns 30 as a
    /// fallback — callers that have a custom cadence should use
    /// `DetectedSubscription.effectiveCadenceDays` instead.
    var approximateDays: Int {
        switch self {
        case .weekly: return 7
        case .biweekly: return 14
        case .monthly: return 30
        case .quarterly: return 91
        case .semiannual: return 182
        case .yearly: return 365
        case .custom: return 30
        }
    }

    /// Convert amount to monthly equivalent (cents). Rounds to nearest cent.
    func toMonthly(amount: Int) -> Int {
        switch self {
        case .weekly: return (amount * 52 + 6) / 12
        case .biweekly: return (amount * 26 + 6) / 12
        case .monthly: return amount
        case .quarterly: return (amount + 1) / 3
        case .semiannual: return (amount + 3) / 6
        case .yearly: return (amount + 6) / 12
        case .custom: return amount
        }
    }

    /// Convert amount to yearly equivalent (cents)
    func toYearly(amount: Int) -> Int {
        switch self {
        case .weekly: return amount * 52
        case .biweekly: return amount * 26
        case .monthly: return amount * 12
        case .quarterly: return amount * 4
        case .semiannual: return amount * 2
        case .yearly: return amount
        case .custom: return amount * 12
        }
    }
}

// MARK: - Subscription Source

/// Provenance of a subscription record. Lets the engine distinguish between
/// records that came out of detection, were typed in by the user, or were
/// promoted from a recurring transaction. Persistence and merge rules differ
/// per source.
enum SubscriptionSource: String, Codable, CaseIterable, Identifiable {
    case manual       // user-added via the sheet
    case detected     // confirmed from transaction-history detection
    case recurring    // promoted from a RecurringTransaction
    case imported     // CSV / reconciliation backfill

    var id: String { rawValue }
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
    /// Canonical, normalized matching key. Stable across detected/manual/
    /// recurring sources so the same merchant collapses to one record.
    /// Computed via `DetectedSubscription.merchantKey(for:)` at init time.
    var merchantKey: String
    var category: Category
    var expectedAmount: Int         // cents — average/typical charge
    var lastAmount: Int             // cents — most recent charge
    var billingCycle: BillingCycle
    /// Cadence in days for `.custom` billing cycles. Ignored otherwise.
    var customCadenceDays: Int?
    var nextRenewalDate: Date?
    var lastChargeDate: Date?
    var status: SubscriptionStatus
    /// Where this record came from. Phase 2 persistence + merge rules key
    /// off `source` so manual edits don't get clobbered by re-detection.
    var source: SubscriptionSource
    var linkedTransactionIds: [UUID]
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    // Trial tracking — provenance flag without forcing `status == .active`.
    var isTrial: Bool
    var trialEndsAt: Date?

    /// True once the user has explicitly chosen a status (cancel/pause/etc.)
    /// from the UI or AI. The merge step in `analyze()` will not overwrite
    /// `status` while this is set — re-detection can't undo a user decision.
    var userEditedStatus: Bool

    /// User has acknowledged "Maybe Unused" and said they're still using
    /// the service. Detection won't re-flag the record as
    /// `.suspectedUnused` while this is true. Cleared automatically the
    /// next time a fresh charge lands (handled in `applyDetectedUpdate`).
    var dismissedSuspectedUnused: Bool

    // Detection metadata
    var isAutoDetected: Bool
    var confidenceScore: Double     // 0.0–1.0 detection confidence
    var chargeHistory: [ChargeRecord]
    var detectedIntervalDays: Int   // actual median interval from detection (for next-renewal)
    /// Structured rationale for the confidence score. Nil for manual
    /// records (no detection ran) and for legacy records persisted before
    /// Phase 3.
    var detectionRationale: DetectionRationale?

    init(
        id: UUID = UUID(),
        merchantName: String,
        merchantKey: String? = nil,
        category: Category = .bills,
        expectedAmount: Int,
        lastAmount: Int = 0,
        billingCycle: BillingCycle = .monthly,
        customCadenceDays: Int? = nil,
        nextRenewalDate: Date? = nil,
        lastChargeDate: Date? = nil,
        status: SubscriptionStatus = .active,
        source: SubscriptionSource = .detected,
        linkedTransactionIds: [UUID] = [],
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isTrial: Bool = false,
        trialEndsAt: Date? = nil,
        userEditedStatus: Bool = false,
        dismissedSuspectedUnused: Bool = false,
        isAutoDetected: Bool = true,
        confidenceScore: Double = 0.0,
        chargeHistory: [ChargeRecord] = [],
        detectedIntervalDays: Int = 0,
        detectionRationale: DetectionRationale? = nil
    ) {
        self.id = id
        self.merchantName = merchantName
        self.merchantKey = merchantKey ?? Self.merchantKey(for: merchantName)
        self.category = category
        self.expectedAmount = expectedAmount
        self.lastAmount = lastAmount > 0 ? lastAmount : expectedAmount
        self.billingCycle = billingCycle
        self.customCadenceDays = customCadenceDays
        self.nextRenewalDate = nextRenewalDate
        self.lastChargeDate = lastChargeDate
        self.status = status
        self.source = source
        self.linkedTransactionIds = linkedTransactionIds
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isTrial = isTrial
        self.trialEndsAt = trialEndsAt
        self.userEditedStatus = userEditedStatus
        self.dismissedSuspectedUnused = dismissedSuspectedUnused
        self.isAutoDetected = isAutoDetected
        self.confidenceScore = confidenceScore
        self.chargeHistory = chargeHistory
        self.detectedIntervalDays = detectedIntervalDays > 0 ? detectedIntervalDays : billingCycle.approximateDays
        self.detectionRationale = detectionRationale
    }

    // MARK: - Codable

    /// Custom decode tolerates records persisted before `merchantKey`,
    /// `source`, `customCadenceDays`, `isTrial`, `trialEndsAt` were added.
    private enum CodingKeys: String, CodingKey {
        case id, merchantName, merchantKey, category, expectedAmount, lastAmount
        case billingCycle, customCadenceDays, nextRenewalDate, lastChargeDate
        case status, source, linkedTransactionIds, notes, createdAt, updatedAt
        case isTrial, trialEndsAt
        case userEditedStatus, dismissedSuspectedUnused
        case isAutoDetected, confidenceScore, chargeHistory, detectedIntervalDays
        case detectionRationale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let merchantName = try c.decode(String.self, forKey: .merchantName)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.merchantName = merchantName
        self.merchantKey = try c.decodeIfPresent(String.self, forKey: .merchantKey)
            ?? Self.merchantKey(for: merchantName)
        self.category = try c.decode(Category.self, forKey: .category)
        self.expectedAmount = try c.decode(Int.self, forKey: .expectedAmount)
        self.lastAmount = try c.decode(Int.self, forKey: .lastAmount)
        self.billingCycle = try c.decode(BillingCycle.self, forKey: .billingCycle)
        self.customCadenceDays = try c.decodeIfPresent(Int.self, forKey: .customCadenceDays)
        self.nextRenewalDate = try c.decodeIfPresent(Date.self, forKey: .nextRenewalDate)
        self.lastChargeDate = try c.decodeIfPresent(Date.self, forKey: .lastChargeDate)
        self.status = try c.decode(SubscriptionStatus.self, forKey: .status)
        let isAuto = try c.decodeIfPresent(Bool.self, forKey: .isAutoDetected) ?? true
        self.source = try c.decodeIfPresent(SubscriptionSource.self, forKey: .source)
            ?? (isAuto ? .detected : .manual)
        self.linkedTransactionIds = try c.decodeIfPresent([UUID].self, forKey: .linkedTransactionIds) ?? []
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        self.isTrial = try c.decodeIfPresent(Bool.self, forKey: .isTrial) ?? false
        self.trialEndsAt = try c.decodeIfPresent(Date.self, forKey: .trialEndsAt)
        self.userEditedStatus = try c.decodeIfPresent(Bool.self, forKey: .userEditedStatus) ?? false
        self.dismissedSuspectedUnused = try c.decodeIfPresent(Bool.self, forKey: .dismissedSuspectedUnused) ?? false
        self.isAutoDetected = isAuto
        self.confidenceScore = try c.decodeIfPresent(Double.self, forKey: .confidenceScore) ?? 0
        self.chargeHistory = try c.decodeIfPresent([ChargeRecord].self, forKey: .chargeHistory) ?? []
        self.detectedIntervalDays = try c.decodeIfPresent(Int.self, forKey: .detectedIntervalDays)
            ?? self.billingCycle.approximateDays
        self.detectionRationale = try c.decodeIfPresent(DetectionRationale.self, forKey: .detectionRationale)
    }

    // MARK: - Merchant key

    /// Canonical merchant key. Lowercased, punctuation stripped, whitespace
    /// collapsed. Matches `AISubscription.merchantKey(for:)` so records can
    /// migrate between the two models without rekeying.
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

    // MARK: - Computed

    /// Monthly cost equivalent in cents
    var monthlyCost: Int {
        billingCycle.toMonthly(amount: expectedAmount)
    }

    /// Yearly cost equivalent in cents
    var yearlyCost: Int {
        billingCycle.toYearly(amount: expectedAmount)
    }

    /// Effective cadence in days. For `.custom` it honors `customCadenceDays`,
    /// falling back to the billing-cycle default.
    var effectiveCadenceDays: Int {
        if billingCycle == .custom, let d = customCadenceDays, d > 0 { return d }
        return billingCycle.approximateDays
    }

    /// Days until next renewal (nil if unknown)
    var daysUntilRenewal: Int? {
        guard let next = nextRenewalDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: next).day
    }

    /// Whether a meaningful price change was detected. Phase 3 — compares
    /// the latest charge against the **median of prior charges** rather
    /// than the immediately-preceding one. Requires ≥3 charges so a
    /// single outlier (one weird month) doesn't trigger the alert.
    var hasPriceIncrease: Bool {
        guard let pct = priceChangePercent else { return false }
        return pct > 2.0
    }

    /// Signed price-change amount in cents (positive = went up).
    /// Computed against the prior-charges median; nil when there isn't
    /// enough history (<3 charges).
    var priceChangeAmount: Int? {
        guard let baseline = priorChargeMedian, let last = chargeHistory.sorted(by: { $0.date < $1.date }).last else {
            return nil
        }
        let diff = last.amount - baseline
        return diff != 0 ? diff : nil
    }

    /// Signed price-change percentage (e.g. 5.2 means +5.2%, -3.0 means
    /// −3.0%). Reported only if the absolute change is ≥0.5%.
    var priceChangePercent: Double? {
        guard let baseline = priorChargeMedian, baseline > 0,
              let last = chargeHistory.sorted(by: { $0.date < $1.date }).last else {
            return nil
        }
        let pct = Double(last.amount - baseline) / Double(baseline) * 100.0
        return abs(pct) >= 0.5 ? pct : nil
    }

    /// Median amount of all charges except the most recent one. The
    /// baseline used for price-change detection. Nil when there aren't
    /// enough prior charges to form a stable median.
    private var priorChargeMedian: Int? {
        guard chargeHistory.count >= 3 else { return nil }
        let sorted = chargeHistory.sorted { $0.date < $1.date }
        let prior = sorted.dropLast().map(\.amount).sorted()
        guard !prior.isEmpty else { return nil }
        let n = prior.count
        return n % 2 == 0 ? (prior[n/2 - 1] + prior[n/2]) / 2 : prior[n/2]
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

// MARK: - Detection Rationale

/// Structured "why does the engine think this is a subscription"
/// breakdown. Populated by `SubscriptionEngine.detect()` and stored
/// on the record so the detail view can render it without re-running
/// detection. All scores are 0.0–1.0; the four components add up to
/// `confidenceScore` using the same weights the engine uses internally.
struct DetectionRationale: Codable, Hashable {
    /// Share of intervals within ±30% of the median (0.4 weight).
    var regularityRatio: Double
    /// Share of charge amounts within ±15% of the median (0.3 weight).
    var amountSimilarity: Double
    /// `min(1, count / 6)` — six charges saturate this score (0.2 weight).
    var occurrenceScore: Double
    /// 1.0 if the cycle matched a known cadence (weekly / monthly /
    /// yearly), 0.0 for `.custom` (0.1 weight).
    var knownCycle: Double
    /// Median interval in days, kept here for the rationale string
    /// ("charges every ~30 days").
    var medianIntervalDays: Int
    /// Number of charges considered.
    var sampleCount: Int
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
