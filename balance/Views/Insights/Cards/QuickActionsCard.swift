import SwiftUI

struct QuickActionsCard: View {
    let store: Store

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quick Actions")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                let actions = Analytics.quickActions(store: store)
                if actions.isEmpty {
                    Text("All good!")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                        .padding(.vertical, 6)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(actions, id: \.self) { a in
                            QuickActionChip(text: a)
                        }
                    }
                }
            }
        }
    }
}

private struct QuickActionChip: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Colors.accent)

            Text(text)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.text)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quick action: \(text)")
    }
}
