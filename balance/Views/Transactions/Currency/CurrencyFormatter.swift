import Foundation
import SwiftUI

// MARK: - Currency Formatter
struct CurrencyFormatter {
    
    /// کارنسی که کاربر توی app انتخاب کرده
    static var selectedCurrency: String {
        UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"
    }
    
    /// تنظیم کارنسی جدید
    static func setCurrency(_ currency: String) {
        UserDefaults.standard.set(currency, forKey: "app.currency")
    }
    
    /// لیست کارنسی‌های پشتیبانی شده
    enum SupportedCurrency: String, CaseIterable {
        case EUR = "EUR"  // Euro - €
        case USD = "USD"  // US Dollar - $
        case GBP = "GBP"  // British Pound - £
        case JPY = "JPY"  // Japanese Yen - ¥
        case CNY = "CNY"  // Chinese Yuan - ¥
        case IRR = "IRR"  // Iranian Rial - ﷼
        case AED = "AED"  // UAE Dirham - د.إ
        case SAR = "SAR"  // Saudi Riyal - ﷼
        case TRY = "TRY"  // Turkish Lira - ₺
        case CAD = "CAD"  // Canadian Dollar - $
        case AUD = "AUD"  // Australian Dollar - $
        case CHF = "CHF"  // Swiss Franc - CHF
        case INR = "INR"  // Indian Rupee - ₹
        case KRW = "KRW"  // South Korean Won - ₩
        case SEK = "SEK"  // Swedish Krona - kr
        case NOK = "NOK"  // Norwegian Krone - kr
        case DKK = "DKK"  // Danish Krone - kr
        case NZD = "NZD"  // New Zealand Dollar - $
        case SGD = "SGD"  // Singapore Dollar - $
        case HKD = "HKD"  // Hong Kong Dollar - $
        case MXN = "MXN"  // Mexican Peso - $
        case BRL = "BRL"  // Brazilian Real - R$
        case ZAR = "ZAR"  // South African Rand - R
        case RUB = "RUB"  // Russian Ruble - ₽
        case PLN = "PLN"  // Polish Złoty - zł

        var symbol: String {
            switch self {
            case .EUR: return "€"
            case .USD: return "$"
            case .GBP: return "£"
            case .JPY: return "¥"
            case .CNY: return "¥"
            case .IRR: return "﷼"
            case .AED: return "د.إ"
            case .SAR: return "﷼"
            case .TRY: return "₺"
            case .CAD: return "$"
            case .AUD: return "$"
            case .CHF: return "CHF"
            case .INR: return "₹"
            case .KRW: return "₩"
            case .SEK: return "kr"
            case .NOK: return "kr"
            case .DKK: return "kr"
            case .NZD: return "$"
            case .SGD: return "$"
            case .HKD: return "$"
            case .MXN: return "$"
            case .BRL: return "R$"
            case .ZAR: return "R"
            case .RUB: return "₽"
            case .PLN: return "zł"
            }
        }

        var name: String {
            switch self {
            case .EUR: return "Euro"
            case .USD: return "US Dollar"
            case .GBP: return "British Pound"
            case .JPY: return "Japanese Yen"
            case .CNY: return "Chinese Yuan"
            case .IRR: return "Iranian Rial"
            case .AED: return "UAE Dirham"
            case .SAR: return "Saudi Riyal"
            case .TRY: return "Turkish Lira"
            case .CAD: return "Canadian Dollar"
            case .AUD: return "Australian Dollar"
            case .CHF: return "Swiss Franc"
            case .INR: return "Indian Rupee"
            case .KRW: return "South Korean Won"
            case .SEK: return "Swedish Krona"
            case .NOK: return "Norwegian Krone"
            case .DKK: return "Danish Krone"
            case .NZD: return "New Zealand Dollar"
            case .SGD: return "Singapore Dollar"
            case .HKD: return "Hong Kong Dollar"
            case .MXN: return "Mexican Peso"
            case .BRL: return "Brazilian Real"
            case .ZAR: return "South African Rand"
            case .RUB: return "Russian Ruble"
            case .PLN: return "Polish Złoty"
            }
        }
    }
    
    /// فرمت کردن عدد به string با کارنسی
    /// - Parameters:
    ///   - amount: مبلغ (مثل 500.00)
    ///   - showSymbol: نشون بده symbol یا نه (default: true)
    ///   - showDecimal: نشون بده decimal یا نه (default: true)
    /// - Returns: "€ 500,00" یا "500,00 €"
    static func format(
        _ amount: Double,
        showSymbol: Bool = true,
        showDecimal: Bool = true
    ) -> String {
        let currency = SupportedCurrency(rawValue: selectedCurrency) ?? .EUR
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = showDecimal ? 2 : 0
        formatter.maximumFractionDigits = showDecimal ? 2 : 0
        formatter.groupingSeparator = "."  // نقطه برای هزارگان: 1.000
        formatter.decimalSeparator = ","   // کاما برای اعشار: 0,50
        formatter.usesGroupingSeparator = true
        
        let formattedNumber = formatter.string(from: NSNumber(value: amount)) ?? "0,00"
        
        if !showSymbol {
            return formattedNumber
        }
        
        // برای بعضی کارنسی‌ها symbol قبل عدد، برای بعضی‌ها بعد عدد
        switch currency {
        // Prefix (symbol before number)
        case .EUR, .GBP, .USD, .JPY, .CNY,
             .CAD, .AUD, .NZD, .SGD, .HKD, .MXN,
             .BRL, .ZAR, .INR, .KRW, .CHF:
            return "\(currency.symbol) \(formattedNumber)"  // € 1.000,00
        // Suffix (symbol after number) — Middle East, Nordics, PLN, RUB
        case .IRR, .AED, .SAR, .TRY,
             .SEK, .NOK, .DKK, .PLN, .RUB:
            return "\(formattedNumber) \(currency.symbol)"
        }
    }
    
    /// گرفتن symbol کارنسی فعلی
    static var currentSymbol: String {
        let currency = SupportedCurrency(rawValue: selectedCurrency) ?? .EUR
        return currency.symbol
    }
    
    /// گرفتن نام کارنسی فعلی
    static var currentCurrencyName: String {
        let currency = SupportedCurrency(rawValue: selectedCurrency) ?? .EUR
        return currency.name
    }
}

// MARK: - Extension برای راحتی
extension Double {
    /// فرمت کردن به string با کارنسی
    /// مثال: 500.0.formatted() → "€500.00"
    func currencyFormatted(showSymbol: Bool = true, showDecimal: Bool = true) -> String {
        CurrencyFormatter.format(self, showSymbol: showSymbol, showDecimal: showDecimal)
    }
}

extension Int {
    /// فرمت کردن به string با کارنسی
    func currencyFormatted(showSymbol: Bool = true, showDecimal: Bool = true) -> String {
        Double(self).currencyFormatted(showSymbol: showSymbol, showDecimal: showDecimal)
    }
}
