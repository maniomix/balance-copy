import SwiftUI

enum InsightsEmptyState {
    case noBudget
    case noData

    var icon: String {
        switch self {
        case .noBudget: return "target"
        case .noData: return "chart.line.uptrend.xyaxis"
        }
    }

    var title: String {
        switch self {
        case .noBudget: return "Set a budget to unlock insights"
        case .noData: return "No spending this month yet"
        }
    }

    var detail: String {
        switch self {
        case .noBudget: return "Insights, projections, and quick actions all key off your monthly budget."
        case .noData: return "Add a few transactions and we'll surface trends, risks, and quick actions."
        }
    }

    var ctaTitle: String? {
        switch self {
        case .noBudget: return "Set Budget"
        case .noData: return nil
        }
    }
}

struct InsightsEmptyCard: View {
    let state: InsightsEmptyState
    let onCTA: () -> Void

    var body: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DS.Colors.accent.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: state.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                }

                Text(state.title)
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                Text(state.detail)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.subtext)
                    .fixedSize(horizontal: false, vertical: true)

                if let cta = state.ctaTitle {
                    Button {
                        Haptics.light()
                        onCTA()
                    } label: {
                        HStack {
                            Image(systemName: state.icon)
                            Text(cta)
                        }
                    }
                    .buttonStyle(DS.PrimaryButton())
                    .accessibilityHint("Opens budget setup")
                }
            }
        }
    }
}
