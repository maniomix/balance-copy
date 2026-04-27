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

        // ── Backgrounds (Pure black in dark, warm soft canvas in light) ──
        static let bg = adaptive(
            light: UIColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1),  // #F5F7FC soft blue-tinted canvas
            dark:  .black                                                   // #000000 pure black
        )
        static let surface = adaptive(
            light: .white,                                                  // crisp white cards pop on tinted bg
            dark:  UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)   // #0D0D12 near-black card
        )
        static let surface2 = adaptive(
            light: UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1),  // #EDF2FA gentle blue-grey
            dark:  UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)   // #17171C
        )
        /// Elevated surface for cards
        static let surfaceElevated = adaptive(
            light: .white,
            dark:  UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)   // #121217
        )

        // ── Text (Stronger contrast for readability) ──
        static let text = adaptive(
            light: UIColor(red: 0.07, green: 0.09, blue: 0.13, alpha: 1),  // #121720 near-black, slight blue
            dark:  UIColor(red: 0.97, green: 0.98, blue: 1.00, alpha: 1)   // #F8FAFF crisp white
        )
        static let subtext = adaptive(
            light: UIColor(red: 0.40, green: 0.44, blue: 0.52, alpha: 1),  // #667085 readable secondary
            dark:  UIColor(red: 0.60, green: 0.62, blue: 0.70, alpha: 1)   // cool grey
        )
        static let textTertiary = adaptive(
            light: UIColor(red: 0.58, green: 0.62, blue: 0.70, alpha: 1),  // #939EB3 muted but visible
            dark:  UIColor(red: 0.40, green: 0.42, blue: 0.50, alpha: 1)
        )
        static let grid = adaptive(
            light: UIColor(red: 0.88, green: 0.91, blue: 0.95, alpha: 1),  // #E1E8F2 soft blue-grey divider
            dark:  UIColor(red: 0.14, green: 0.15, blue: 0.20, alpha: 1)
        )

        // ── Accent: Beautiful electric blue ──
        static let accent = Color(red: 0.20, green: 0.55, blue: 1.00)       // #338CFF vivid blue
        static let accentLight = adaptive(
            light: UIColor(red: 0.20, green: 0.55, blue: 1.00, alpha: 0.10),
            dark:  UIColor(red: 0.20, green: 0.55, blue: 1.00, alpha: 0.18)
        )
        static let buttonFill = adaptive(
            light: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1),
            dark:  UIColor(red: 0.20, green: 0.55, blue: 1.00, alpha: 1)
        )

        // ── Semantic (refined — calmer in light, softer in dark) ──
        static let positive = adaptive(
            light: UIColor(red: 0.10, green: 0.65, blue: 0.42, alpha: 1),   // #1AA66B deeper, more readable green
            dark:  UIColor(red: 0.40, green: 0.85, blue: 0.65, alpha: 1)    // #66D9A6 softer pastel
        )
        static let warning = adaptive(
            light: UIColor(red: 0.85, green: 0.55, blue: 0.05, alpha: 1),   // #D98C0D richer, less neon amber
            dark:  UIColor(red: 1.00, green: 0.78, blue: 0.40, alpha: 1)    // #FFC766 soft gold
        )
        static let danger = adaptive(
            light: UIColor(red: 0.85, green: 0.22, blue: 0.27, alpha: 1),   // #D93845 grounded red
            dark:  UIColor(red: 0.98, green: 0.45, blue: 0.47, alpha: 1)    // #FA7378 softer coral
        )
        static let negative = adaptive(
            light: UIColor(red: 0.85, green: 0.22, blue: 0.27, alpha: 1),   // #D93845
            dark:  UIColor(red: 0.98, green: 0.45, blue: 0.47, alpha: 1)    // #FA7378
        )
    }

    // MARK: - Typography (Better Hierarchy)
    //
    // Text-style-based so they respect Dynamic Type. Default point sizes line
    // up with the old fixed values: largeTitle=28, title=20, section=17,
    // body=15, caption=13, number=17. `callout` drifts 14→15 (closest text
    // style is .subheadline at 15pt — 1pt drift is accepted in exchange for
    // Dynamic Type support). `heroAmount` intentionally stays fixed because
    // the dashboard hero card layout is not safe at accessibility sizes.
    enum Typography {
        static let largeTitle = Font.system(.title, design: .rounded).weight(.bold)
        static let title = Font.system(.title3, design: .rounded).weight(.semibold)
        static let section = Font.system(.headline, design: .rounded)
        static let body = Font.system(.subheadline, design: .rounded)
        static let callout = Font.system(.subheadline, design: .rounded).weight(.medium)
        static let caption = Font.system(.footnote, design: .rounded)
        static let number = Font.system(.body, design: .monospaced).weight(.semibold).monospacedDigit()
        static let heroAmount = Font.system(size: 42, weight: .bold, design: .rounded).monospacedDigit()
    }

    // MARK: - Gradients (Premium accent-based)
    enum Gradients {
        /// Primary accent gradient — deep azure to electric blue
        static let accent = LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.30, blue: 0.85),  // Deep azure
                Color(red: 0.20, green: 0.55, blue: 1.00),  // #338CFF
                Color(red: 0.40, green: 0.75, blue: 1.00)   // Sky highlight
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Subtle card shimmer — very low opacity blue wash
        static let cardShimmer = LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.55, blue: 1.00).opacity(0.08),
                Color(red: 0.10, green: 0.40, blue: 0.90).opacity(0.04),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Positive glow — green to teal
        static let positive = LinearGradient(
            colors: [
                Colors.positive.opacity(0.8),
                Colors.positive
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        /// Danger glow — coral to red
        static let danger = LinearGradient(
            colors: [
                Colors.danger.opacity(0.8),
                Colors.danger
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        /// Mesh-style background overlay
        static let meshOverlay = LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.55, blue: 1.00).opacity(0.10),
                Color(red: 0.10, green: 0.30, blue: 0.85).opacity(0.05),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Materials (Glassmorphism)
    enum Materials {
        /// Ultra-thin blur for sticky headers & overlays
        static let ultraThin = Material.ultraThinMaterial
        /// Thin blur for cards floating above content
        static let thin = Material.thinMaterial
        /// Regular blur for modal backgrounds
        static let regular = Material.regularMaterial
    }

    // MARK: - Card (Elevation-based, subtle border in dark)
    struct Card<Content: View>: View {
        var padding: CGFloat = 18
        @Environment(\.colorScheme) private var colorScheme
        @ViewBuilder var content: Content
        var body: some View {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(colorScheme == .dark ? Colors.surfaceElevated : Colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            colorScheme == .dark
                                ? Color.white.opacity(0.06)
                                : Color(red: 0.20, green: 0.55, blue: 1.00).opacity(0.06),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: colorScheme == .dark
                        ? .clear                              // no shadow in dark — rely on elevation + border
                        : Color(red: 0.10, green: 0.20, blue: 0.40).opacity(0.06),
                    radius: 14,
                    x: 0,
                    y: 6
                )
        }
    }

    // MARK: - Primary Button (Accent filled)
    struct PrimaryButton: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Gradients.accent)
                )
                .shadow(color: Colors.accent.opacity(configuration.isPressed ? 0.15 : 0.45), radius: 12, x: 0, y: 4)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }

    // MARK: - Colored Button (Subtle)
    struct ColoredButton: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Colors.accent)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Colors.accentLight)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }

    // MARK: - Modern Scale Button Style (Premium micro-interaction)
    struct ModernScaleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .opacity(configuration.isPressed ? 0.85 : 1.0)
                .animation(
                    .spring(response: 0.28, dampingFraction: 0.72, blendDuration: 0),
                    value: configuration.isPressed
                )
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

    // MARK: - Beta Badge (small capsule for pre-release features)
    struct BetaBadge: View {
        var label: String = "BETA"
        var color: Color = Colors.warning

        var body: some View {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(color.opacity(0.15)))
                .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.5))
        }
    }

    // MARK: - Section Header (Elegant grouping)
    struct SectionHeader: View {
        let title: String
        var icon: String? = nil
        var trailing: AnyView? = nil

        var body: some View {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Colors.accent)
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Colors.subtext)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                if let trailing {
                    trailing
                }
            }
        }
    }

    struct StatusLine: View {
        let title: String
        let detail: String
        let level: Level

        @Environment(\.colorScheme) private var colorScheme

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
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Colors.surfaceElevated : Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03),
                        lineWidth: 1
                    )
            )
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
