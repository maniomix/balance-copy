import SwiftUI

/// Icon-prefixed mini stat — the building block of every page's bottom row.
/// Matches the reference-screenshot aesthetic: filled SF Symbol in the tint
/// color, monospaced number/text in slightly muted white.
///
/// Pair two of these in an HStack with a Spacer between for the canonical
/// left+right page footer.
struct IconStat: View {
    let icon: String
    let text: String
    var tint: Color = .white.opacity(0.75)
    var weight: Font.Weight = .semibold

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12, weight: weight, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Reusable hero block — big amount + uppercase tracking label below.
/// Used by every page's left column.
struct HeroBlock: View {
    let amount: String
    let label: String
    let tint: Color
    var amountSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(amount)
                .font(.system(size: amountSize, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .allowsTightening(true)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
    }
}
