import Foundation
import Combine

// ============================================================
// MARK: - Currency Converter
// ============================================================
//
// Converts amounts between currencies using cached exchange rates.
// Rates are fetched from a free API and cached in UserDefaults
// for 24 hours. Falls back to bundled offline rates if fetch fails.
//
// Usage:
//   let euros = CurrencyConverter.shared.convert(100, from: "USD", to: "EUR")
//   let text  = CurrencyConverter.shared.convertedText(5000, from: "USD")
//
// ============================================================

@MainActor
class CurrencyConverter: ObservableObject {

    static let shared = CurrencyConverter()

    @Published var rates: [String: Double] = [:]
    @Published var lastUpdated: Date?
    @Published var isLoading = false

    /// The app-wide base currency
    var appCurrency: String {
        UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"
    }

    private let cacheKey = "cached_exchange_rates"
    private let cacheTimestampKey = "cached_exchange_rates_timestamp"
    private let cacheMaxAge: TimeInterval = 24 * 60 * 60 // 24 hours

    private init() {
        loadCachedRates()
        if rates.isEmpty {
            loadOfflineRates()
        }
    }

    // ============================================================
    // MARK: - Conversion
    // ============================================================

    /// Convert an amount from one currency to another.
    /// Returns nil if conversion is not possible (unknown currency).
    func convert(_ amount: Double, from: String, to: String) -> Double? {
        if from == to { return amount }

        // Rates are stored as: 1 USD = X (other currency)
        // We need to find a path: from → USD → to
        // OR use cross-rate through any base

        guard let fromRate = rate(for: from),
              let toRate = rate(for: to) else { return nil }

        // amount in USD = amount / fromRate
        // amount in target = (amount / fromRate) * toRate
        let amountInUSD = amount / fromRate
        return amountInUSD * toRate
    }

    /// Convert to the app's default currency.
    func convertToAppCurrency(_ amount: Double, from: String) -> Double? {
        convert(amount, from: from, to: appCurrency)
    }

    /// Returns a short display string like "≈ €4,350" for converted amounts.
    /// Returns nil if conversion not needed (same currency) or not possible.
    func convertedDisplayText(_ amount: Double, from: String) -> String? {
        guard from != appCurrency else { return nil }
        guard let converted = convertToAppCurrency(amount, from: from) else { return nil }

        let symbol = CurrencyFormatter.currentSymbol
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true

        guard let formatted = formatter.string(from: NSNumber(value: converted)) else { return nil }
        return "≈ \(symbol)\(formatted)"
    }

    /// Get rate for a currency relative to USD (1 USD = X units).
    func rate(for currency: String) -> Double? {
        if currency == "USD" { return 1.0 }
        return rates[currency]
    }

    /// Whether we can convert from the given currency
    func canConvert(from currency: String) -> Bool {
        currency == "USD" || rates[currency] != nil
    }

    // ============================================================
    // MARK: - Fetch Rates
    // ============================================================

    /// Fetch latest rates from API. Call on app launch.
    func fetchRatesIfNeeded() async {
        // Skip if we have fresh rates
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < cacheMaxAge, !rates.isEmpty {
            return
        }
        await fetchRates()
    }

    func fetchRates() async {
        isLoading = true
        defer { isLoading = false }

        // Use exchangerate-api.com free tier (no API key needed for latest USD base)
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ExchangeRateResponse.self, from: data)

            if response.result == "success", let fetchedRates = response.rates {
                self.rates = fetchedRates
                self.lastUpdated = Date()
                cacheRates(fetchedRates)
                SecureLogger.info("Exchange rates updated: \(fetchedRates.count) currencies")
            }
        } catch {
            SecureLogger.warning("Failed to fetch exchange rates: \(error.localizedDescription)")
            // Keep using cached/offline rates
        }
    }

    // ============================================================
    // MARK: - Cache
    // ============================================================

    private func cacheRates(_ rates: [String: Double]) {
        if let data = try? JSONEncoder().encode(rates) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
        }
    }

    private func loadCachedRates() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([String: Double].self, from: data) else { return }

        let timestamp = UserDefaults.standard.double(forKey: cacheTimestampKey)
        let cacheDate = Date(timeIntervalSince1970: timestamp)

        self.rates = cached
        self.lastUpdated = cacheDate
    }

    // ============================================================
    // MARK: - Offline Fallback Rates (approx. March 2026)
    // ============================================================

    private func loadOfflineRates() {
        rates = [
            "EUR": 0.92,
            "GBP": 0.79,
            "JPY": 149.5,
            "CNY": 7.24,
            "IRR": 42000.0,
            "AED": 3.67,
            "SAR": 3.75,
            "TRY": 38.5,
            "CAD": 1.36,
            "AUD": 1.55,
            "CHF": 0.88,
            "SEK": 10.4,
            "NOK": 10.6,
            "DKK": 6.88,
            "PLN": 3.97,
            "CZK": 23.2,
            "HUF": 370.0,
            "INR": 83.5,
            "BRL": 4.95,
            "MXN": 17.1,
            "KRW": 1340.0,
            "SGD": 1.34,
            "HKD": 7.82,
            "NZD": 1.67,
            "ZAR": 18.7,
        ]
        lastUpdated = nil // Mark as offline
    }
}

// MARK: - API Response Model

private struct ExchangeRateResponse: Decodable {
    let result: String?
    let rates: [String: Double]?
}
