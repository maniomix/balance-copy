import SwiftUI

// MARK: - Charts KPI Strip

struct ChartsKPIStrip: View {
    let kpi: ChartsKPI
    let range: ChartRange
    let onTap: (ChartsKPIPill) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ChartsKPIPill.allCases, id: \.self) { pill in
                    KPIPillView(pill: pill, kpi: kpi, range: range) {
                        Haptics.light()
                        onTap(pill)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

enum ChartsKPIPill: CaseIterable, Hashable {
    case totalSpent
    case average
    case delta
    case biggestCategory

    var scrollAnchor: String {
        switch self {
        case .totalSpent, .average, .delta: return "chart.trend"
        case .biggestCategory: return "chart.category"
        }
    }
}

// MARK: - Pill

private struct KPIPillView: View {
    let pill: ChartsKPIPill
    let kpi: ChartsKPI
    let range: ChartRange
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.subtext)
                        .textCase(.uppercase)
                        .kerning(0.4)
                }

                Text(primaryValue)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let sub = subValue {
                    Text(sub)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(subTint)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minWidth: 130, alignment: .leading)
            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Colors.grid.opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(primaryValue). \(subValue ?? "")")
        .accessibilityHint("Double-tap to jump to related chart")
    }

    private var title: String {
        switch pill {
        case .totalSpent: return "Spent"
        case .average: return "Avg \(range.granularity.unitShort)"
        case .delta: return "vs Prev"
        case .biggestCategory: return "Top Category"
        }
    }

    private var iconName: String {
        switch pill {
        case .totalSpent: return "creditcard.fill"
        case .average: return "chart.bar.fill"
        case .delta: return kpi.spentDeltaRatio >= 0 ? "arrow.up.right" : "arrow.down.right"
        case .biggestCategory: return "circle.grid.2x2.fill"
        }
    }

    private var tint: Color {
        switch pill {
        case .totalSpent: return DS.Colors.accent
        case .average: return DS.Colors.accent
        case .delta: return kpi.spentDeltaRatio > 0.05 ? DS.Colors.danger : (kpi.spentDeltaRatio < -0.05 ? DS.Colors.positive : DS.Colors.subtext)
        case .biggestCategory: return kpi.biggestCategory?.tint ?? DS.Colors.accent
        }
    }

    private var primaryValue: String {
        switch pill {
        case .totalSpent:
            return kpi.totalSpent.currencyFormatted(showDecimal: false)
        case .average:
            return kpi.averagePerBucket.currencyFormatted(showDecimal: false)
        case .delta:
            guard kpi.previousTotalSpent > 0 else { return "—" }
            let pct = Int((kpi.spentDeltaRatio * 100).rounded())
            let sign = pct > 0 ? "+" : ""
            return "\(sign)\(pct)%"
        case .biggestCategory:
            return kpi.biggestCategory?.title ?? "—"
        }
    }

    private var subValue: String? {
        switch pill {
        case .totalSpent:
            guard kpi.transactionCount > 0 else { return nil }
            return "\(kpi.transactionCount) tx"
        case .average:
            return "per \(range.granularity.unitLong)"
        case .delta:
            guard kpi.previousTotalSpent > 0 else { return "no prior data" }
            let diff = kpi.totalSpent - kpi.previousTotalSpent
            let absDiff = abs(diff).currencyFormatted(showDecimal: false)
            return diff >= 0 ? "+\(absDiff)" : "−\(absDiff)"
        case .biggestCategory:
            guard kpi.biggestCategoryAmount > 0 else { return nil }
            return kpi.biggestCategoryAmount.currencyFormatted(showDecimal: false)
        }
    }

    private var subTint: Color {
        switch pill {
        case .delta:
            return kpi.spentDeltaRatio > 0.05 ? DS.Colors.danger : (kpi.spentDeltaRatio < -0.05 ? DS.Colors.positive : DS.Colors.subtext)
        default:
            return DS.Colors.subtext
        }
    }
}

private extension ChartGranularity {
    var unitShort: String {
        switch self {
        case .daily: return "Day"
        case .weekly: return "Week"
        case .monthly: return "Month"
        }
    }
    var unitLong: String {
        switch self {
        case .daily: return "day"
        case .weekly: return "week"
        case .monthly: return "month"
        }
    }
}
