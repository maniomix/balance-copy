import Foundation
import Combine
import Supabase

// ============================================================
// MARK: - MembershipManager (Phase 5.6.5)
// ============================================================
// Gates the app's own paid plan ("Centmond Membership"). Distinct
// from the user-tracked services feature in SubscriptionEngine /
// subscription_state.
//
// Tiers: free → pro_trial (30 days) → pro
//
// StoreKit is the source of truth once the Apple Developer account
// is set up. These cloud columns on `profiles` are just a cache so
// other devices know the tier without re-querying Apple.
//
// Until StoreKit is wired up, `isPro` returns true for everyone —
// the paywall is intentionally disabled for the rebuild.
// ============================================================

@MainActor
final class MembershipManager: ObservableObject {

    static let shared = MembershipManager()

    // MARK: - Tier

    enum Tier: String, Codable {
        case free
        case proTrial = "pro_trial"
        case pro

        var isPro: Bool { self == .pro || self == .proTrial }
        var displayName: String {
            switch self {
            case .free:     return "Free"
            case .proTrial: return "Pro (Trial)"
            case .pro:      return "Pro"
            }
        }
    }

    // MARK: - Published state

    @Published var tier: Tier = .free
    @Published var trialEndsAt: Date?
    @Published var proPeriodEnd: Date?
    @Published var isLoading: Bool = false

    // MARK: - Limits

    static let freeTransactionLimit: Int = 50
    static let trialDurationDays: Int = 30

    // MARK: - Computed

    /// **Paywall intentionally disabled** until StoreKit is integrated post
    /// Apple Developer account. Treat every user as Pro for now.
    /// Flip this to `tier.isPro` once the StoreKit listener is in place.
    var isPro: Bool { true }

    /// Days remaining in the current trial. 0 if not on trial.
    var trialDaysRemaining: Int {
        guard tier == .proTrial, let end = trialEndsAt else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0)
    }

    /// Free-tier transaction count check. Always allowed while paywall is off.
    func canAddTransaction(currentCount: Int) -> Bool {
        if isPro { return true }
        return currentCount < Self.freeTransactionLimit
    }

    func remainingFreeTransactions(currentCount: Int) -> Int {
        if isPro { return .max }
        return max(0, Self.freeTransactionLimit - currentCount)
    }

    // MARK: - Profile DTO (just the membership-related columns)

    private struct ProfileMembershipRow: Codable {
        let membership_tier: String
        let trial_started_at: String?
        let trial_ends_at: String?
        let pro_period_end: String?
        let pro_platform: String?
    }

    // MARK: - Load (cloud → state)

    func load() async {
        guard AuthManager.shared.currentUser != nil else {
            tier = .free; trialEndsAt = nil; proPeriodEnd = nil
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let rows: [ProfileMembershipRow] = try await SupabaseManager.shared.client
                .from("profiles")
                .select("membership_tier, trial_started_at, trial_ends_at, pro_period_end, pro_platform")
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else {
                tier = .free; return
            }
            tier = Tier(rawValue: row.membership_tier) ?? .free
            trialEndsAt = parseDate(row.trial_ends_at)
            proPeriodEnd = parseDate(row.pro_period_end)

            // Auto-expire stale trial / pro periods so the UI doesn't keep
            // showing "Pro (Trial)" past the end date.
            if tier == .proTrial, let end = trialEndsAt, Date() >= end {
                await downgrade(to: .free)
            } else if tier == .pro, let end = proPeriodEnd, Date() >= end {
                await downgrade(to: .free)
            }
            SecureLogger.info("Membership loaded: \(tier.displayName)")
        } catch {
            SecureLogger.warning("Membership load failed; falling back to free")
            tier = .free
        }
    }

    // MARK: - Trial / upgrade / downgrade
    //
    // These are placeholder hooks for the StoreKit integration. They write
    // through to `profiles` so other devices stay in sync. Apple's StoreKit
    // listener will call `applyAppleEntitlement(...)` once we wire up the
    // real purchase flow.

    func startFreeTrial() async {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: Self.trialDurationDays, to: now) ?? now
        await patchProfile(tier: .proTrial, trialStart: now, trialEnd: end, periodEnd: nil, platform: "apple")
    }

    func applyAppleEntitlement(periodEnd: Date) async {
        await patchProfile(tier: .pro, trialStart: nil, trialEnd: nil, periodEnd: periodEnd, platform: "apple")
    }

    func downgrade(to newTier: Tier) async {
        await patchProfile(tier: newTier, trialStart: nil, trialEnd: nil, periodEnd: nil, platform: nil)
    }

    // MARK: - Internals

    private func patchProfile(tier: Tier, trialStart: Date?, trialEnd: Date?, periodEnd: Date?, platform: String?) async {
        struct Patch: Encodable {
            let membership_tier: String
            let trial_started_at: String?
            let trial_ends_at: String?
            let pro_period_end: String?
            let pro_platform: String?
        }
        let iso = ISO8601DateFormatter()
        let patch = Patch(
            membership_tier: tier.rawValue,
            trial_started_at: trialStart.map(iso.string(from:)),
            trial_ends_at: trialEnd.map(iso.string(from:)),
            pro_period_end: periodEnd.map(iso.string(from:)),
            pro_platform: platform
        )
        do {
            guard let userId = AuthManager.shared.currentUser?.id.uuidString else { return }
            try await SupabaseManager.shared.client
                .from("profiles")
                .update(patch)
                .eq("id", value: userId)
                .execute()
            self.tier = tier
            self.trialEndsAt = trialEnd
            self.proPeriodEnd = periodEnd
            SecureLogger.info("Membership patched: \(tier.displayName)")
        } catch {
            SecureLogger.error("Membership patch failed", error)
        }
    }

    private func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
