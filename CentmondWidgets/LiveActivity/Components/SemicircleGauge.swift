import SwiftUI

/// U-shape "smile" gauge — the bottom half of a circular ring, fills from
/// left to right. Used for "pace" indicators on Today / Week pages. Drawn
/// via Canvas so we get exactly-half precision without ZStack rotation
/// jiggling.
struct SemicircleGauge: View {
    let percent: Double
    let valueText: String       // e.g. "78%"
    let label: String           // e.g. "PACE"
    let tint: Color
    var width: CGFloat = 56
    var lineWidth: CGFloat = 4.5

    private var clamped: Double { max(0, min(1.0, percent)) }

    var body: some View {
        VStack(spacing: 1) {
            Text(valueText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height)
                let radius = (size.width - lineWidth) / 2
                // Background bottom-half arc: 180° (left) → 360° (right).
                var bg = Path()
                bg.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(360),
                    clockwise: false
                )
                context.stroke(bg, with: .color(tint.opacity(0.22)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                // Foreground arc — proportional fill from left.
                var fg = Path()
                fg.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(180 + 180 * clamped),
                    clockwise: false
                )
                context.stroke(fg, with: .color(tint),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            .frame(width: width, height: width / 2 + lineWidth / 2)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) gauge, \(valueText)")
    }
}
