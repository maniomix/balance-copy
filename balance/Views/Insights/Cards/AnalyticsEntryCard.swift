import SwiftUI

struct AnalyticsEntryCard: View {
    let onOpen: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            onOpen()
        } label: {
            DS.Card {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DS.Colors.accent.opacity(0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Analytics")
                            .font(DS.Typography.section)
                            .foregroundStyle(DS.Colors.text)
                        Text("Trends, category drill-downs, cashflow, heatmap, merchants.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analytics")
        .accessibilityHint("Opens trends, category drill-downs, cashflow, heatmap, and merchants")
        .accessibilityAddTraits(.isButton)
    }
}
