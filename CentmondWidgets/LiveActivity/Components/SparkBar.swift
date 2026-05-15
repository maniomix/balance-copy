import SwiftUI

/// Hourly sparkline — 24 vertical bars. Empty hours render as a faint
/// baseline; bars scale to the busiest hour. The current hour is tinted
/// the accent color so the user reads "where did today go" at a glance.
/// A solid 1pt baseline line under the bars carries the eye across empty
/// stretches and gives the current-hour marker something to anchor to.
struct SparkBar: View {
    let buckets: [Int]              // 24 entries, cents per hour
    let currentHour: Int
    let tint: Color
    var height: CGFloat = 22

    private var maxValue: Int { max(1, buckets.max() ?? 1) }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let count = max(1, buckets.count)
                let totalSpacing = CGFloat(count - 1) * 1.5
                let barWidth = max(1.5, (geo.size.width - totalSpacing) / CGFloat(count))
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 1.5) {
                        ForEach(0..<count, id: \.self) { i in
                            let value = i < buckets.count ? buckets[i] : 0
                            let pct = Double(value) / Double(maxValue)
                            let isNow = i == currentHour
                            // Empty current hour gets a 3pt accent stub so the
                            // "you are here" marker is visible even before any
                            // spending lands today.
                            let isEmptyNow = isNow && value == 0
                            Capsule(style: .continuous)
                                .fill(
                                    isNow
                                        ? tint
                                        : (value == 0 ? Color.white.opacity(0.12) : tint.opacity(0.55))
                                )
                                .frame(
                                    width: barWidth,
                                    height: isEmptyNow
                                        ? max(3, height * 0.12)
                                        : max(2, height * CGFloat(max(0.06, pct)))
                                )
                        }
                    }
                    .frame(height: height, alignment: .bottom)
                }
            }
            .frame(height: height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's hourly spending")
    }
}
