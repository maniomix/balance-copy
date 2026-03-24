import Foundation

// ============================================================
// MARK: - Widget Shared Data
// ============================================================
//
// Lightweight Codable struct that the main app writes to
// the App Group container, and widgets read from it.
//
// This file must be included in BOTH targets:
//   - balance (main app)
//   - CentmondWidgetExtension (widget)
//
// App Group: group.com.centmond.balance
// ============================================================

struct WidgetSharedData: Codable {
    // Budget
    let budgetTotal: Int            // cents
    let spentThisMonth: Int         // cents
    let remainingBudget: Int        // cents
    let spentToday: Int             // cents
    let dailyAverage: Int           // cents
    let daysRemainingInMonth: Int
    let dayOfMonth: Int
    let daysInMonth: Int

    // Safe to spend
    let safeToSpendTotal: Int       // cents
    let safeToSpendPerDay: Int      // cents
    let reservedForBills: Int       // cents
    let reservedForGoals: Int       // cents

    // Upcoming bills
    let upcomingBills: [WidgetBill]

    // Net worth
    let netWorth: Int               // cents
    let accountCount: Int
    let totalAssets: Int            // cents
    let totalLiabilities: Int       // cents

    // Risk
    let riskLevel: String           // "safe", "caution", "highRisk"

    // Income
    let incomeThisMonth: Int        // cents

    // Meta
    let currencySymbol: String
    let lastUpdated: Date

    // MARK: - Computed Helpers

    /// Data has never been written by the app
    var isEmpty: Bool {
        budgetTotal == 0 && spentThisMonth == 0 && spentToday == 0
            && netWorth == 0 && accountCount == 0 && dayOfMonth == 0
    }

    /// Data is older than 6 hours — likely stale
    var isStale: Bool {
        Date().timeIntervalSince(lastUpdated) > 6 * 3600
    }

    /// Budget ratio (0…∞)
    var budgetUsedRatio: Double {
        budgetTotal > 0 ? Double(spentThisMonth) / Double(budgetTotal) : 0
    }

    // MARK: - Empty State

    static let empty = WidgetSharedData(
        budgetTotal: 0, spentThisMonth: 0, remainingBudget: 0,
        spentToday: 0, dailyAverage: 0, daysRemainingInMonth: 0,
        dayOfMonth: 0, daysInMonth: 30,
        safeToSpendTotal: 0, safeToSpendPerDay: 0,
        reservedForBills: 0, reservedForGoals: 0,
        upcomingBills: [],
        netWorth: 0, accountCount: 0, totalAssets: 0, totalLiabilities: 0,
        riskLevel: "safe", incomeThisMonth: 0,
        currencySymbol: "€", lastUpdated: Date.distantPast
    )

    // MARK: - Sample Data (for widget gallery preview)

    static let sample = WidgetSharedData(
        budgetTotal: 250000, spentThisMonth: 148750, remainingBudget: 101250,
        spentToday: 3490, dailyAverage: 8625, daysRemainingInMonth: 13,
        dayOfMonth: 17, daysInMonth: 30,
        safeToSpendTotal: 78400, safeToSpendPerDay: 6030,
        reservedForBills: 15200, reservedForGoals: 7650,
        upcomingBills: [
            WidgetBill(name: "Netflix", amount: 1599,
                       dueDateTimestamp: Date().addingTimeInterval(3 * 86400).timeIntervalSince1970,
                       categoryName: "Entertainment"),
            WidgetBill(name: "Gym", amount: 2990,
                       dueDateTimestamp: Date().addingTimeInterval(7 * 86400).timeIntervalSince1970,
                       categoryName: "Health"),
            WidgetBill(name: "Phone", amount: 3500,
                       dueDateTimestamp: Date().addingTimeInterval(12 * 86400).timeIntervalSince1970,
                       categoryName: "Utilities"),
        ],
        netWorth: 3245000, accountCount: 3, totalAssets: 4150000, totalLiabilities: 905000,
        riskLevel: "safe", incomeThisMonth: 420000,
        currencySymbol: "€", lastUpdated: Date()
    )
}

struct WidgetBill: Codable, Identifiable {
    var id: String { name + "\(dueDateTimestamp)" }
    let name: String
    let amount: Int                 // cents
    let dueDateTimestamp: TimeInterval
    let categoryName: String

    var dueDate: Date { Date(timeIntervalSince1970: dueDateTimestamp) }
}

// MARK: - Read / Write Helpers

enum WidgetDataBridge {
    static let appGroupID = "group.com.centmond.balance"
    static let dataKey = "widget_shared_data"

    /// Write data to App Group (call from main app)
    static func write(_ data: WidgetSharedData) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let encoded = try? encoder.encode(data) {
            defaults.set(encoded, forKey: dataKey)
        }
    }

    /// Read data from App Group (call from widget)
    static func read() -> WidgetSharedData {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: dataKey) else {
            return .empty
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetSharedData.self, from: data)) ?? .empty
    }
}
