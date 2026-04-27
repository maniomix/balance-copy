import SwiftUI

struct UnderstandingCard: View {
    let store: Store

    var body: some View {
        let proj = Analytics.projectedEndOfMonth(store: store)
        let ruleInsights = Analytics.generateInsights(store: store)

        let title = proj.level == .risk
            ? "This trend will pressure your budget"
            : "Approaching the limit"

        let detail = proj.level == .risk
            ? "End-of-month projection is above budget. Prioritize cutting discretionary costs."
            : "To stay in control, trim one discretionary category slightly."

        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Understanding")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                DS.StatusLine(title: title, detail: detail, level: proj.level)

                if !ruleInsights.isEmpty {
                    Divider()
                        .background(DS.Colors.surface2)

                    VStack(spacing: 10) {
                        ForEach(ruleInsights) { insight in
                            InsightRow(insight: insight)
                        }
                    }
                }

                Text("Based on current spending")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
            }
        }
    }
}
