import Foundation
import Supabase
import Combine

// MARK: - Net Worth Manager

@MainActor
class NetWorthManager: ObservableObject {
    
    static let shared = NetWorthManager()
    
    @Published var summary: NetWorthSummary = .empty
    @Published var historyDataPoints: [NetWorthDataPoint] = []
    @Published var isLoading = false
    
    private var client: SupabaseClient { SupabaseManager.shared.client }
    private let accountManager = AccountManager.shared
    
    private init() {}
    
    // MARK: - Compute Current Summary
    
    func computeSummary() async {
        isLoading = true

        // Fetch fresh account data before computing to avoid stale balances
        await accountManager.fetchAccounts()

        let totalAssets = accountManager.totalAssets
        let totalLiabilities = accountManager.totalLiabilities
        let currentNetWorth = totalAssets - totalLiabilities
        
        let lastMonthNetWorth = await fetchLastMonthNetWorth()
        
        let change = currentNetWorth - lastMonthNetWorth
        let percentage: Double = lastMonthNetWorth != 0
            ? (change / abs(lastMonthNetWorth)) * 100
            : 0
        
        summary = NetWorthSummary(
            totalAssets: totalAssets,
            totalLiabilities: totalLiabilities,
            netWorth: currentNetWorth,
            changeFromLastMonth: change,
            changePercentage: percentage
        )
        
        isLoading = false
    }
    
    // MARK: - Fetch History for Charts
    
    func fetchHistory(months: Int = 12) async {
        isLoading = true
        
        let calendar = Calendar.current
        let now = Date()
        guard let startDate = calendar.date(byAdding: .month, value: -months, to: now) else {
            isLoading = false
            return
        }
        
        let isoFormatter = ISO8601DateFormatter()
        
        do {
            let snapshots: [AccountBalanceSnapshot] = try await client
                .from("account_balance_snapshots")
                .select()
                .gte("snapshot_date", value: isoFormatter.string(from: startDate))
                .order("snapshot_date", ascending: true)
                .execute()
                .value
            
            // Get all accounts to classify asset vs liability
            let allAccounts = await accountManager.fetchAllAccounts()
            let typeMap = Dictionary(uniqueKeysWithValues: allAccounts.map { ($0.id, $0.type) })
            
            // Group by month, keep latest snapshot per account per month
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "yyyy-MM"
            
            // key: "yyyy-MM", value: [accountId: balance]
            var monthlyBalances: [String: [UUID: Double]] = [:]
            
            for snapshot in snapshots {
                let monthKey = monthFormatter.string(from: snapshot.snapshotDate)
                var balances = monthlyBalances[monthKey] ?? [:]
                balances[snapshot.accountId] = snapshot.balance // latest wins (ordered asc)
                monthlyBalances[monthKey] = balances
            }
            
            // Convert to data points
            historyDataPoints = monthlyBalances
                .compactMap { key, balances -> NetWorthDataPoint? in
                    guard let date = monthFormatter.date(from: key) else { return nil }
                    
                    var assets: Double = 0
                    var liabilities: Double = 0
                    
                    for (accountId, balance) in balances {
                        if typeMap[accountId]?.isAsset == true {
                            assets += balance
                        } else {
                            liabilities += abs(balance)
                        }
                    }
                    
                    return NetWorthDataPoint(
                        date: date,
                        totalAssets: assets,
                        totalLiabilities: liabilities
                    )
                }
                .sorted { $0.date < $1.date }
            
            SecureLogger.info("Net worth history: \(historyDataPoints.count) data points")

        } catch {
            SecureLogger.error("Failed to fetch net worth history", error)
        }
        
        isLoading = false
    }
    
    // MARK: - Last Month Net Worth
    
    private func fetchLastMonthNetWorth() async -> Double {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        guard let thisMonthStart = calendar.date(from: comps),
              let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) else {
            return 0
        }
        
        let isoFormatter = ISO8601DateFormatter()
        
        do {
            let snapshots: [AccountBalanceSnapshot] = try await client
                .from("account_balance_snapshots")
                .select()
                .gte("snapshot_date", value: isoFormatter.string(from: lastMonthStart))
                .lt("snapshot_date", value: isoFormatter.string(from: thisMonthStart))
                .order("snapshot_date", ascending: false)
                .execute()
                .value
            
            let allAccounts = await accountManager.fetchAllAccounts()
            let typeMap = Dictionary(uniqueKeysWithValues: allAccounts.map { ($0.id, $0.type) })
            
            // Latest snapshot per account from last month
            var latestPerAccount: [UUID: Double] = [:]
            for snapshot in snapshots {
                if latestPerAccount[snapshot.accountId] == nil {
                    latestPerAccount[snapshot.accountId] = snapshot.balance
                }
            }
            
            var total: Double = 0
            for (accountId, balance) in latestPerAccount {
                if typeMap[accountId]?.isAsset == true {
                    total += balance
                } else {
                    total -= abs(balance)
                }
            }
            
            return total
        } catch {
            return 0
        }
    }
}
