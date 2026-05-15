import SwiftUI

// Shared chrome for the Budget Live Activity — colors, formatters, page
// metadata, deep links. Internal access so every file under LiveActivity/
// can pull from one source.

func barColor(for state: BudgetActivityAttributes.ContentState) -> Color {
    if state.isOverBudget { return .red }
    if state.percentSpent >= 0.85 { return .orange }
    return Color(red: 0.30, green: 0.85, blue: 0.55)
}

/// Cached locale-aware formatter for amounts. Uses current locale for
/// thousands / decimal separators (de-DE → `1.000,00`, en-US → `1,000.00`).
/// Symbol is appended separately so the wire-format `currencySymbol` from
/// `BudgetActivityAttributes` stays the source of truth — keeps DI labels
/// in sync with the app's currency setting without re-reading UserDefaults
/// inside the widget extension.
private let amountFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = .current
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    f.usesGroupingSeparator = true
    return f
}()

private let amountFormatterNoDecimals: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = .current
    f.minimumFractionDigits = 0
    f.maximumFractionDigits = 0
    f.usesGroupingSeparator = true
    return f
}()

/// Compact form for tight spots (compact-trailing, minimal): no decimals,
/// grouped thousands, symbol suffix. e.g. `1.234 €`.
func formatAmount(_ cents: Int, symbol: String) -> String {
    let value = Decimal(cents) / 100
    let body = amountFormatterNoDecimals.string(from: value as NSDecimalNumber) ?? "\(cents / 100)"
    return "\(body) \(symbol)"
}

/// Full form for expanded regions: grouped thousands + two decimals.
/// e.g. `1.234,56 €`.
func formatAmountDecimal(_ cents: Int, symbol: String) -> String {
    let value = Decimal(cents) / 100
    let body = amountFormatter.string(from: value as NSDecimalNumber) ?? String(format: "%.2f", Double(cents) / 100)
    return "\(body) \(symbol)"
}

/// Ultra-compact form for the collapsed Dynamic Island (left of the sensor
/// cutout). Reduces "6000 €" → "6K €", "12345 €" → "12K €", "1234567 €" →
/// "1.2M €". Keeps the symbol suffix.
///
/// Thresholds:
///  - < 1_000        →  "823"          (no suffix)
///  - 1_000–9_999    →  "6.2K" / "6K"  (one decimal when < 10K)
///  - 10_000–999_999 →  "12K"          (rounded)
///  - 1_000_000+     →  "1.2M"
func formatAmountShort(_ cents: Int, symbol: String) -> String {
    let units = abs(cents) / 100               // whole-unit value
    let sign = cents < 0 ? "-" : ""
    let body: String
    switch units {
    case 0..<1_000:
        body = "\(units)"
    case 1_000..<10_000:
        let v = Double(units) / 1_000.0
        // Drop the trailing .0 — "6.0K" reads worse than "6K".
        body = v.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(v))K"
            : String(format: "%.1fK", v)
    case 10_000..<1_000_000:
        body = "\(units / 1_000)K"
    default:
        let v = Double(units) / 1_000_000.0
        body = v.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(v))M"
            : String(format: "%.1fM", v)
    }
    return "\(sign)\(body) \(symbol)"
}

struct PageMeta {
    let title: String
    let icon: String
}

let pageMetas: [PageMeta] = [
    .init(title: "BUDGET",       icon: "chart.pie.fill"),
    .init(title: "TODAY",        icon: "sun.max.fill"),
    .init(title: "THIS WEEK",    icon: "calendar"),
    .init(title: "TOP CATEGORY", icon: "trophy.fill"),
    .init(title: "GOAL",         icon: "flag.fill"),
]

/// Per-page deep-link target. Tapping the activity (compact or expanded
/// regions outside the Next button / dots) opens Centmond at the most
/// relevant tab for what the user was just looking at.
func deepLinkURL(forPage pageIndex: Int) -> URL? {
    let host: String
    switch pageIndex {
    case 1: host = "transactions"
    case 2: host = "insights"
    case 3: host = "insights"
    case 4: host = "goals"
    default: host = "budget"
    }
    return URL(string: "centmond://\(host)")
}
