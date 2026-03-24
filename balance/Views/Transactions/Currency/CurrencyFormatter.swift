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
        case .EUR, .GBP, .USD, .JPY, .CNY:
            return "\(currency.symbol) \(formattedNumber)"  // € 1.000,00
        case .IRR, .AED, .SAR, .TRY:
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
