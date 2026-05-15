import SwiftUI

/// 7 vertical bars for the past week. Last index = today. Tallest bar is
/// emphasized; today's bar carries the accent so the user sees both "how
/// much this week" and "where today sits in that pattern" in one glance.
struct DailyBars: View {
    let buckets: [Int]              // 7 entries, index 0 = 6 days ago, 6 = today
    let tint: Color
    var height: CGFloat = 28
    var showLabels: Bool = true

    private var maxValue: Int { max(1, buckets.max() ?? 1) }
    private var maxIndex: Int { buckets.firstIndex(of: buckets.max() ?? 0) ?? -1 }

    /// Day-of-week initials anchored to today (index 6) and counting back.
    /// Locale-aware: respects `Calendar.current.veryShortStandaloneWeekdaySymbols`.
    private static let veryShortWeekdays: [String] = {
        let f = DateFormatter()
        f.locale = .current
        return f.veryShortStandaloneWeekdaySymbols
    }()

    private var dayLabels: [String] {
        let cal = Calendar.current
        // weekday returns 1...7 with 1 = Sunday (Gregorian) regardless of
        // the user's firstWeekday setting. We index directly into the
        // symbols array which is also Sunday-first.
        let today = cal.component(.weekday, from: Date()) // 1...7
        return (0..<7).map { offset in
            let daysAgo = 6 - offset
            let weekdayIdx = ((today - 1 - daysAgo) % 7 + 7) % 7
            return Self.veryShortWeekdays[weekdayIdx]
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                let count = max(1, buckets.count)
                let totalSpacing = CGFloat(count - 1) * 4
                let barWidth = max(4, (geo.size.width - totalSpacing) / CGFloat(count))
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0..<count, id: \.self) { i in
                        let value = i < buckets.count ? buckets[i] : 0
                        let pct = Double(value) / Double(maxValue)
                        let isToday = i == count - 1
                        let isPeak = i == maxIndex && value > 0
                        let fill: Color = isToday
                            ? tint
                            : (isPeak ? tint.opacity(0.85) : Color.white.opacity(value == 0 ? 0.12 : 0.4))
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(fill)
                            .frame(
                                width: barWidth,
                                height: max(2, height * CGFloat(max(0.06, pct)))
                            )
                    }
                }
                .frame(height: height, alignment: .bottom)
            }
            .frame(height: height)

            if showLabels {
                HStack(spacing: 4) {
                    ForEach(0..<min(7, dayLabels.count), id: \.self) { i in
                        Text(dayLabels[i])
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(i == 6 ? tint : .white.opacity(0.45))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Past 7 days spending chart")
    }
}
