import SwiftUI

// Hero amount + right-aligned stat tile — used by every expanded page so the
// 4 pages share the same visual rhythm.

struct PageHero: View {
    let amount: String
    let label: String
    let tint: Color
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(amount)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .allowsTightening(true)
                .layoutPriority(2)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .layoutPriority(0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let tint: Color
    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .fixedSize(horizontal: true, vertical: true)
        .layoutPriority(1)
    }
}
