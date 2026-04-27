import SwiftUI

// MARK: - Insight Model

struct ChartInsight: Identifiable, Hashable {
    let id: String
    let text: String
    let tint: Color
    let icon: String
    let scrollAnchor: String?
    let chatPrefill: String
}

// MARK: - Generator

enum ChartsInsightsGenerator {
    static func build(store: Store, range: ChartRange) -> [ChartInsight] {
        let snap = ChartsAnalytics.shared.snapshot(store: store, range: range, now: store.selectedMonth)
        let kpi = snap.kpi
        var out: [ChartInsight] = []

        // Δ vs previous period
        if kpi.previousTotalSpent > 0 {
            let pct = Int((kpi.spentDeltaRatio * 100).rounded())
            if pct >= 10 {
                out.append(.init(
                    id: "delta.up",
                    text: "Spending up \(pct)% vs last period",
                    tint: DS.Colors.danger,
                    icon: "arrow.up.right.circle.fill",
                    scrollAnchor: "chart.trend",
                    chatPrefill: "My spending is up \(pct)% vs last \(range.displayName.lowercased()). What's driving it and how do I pull it back?"
                ))
            } else if pct <= -10 {
                out.append(.init(
                    id: "delta.down",
                    text: "Spending down \(-pct)% vs last period",
                    tint: DS.Colors.positive,
                    icon: "arrow.down.right.circle.fill",
                    scrollAnchor: "chart.trend",
                    chatPrefill: "Nice — spending is down \(-pct)% vs last \(range.displayName.lowercased()). Help me keep the momentum."
                ))
            }
        }

        // Biggest category
        if let top = snap.categories.first, top.amount > 0 {
            let totalCat = snap.categories.reduce(0) { $0 + $1.amount }
            if totalCat > 0 {
                let share = Int((Double(top.amount) / Double(totalCat) * 100).rounded())
                if share >= 30 {
                    out.append(.init(
                        id: "top.share",
                        text: "\(top.category.title) is \(share)% of spending",
                        tint: CategoryRegistry.shared.tint(for: top.category),
                        icon: "circle.grid.2x2.fill",
                        scrollAnchor: "chart.category",
                        chatPrefill: "\(top.category.title) is \(share)% of my spending this \(range.displayName.lowercased()). Where can I trim it?"
                    ))
                }
            }
        }

        // Top mover (category delta)
        let movers = snap.categories.filter { $0.previousAmount > 0 && abs($0.deltaRatio) > 0.25 }
        if let riser = movers.sorted(by: { $0.deltaRatio > $1.deltaRatio }).first, riser.deltaRatio > 0.25 {
            let pct = Int((riser.deltaRatio * 100).rounded())
            out.append(.init(
                id: "mover.up.\(riser.id)",
                text: "\(riser.category.title) up \(pct)%",
                tint: DS.Colors.danger,
                icon: "chart.line.uptrend.xyaxis",
                scrollAnchor: "chart.category",
                chatPrefill: "\(riser.category.title) jumped \(pct)% vs last \(range.displayName.lowercased()). What happened and what should I do?"
            ))
        }

        // Cashflow — net sign
        if kpi.totalIncome > 0 {
            let rate = Double(kpi.netSavings) / Double(kpi.totalIncome)
            if kpi.netSavings < 0 {
                out.append(.init(
                    id: "cashflow.negative",
                    text: "Spending exceeded income",
                    tint: DS.Colors.danger,
                    icon: "exclamationmark.triangle.fill",
                    scrollAnchor: "chart.cashflow",
                    chatPrefill: "My expenses were higher than my income this \(range.displayName.lowercased()). Where do I start fixing this?"
                ))
            } else if rate >= 0.2 {
                let pct = Int((rate * 100).rounded())
                out.append(.init(
                    id: "cashflow.savings",
                    text: "Saved \(pct)% of income",
                    tint: DS.Colors.positive,
                    icon: "checkmark.seal.fill",
                    scrollAnchor: "chart.cashflow",
                    chatPrefill: "I saved \(pct)% of my income this \(range.displayName.lowercased()). Am I on track for my goals?"
                ))
            }
        }

        // Budget — over-cap categories
        var overCap = 0
        for c in snap.categories {
            let cap = store.categoryBudget(for: c.category)
            if cap > 0 && c.amount > cap { overCap += 1 }
        }
        if overCap > 0 {
            out.append(.init(
                id: "budget.over",
                text: "\(overCap) \(overCap == 1 ? "category is" : "categories are") over cap",
                tint: DS.Colors.danger,
                icon: "square.grid.3x3.fill",
                scrollAnchor: "chart.budget",
                chatPrefill: "\(overCap) of my categories went over their budget cap. Help me rebalance."
            ))
        }

        // Anomaly days
        if kpi.anomalyCount > 0 {
            out.append(.init(
                id: "anomaly",
                text: "\(kpi.anomalyCount) unusual spending \(kpi.anomalyCount == 1 ? "day" : "days")",
                tint: Color.orange,
                icon: "exclamationmark.circle.fill",
                scrollAnchor: "chart.trend",
                chatPrefill: "I had \(kpi.anomalyCount) unusually high spending periods. What caused the spikes?"
            ))
        }

        return out
    }
}

// MARK: - Rail View

struct ChartsInsightsRail: View {
    let store: Store
    let range: ChartRange
    let onScroll: (String) -> Void
    let onAsk: (String) -> Void

    private var insights: [ChartInsight] {
        ChartsInsightsGenerator.build(store: store, range: range)
    }

    var body: some View {
        if insights.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(insights) { insight in
                        InsightChip(
                            insight: insight,
                            onTap: {
                                Haptics.light()
                                if let anchor = insight.scrollAnchor { onScroll(anchor) }
                            },
                            onAsk: {
                                Haptics.light()
                                onAsk(insight.chatPrefill)
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Chip

private struct InsightChip: View {
    let insight: ChartInsight
    let onTap: () -> Void
    let onAsk: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: insight.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(insight.tint)
                    Text(insight.text)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                        .lineLimit(1)
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(DS.Colors.grid.opacity(0.4))
                .frame(width: 0.5, height: 18)

            Button(action: onAsk) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Colors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .background(DS.Colors.surface2, in: Capsule())
        .overlay(
            Capsule().stroke(insight.tint.opacity(0.25), lineWidth: 0.5)
        )
    }
}
