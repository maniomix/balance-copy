import Foundation
import Combine
import Supabase

// MARK: - Subscription Manager
// Simple feature gating — checks Supabase for subscription status
// No paywall UI, no purchase flow — just lock/unlock logic

@MainActor
final class SubscriptionManager: ObservableObject {
    
    static let shared = SubscriptionManager()
    
    // MARK: - Published State
    @Published var status: SubscriptionStatus = .free
    @Published var trialDaysRemaining: Int = 0
    @Published var isLoading: Bool = false
    @Published var currentPlan: String = "free"           // free, monthly, yearly
    @Published var currentPeriodEnd: Date? = nil           // تاریخ انقضای دوره فعلی
    @Published var trialEndDate: Date? = nil               // تاریخ پایان تریال
    
    // MARK: - Limits
    static let freeTransactionLimit: Int = 50
    
    // MARK: - Computed
    
    /// Paywall gates removed — every user is treated as Pro.
    /// Keeping the computed var and `status` enum so the ProfileView / Settings
    /// plan-status card keeps rendering without further refactor; it just
    /// always reports Pro.
    var isPro: Bool { true }
    
    /// Check if free user can still add transactions
    func canAddTransaction(currentCount: Int) -> Bool {
        if isPro { return true }
        return currentCount < Self.freeTransactionLimit
    }
    
    /// How many free transactions remain
    func remainingFreeTransactions(currentCount: Int) -> Int {
        if isPro { return .max }
        return max(0, Self.freeTransactionLimit - currentCount)
    }
    
    // MARK: - Status Enum
    
    enum SubscriptionStatus: String, Codable {
        case free
        case trial
        case active
        case expired
        case canceled
    }
    
    // MARK: - Supabase Model
    
    struct Subscription: Codable {
        let id: String?
        let userId: String
        var status: String
        var plan: String
        var platform: String?
        var trialStart: String?
        var trialEnd: String?
        var currentPeriodStart: String?
        var currentPeriodEnd: String?
        var createdAt: String?
        var updatedAt: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case userId = "user_id"
            case status, plan, platform
            case trialStart = "trial_start"
            case trialEnd = "trial_end"
            case currentPeriodStart = "current_period_start"
            case currentPeriodEnd = "current_period_end"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }
    
    // MARK: - Load from Supabase
    
    func loadSubscription() async {
        guard let userId = AuthManager.shared.currentUser?.uid else {
            status = .free
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let response: [Subscription] = try await SupabaseManager.shared.client
                .from("subscriptions")
                .select()
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            
            guard let sub = response.first else {
                status = .free
                currentPlan = "free"
                currentPeriodEnd = nil
                trialEndDate = nil
                saveToLocal()
                return
            }
            
            // Store plan
            currentPlan = sub.plan
            
            let parsed = SubscriptionStatus(rawValue: sub.status) ?? .free
            
            switch parsed {
            case .trial:
                if let trialEnd = parseDate(sub.trialEnd), Date() < trialEnd {
                    status = .trial
                    trialDaysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
                    trialEndDate = trialEnd
                } else {
                    status = .expired
                    trialDaysRemaining = 0
                    trialEndDate = nil
                    try? await updateStatus(userId: userId, to: "expired")
                }
                
            case .active:
                if let periodEnd = parseDate(sub.currentPeriodEnd), Date() >= periodEnd {
                    status = .expired
                    currentPeriodEnd = nil
                    try? await updateStatus(userId: userId, to: "expired")
                } else {
                    status = .active
                    currentPeriodEnd = parseDate(sub.currentPeriodEnd)
                }
                
            default:
                status = parsed
            }
            
            saveToLocal()
            SecureLogger.info("Subscription: \(status.rawValue)")

        } catch {
            SecureLogger.error("Subscription load failed", error)
            loadFromLocal()
        }
    }
    
    // MARK: - Update Status
    
    private func updateStatus(userId: String, to newStatus: String) async throws {
        try await SupabaseManager.shared.client
            .from("subscriptions")
            .update(["status": newStatus, "updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("user_id", value: userId)
            .execute()
    }
    
    // MARK: - Local Cache (offline fallback)
    
    private func saveToLocal() {
        UserDefaults.standard.set(status.rawValue, forKey: "sub.status")
        UserDefaults.standard.set(trialDaysRemaining, forKey: "sub.trialDays")
    }
    
    private func loadFromLocal() {
        if let s = UserDefaults.standard.string(forKey: "sub.status"),
           let parsed = SubscriptionStatus(rawValue: s) {
            status = parsed
        }
        trialDaysRemaining = UserDefaults.standard.integer(forKey: "sub.trialDays")
    }
    
    // MARK: - Helpers
    
    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }
}
