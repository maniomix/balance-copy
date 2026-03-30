import SwiftUI

// MARK: - Design System

enum DS {
    // MARK: - Adaptive Colors (Light + Dark)
    enum Colors {
        // Helper: creates an adaptive Color that switches between light & dark variants
        private static func adaptive(light: UIColor, dark: UIColor) -> Color {
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            })
        }

        // ── Backgrounds ──
        static let bg = adaptive(
            light: UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1),  // #F7F7FA
            dark:  UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)   // #121217
        )
        static let surface = adaptive(
            light: .white,
            dark:  UIColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 1)   // #1C1C23
        )
        static let surface2 = adaptive(
            light: UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1),  // #F2F2F7
            dark:  UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1)   // #26262E
        )

        // ── Text ──
        static let text = adaptive(
            light: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1),  // #1C1C1F
            dark:  UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)   // #F2F2F7
        )
        static let subtext = adaptive(
            light: UIColor(red: 0.56, green: 0.56, blue: 0.58, alpha: 1),  // #8F8F94
            dark:  UIColor(red: 0.60, green: 0.60, blue: 0.65, alpha: 1)   // #9999A6
        )
        static let textTertiary = adaptive(
            light: UIColor(red: 0.72, green: 0.72, blue: 0.74, alpha: 1),  // #B8B8BC
            dark:  UIColor(red: 0.45, green: 0.45, blue: 0.50, alpha: 1)   // #737380
        )
        static let grid = adaptive(
            light: UIColor(red: 0.91, green: 0.91, blue: 0.93, alpha: 1),  // #E8E8ED
            dark:  UIColor(red: 0.20, green: 0.20, blue: 0.24, alpha: 1)   // #33333D
        )

        // ── Accent (same in both modes) ──
        static let accent = Color(red: 0.27, green: 0.35, blue: 0.96)       // #4559F5
        static let accentLight = adaptive(
            light: UIColor(red: 0.27, green: 0.35, blue: 0.96, alpha: 0.08),
            dark:  UIColor(red: 0.27, green: 0.35, blue: 0.96, alpha: 0.15)
        )
        static let buttonFill = adaptive(
            light: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1),
            dark:  UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        )

        // ── Semantic (same in both modes — vibrant enough) ──
        static let positive = Color(red: 0.20, green: 0.78, blue: 0.55)     // #34C78C
        static let warning  = Color(red: 1.00, green: 0.72, blue: 0.27)     // #FFB845
        static let danger   = Color(red: 0.96, green: 0.32, blue: 0.35)     // #F55259
        static let negative = Color(red: 0.96, green: 0.32, blue: 0.35)     // #F55259
    }

    // MARK: - Typography (Better Hierarchy)
    enum Typography {
        static let largeTitle = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let section = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 15, weight: .regular, design: .rounded)
        static let callout = Font.system(size: 14, weight: .medium, design: .rounded)
        static let caption = Font.system(size: 13, weight: .regular, design: .rounded)
        static let number = Font.system(size: 17, weight: .semibold, design: .monospaced)
        static let heroAmount = Font.system(size: 42, weight: .bold, design: .rounded)
    }

    // MARK: - Card (Shadow-based, no borders)
    struct Card<Content: View>: View {
        var padding: CGFloat = 18
        @Environment(\.colorScheme) private var colorScheme
        @ViewBuilder var content: Content
        var body: some View {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(padding)
                .background(Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: colorScheme == .dark ? 8 : 12, x: 0, y: 4)
        }
    }

    // MARK: - Primary Button (Accent filled)
    struct PrimaryButton: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Colors.accent)
                )
                .shadow(color: Colors.accent.opacity(configuration.isPressed ? 0 : 0.25), radius: 12, x: 0, y: 4)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }

    // MARK: - Colored Button (Subtle)
    struct ColoredButton: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(Colors.accent)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Colors.accentLight)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }

    // MARK: - TextField Style (Borderless, background contrast)
    struct TextFieldStyle: SwiftUI.TextFieldStyle {
        func _body(configuration: TextField<Self._Label>) -> some View {
            configuration
                .font(Typography.body)
                .padding(14)
                .background(Colors.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(Colors.text)
        }
    }

    /// Beautiful empty state component
    struct EmptyState: View {
        let icon: String
        let title: String
        let message: String
        var actionTitle: String? = nil
        var action: (() -> Void)? = nil

        var body: some View {
            VStack(spacing: Spacing.lg) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Colors.subtext.opacity(0.5))

                // Text
                VStack(spacing: Spacing.sm) {
                    Text(title)
                        .font(Typography.section)
                        .foregroundStyle(Colors.text)

                    Text(message)
                        .font(Typography.body)
                        .foregroundStyle(Colors.subtext)
                        .multilineTextAlignment(.center)
                }

                // Action button
                if let actionTitle = actionTitle, let action = action {
                    Button(action: action) {
                        Text(actionTitle)
                    }
                    .buttonStyle(PrimaryButton())
                    .padding(.horizontal, Spacing.xl)
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity)
        }
    }

    struct StatusLine: View {
        let title: String
        let detail: String
        let level: Level

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(level.color.opacity(0.12))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: level.icon)
                            .foregroundStyle(level.color)
                            .font(.system(size: 13, weight: .semibold))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Typography.body.weight(.semibold))
                        .foregroundStyle(Colors.text)
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Colors.subtext)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
    }

    struct Meter: View {
        let title: String
        let value: Int
        let max: Int
        let hint: String

        private var ratio: Double { min(1, Double(value) / Double(max)) }
        private var level: Level {
            if ratio < 0.70 { return .ok }
            if ratio <= 0.80 { return .watch }
            return .risk
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(Typography.caption)
                        .foregroundStyle(Colors.subtext)
                    Spacer()
                    Text(hint)
                        .font(Typography.caption)
                        .foregroundStyle(level == .ok ? Colors.subtext : level.color)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Colors.surface2)
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(level.color)
                            .frame(width: geo.size.width * ratio)
                            .opacity(0.85)
                            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: ratio)
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    enum Format {
        static func money(_ cents: Int) -> String {
            let currencyCode = UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"

            let nf = NumberFormatter()
            nf.numberStyle = .currency
            nf.locale = .current
            nf.currencyCode = currencyCode

            // Set symbol based on currency
            switch currencyCode {
            case "EUR": nf.currencySymbol = "€"
            case "USD": nf.currencySymbol = "$"
            case "GBP": nf.currencySymbol = "£"
            case "JPY": nf.currencySymbol = "¥"
            case "CAD": nf.currencySymbol = "C$"
            default: nf.currencySymbol = currencyCode
            }

            nf.minimumFractionDigits = 2
            nf.maximumFractionDigits = 2

            let value = Decimal(cents) / Decimal(100)
            return nf.string(from: value as NSDecimalNumber) ?? "\(nf.currencySymbol ?? "")\(value)"
        }

        /// Format money with superscript cents (e.g., 105,²⁴ €)
        static func moneyAttributed(_ cents: Int) -> AttributedString {
            let currencyCode = UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"
            let currencySymbol: String

            switch currencyCode {
            case "EUR": currencySymbol = "€"
            case "USD": currencySymbol = "$"
            case "GBP": currencySymbol = "£"
            case "JPY": currencySymbol = "¥"
            case "CAD": currencySymbol = "C$"
            default: currencySymbol = currencyCode
            }

            let value = Double(cents) / 100.0
            let euros = Int(value)
            let centsPart = abs(cents % 100)

            // Format: 105,²⁴ €
            var result = AttributedString("\(euros),")

            // Superscript cents
            var centsStr = AttributedString(String(format: "%02d", centsPart))
            centsStr.font = .system(size: 11, weight: .medium)
            centsStr.baselineOffset = 6

            result += centsStr
            result += AttributedString(" \(currencySymbol)")

            return result
        }

        // Alias for ProfileView compatibility
        static func currency(_ cents: Int) -> String {
            return money(cents)
        }

        static func percent(_ value: Double) -> String {
            let nf = NumberFormatter()
            nf.numberStyle = .percent
            nf.locale = .current
            nf.minimumFractionDigits = 0
            nf.maximumFractionDigits = 0
            return nf.string(from: NSNumber(value: value)) ?? "\(Int(value * 100))%"
        }

        /// Parses user-entered money text into **cents**.
        /// Accepts: "250", "250.5", "250.50", "250,50"
        static func cents(from text: String) -> Int {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return 0 }

            var cleaned = ""
            var didAddDot = false

            for ch in trimmed {
                if ch.isNumber {
                    cleaned.append(ch)
                } else if (ch == "." || ch == ",") && !didAddDot {
                    cleaned.append(".")
                    didAddDot = true
                }
            }

            guard !cleaned.isEmpty else { return 0 }

            // If no decimal separator: treat as euros (e.g. "250" => 25000 cents)
            if !cleaned.contains(".") {
                let euros = Int(cleaned) ?? 0
                return max(0, euros * 100)
            }

            let dec = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) ?? 0
            let centsDec = dec * Decimal(100)
            let cents = NSDecimalNumber(decimal: centsDec).rounding(accordingToBehavior: nil).intValue
            return max(0, cents)
        }

        static func relativeDateTime(_ date: Date) -> String {
            let fmt = RelativeDateTimeFormatter()
            fmt.locale = .current
            fmt.unitsStyle = .abbreviated
            return fmt.localizedString(for: date, relativeTo: Date())
        }

        /// Returns currency symbol (€, $, £, etc.)
        static func currencySymbol() -> String {
            let currencyCode = UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"

            switch currencyCode {
            case "EUR": return "€"
            case "USD": return "$"
            case "GBP": return "£"
            case "JPY": return "¥"
            case "CAD": return "C$"
            default: return currencyCode
            }
        }

        /// Returns formatted placeholder (e.g., "€ 250")
        static func amountPlaceholder() -> String {
            return "\(currencySymbol()) 250"
        }
    }
}

// MARK: - Level

enum Level: Hashable {
    case ok, watch, risk

    var icon: String {
        switch self {
        case .ok: return "checkmark"
        case .watch: return "exclamationmark"
        case .risk: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ok: return DS.Colors.positive
        case .watch: return DS.Colors.warning
        case .risk: return DS.Colors.danger
        }
    }
}

// MARK: - Enhanced Design System

extension DS {
    /// Consistent spacing values
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        static let xxxl: CGFloat = 36
    }

    /// Standard animations
    enum Animations {
        static let quick = Animation.spring(response: 0.3, dampingFraction: 0.7)
        static let standard = Animation.spring(response: 0.4, dampingFraction: 0.8)
        static let smooth = Animation.spring(response: 0.45, dampingFraction: 0.9)
        static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.95)
    }

    /// Corner radius standards
    enum Corners {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let pill: CGFloat = 999
    }
}
