import Foundation

// ============================================================
// MARK: - Net Worth Milestone Detector (Phase 4c — iOS port)
// ============================================================
//
// Pure value-type derivation over `NetWorthSnapshot` history.
// Milestones are computed on the fly (not persisted) so they stay
// consistent across history rebuilds.
//
// Types:
//   .thresholdCrossed(cents) — first crossing of a canonical round
//                              dollar mark ($1k / $5k / $10k / $25k /
//                              $50k / $100k / $250k / $500k / $1M)
//   .allTimeHigh             — today's value equals the max-ever AND
//                              was set inside the 14-day recency window
//   .crossedZero             — net worth flipped from negative to
//                              non-negative (most recent such flip)
//   .doubled(since:)         — latest value ≥ 2× the earliest positive
//                              snapshot
//
// Ported from macOS. Adapted to iOS Int-cents throughout; uses a small
// inline `formatCents` helper in place of macOS's `CurrencyFormat`.
// ============================================================

struct NetWorthMilestone: Identifiable, Hashable {
    enum Kind: Hashable {
        case thresholdCrossed(cents: Int)
        case allTimeHigh
        case crossedZero
        case doubled(since: Date)
    }

    let id: String
    let kind: Kind
    let date: Date
    let valueCents: Int
    let title: String
    let detail: String
    let icon: String
}

enum NetWorthMilestoneDetector {

    /// Canonical "round number" thresholds in cents, smallest to largest.
    private static let thresholdsCents: [Int] = [
        100_000,      //    $1k
        500_000,      //    $5k
        1_000_000,    //   $10k
        2_500_000,    //   $25k
        5_000_000,    //   $50k
        10_000_000,   //  $100k
        25_000_000,   //  $250k
        50_000_000,   //  $500k
        100_000_000,  //    $1M
    ]

    /// ATH is only celebrated if the new peak was set inside this window.
    private static let athRecencyDays = 14

    // MARK: - Public

    static func detect(from snapshots: [NetWorthSnapshot]) -> [NetWorthMilestone] {
        let sorted = snapshots.sorted { $0.date < $1.date }
        guard let latest = sorted.last else { return [] }

        var out: [NetWorthMilestone] = []
        out.append(contentsOf: detectThresholds(sorted: sorted))
        if let ath = detectAllTimeHigh(sorted: sorted, latest: latest) { out.append(ath) }
        if let zero = detectZeroCross(sorted: sorted) { out.append(zero) }
        if let doubled = detectDoubled(sorted: sorted, latest: latest) { out.append(doubled) }

        return out.sorted { $0.date > $1.date }
    }

    // MARK: - Threshold crossings

    private static func detectThresholds(sorted: [NetWorthSnapshot]) -> [NetWorthMilestone] {
        guard sorted.count >= 2 else { return [] }
        var out: [NetWorthMilestone] = []
        for threshold in thresholdsCents {
            // First snapshot whose netWorth >= threshold and whose prev was below.
            for i in 1..<sorted.count {
                let prev = sorted[i - 1].netWorth
                let cur = sorted[i].netWorth
                if prev < threshold && cur >= threshold {
                    out.append(NetWorthMilestone(
                        id: "threshold:\(threshold)",
                        kind: .thresholdCrossed(cents: threshold),
                        date: sorted[i].date,
                        valueCents: cur,
                        title: "Crossed \(formatCompact(cents: threshold))",
                        detail: "First time on \(sorted[i].date.formatted(.dateTime.month(.abbreviated).day().year()))",
                        icon: "flag.checkered"
                    ))
                    break
                }
            }
        }
        return out
    }

    // MARK: - All-time high

    private static func detectAllTimeHigh(sorted: [NetWorthSnapshot], latest: NetWorthSnapshot) -> NetWorthMilestone? {
        guard sorted.count >= 7 else { return nil }  // not meaningful on day 1
        let max = sorted.map(\.netWorth).max() ?? 0
        guard latest.netWorth >= max, latest.netWorth > 0 else { return nil }

        let recent = Calendar.current.date(byAdding: .day, value: -athRecencyDays, to: Date()) ?? .distantPast
        guard latest.date >= recent else { return nil }

        return NetWorthMilestone(
            id: "ath",
            kind: .allTimeHigh,
            date: latest.date,
            valueCents: latest.netWorth,
            title: "All-time high",
            detail: "New peak at \(formatStandard(cents: latest.netWorth))",
            icon: "mountain.2.fill"
        )
    }

    // MARK: - Zero crossing (underwater → above)

    private static func detectZeroCross(sorted: [NetWorthSnapshot]) -> NetWorthMilestone? {
        guard sorted.count >= 2 else { return nil }
        for i in stride(from: sorted.count - 1, to: 0, by: -1) {
            let prev = sorted[i - 1].netWorth
            let cur = sorted[i].netWorth
            if prev < 0 && cur >= 0 {
                return NetWorthMilestone(
                    id: "zero-cross",
                    kind: .crossedZero,
                    date: sorted[i].date,
                    valueCents: cur,
                    title: "Out of the red",
                    detail: "Net worth turned positive on \(sorted[i].date.formatted(.dateTime.month(.abbreviated).day()))",
                    icon: "arrow.up.forward.circle.fill"
                )
            }
        }
        return nil
    }

    // MARK: - Doubled since earliest positive

    private static func detectDoubled(sorted: [NetWorthSnapshot], latest: NetWorthSnapshot) -> NetWorthMilestone? {
        // Doubling from a negative base is nonsense — find the earliest positive.
        guard let earliest = sorted.first(where: { $0.netWorth > 0 }) else { return nil }
        guard earliest.netWorth > 0,
              latest.netWorth >= earliest.netWorth * 2,
              earliest.date != latest.date else { return nil }

        return NetWorthMilestone(
            id: "doubled:\(earliest.date.timeIntervalSince1970)",
            kind: .doubled(since: earliest.date),
            date: latest.date,
            valueCents: latest.netWorth,
            title: "Doubled",
            detail: "From \(formatCompact(cents: earliest.netWorth)) on \(earliest.date.formatted(.dateTime.month(.abbreviated).year()))",
            icon: "multiply.circle.fill"
        )
    }

    // MARK: - Formatting

    private static func formatCompact(cents: Int) -> String {
        let dollars = Double(cents) / 100
        switch abs(dollars) {
        case 1_000_000...:
            return String(format: "$%.1fM", dollars / 1_000_000)
        case 1_000...:
            return String(format: "$%.0fk", dollars / 1_000)
        default:
            return String(format: "$%.0f", dollars)
        }
    }

    private static func formatStandard(cents: Int) -> String {
        let dollars = Double(cents) / 100
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: dollars)) ?? String(format: "$%.0f", dollars)
    }
}
