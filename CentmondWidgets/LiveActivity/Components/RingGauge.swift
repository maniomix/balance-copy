import SwiftUI

/// Circular spend gauge — used in the Budget page and lock-screen hero.
/// Replaces the linear progress bar with a denser, more glanceable read.
/// Background ring is the tint at low opacity; foreground arc is full tint.
/// Center label shows the integer percent.
struct RingGauge: View {
    let percent: Double
    let tint: Color
    var size: CGFloat = 44
    var lineWidth: CGFloat = 4.5
    var showPercentText: Bool = true

    private var clamped: Double { max(0, min(1.0, percent)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, clamped))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showPercentText {
                Text("\(Int(clamped * 100))%")
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(clamped * 100)) percent of budget spent")
    }
}
