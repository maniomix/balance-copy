import SwiftUI

// ============================================================
// MARK: - Action Cards View
// ============================================================
// Horizontally scrolling action cards for the dashboard.
// Each card shows a prioritized action with tap-to-navigate
// and swipe-to-dismiss.
// ============================================================

struct ActionCardsView: View {
    let cards: [ActionCard]
    let monthKey: String
    var onDismiss: (ActionCard) -> Void = { _ in }

    var body: some View {
        if cards.isEmpty { EmptyView() }
        else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Actions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Text("\(cards.count) pending")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DS.Colors.accent.opacity(0.15), in: Capsule())

                    Spacer()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(cards) { card in
                            ActionCardView(card: card)
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity),
                                    removal: .slide.combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal, -2)
            }
        }
    }
}

// MARK: - Single Action Card

struct ActionCardView: View {
    let card: ActionCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(hexValue: UInt32(card.iconColor)).opacity(0.15))
                        .frame(width: 32, height: 32)

                    Image(systemName: card.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hexValue: UInt32(card.iconColor)))
                }

                priorityDot
            }

            Text(card.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Colors.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(card.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(DS.Colors.subtext)
                .lineLimit(2)
        }
        .padding(14)
        .frame(width: 180, height: 150, alignment: .topLeading)
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(borderColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var priorityDot: some View {
        Group {
            switch card.priority {
            case .critical:
                Circle().fill(.red).frame(width: 8, height: 8)
            case .high:
                Circle().fill(.orange).frame(width: 6, height: 6)
            default:
                EmptyView()
            }
        }
    }

    private var borderColor: Color {
        switch card.priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return DS.Colors.grid
        case .low: return DS.Colors.grid
        }
    }
}
