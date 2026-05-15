import SwiftUI

/// Compact donut showing one category's share of total month spend.
/// The arc is the share; the hole shows the category icon.
struct CategoryDonut: View {
    let share: Double               // 0...1
    let icon: String
    let tint: Color
    var size: CGFloat = 36
    var lineWidth: CGFloat = 4

    private var clamped: Double { max(0, min(1.0, share)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, clamped))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: icon)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Top category, \(Int(clamped * 100)) percent of month")
    }
}
