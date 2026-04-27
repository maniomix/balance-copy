import SwiftUI

struct AIInsightsSectionCard: View {
    let insights: [AIInsight]
    let onAskAI: () -> Void
    let onSelect: (AIInsight) -> Void

    var body: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                    Text("AI Insights")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    Button { onAskAI() } label: {
                        Text("Ask AI")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.accent)
                    }
                }

                ForEach(insights.prefix(5)) { insight in
                    Button {
                        Haptics.light()
                        onSelect(insight)
                    } label: {
                        AIInsightBanner(insight: insight) { _ in
                            onSelect(insight)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
