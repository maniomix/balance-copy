import SwiftUI
import UIKit

// MARK: - Static export layout used by ImageRenderer

struct ChartsExportRender: View {
    let store: Store
    let range: ChartRange

    private var snapshot: ChartsAnalytics.Snapshot {
        ChartsAnalytics.shared.snapshot(store: store, range: range, now: store.selectedMonth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            kpiGrid
            trendCard
            categoryCard
            cashflowCard
            footer
        }
        .padding(.horizontal, 16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Centmond · Analytics")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
            Text(range.displayName)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
        }
    }

    private var kpiGrid: some View {
        let kpi = snapshot.kpi
        return HStack(spacing: 8) {
            exportPill(label: "Spent", value: kpi.totalSpent.currencyFormatted(showDecimal: false), tint: DS.Colors.accent)
            exportPill(label: "Income", value: kpi.totalIncome.currencyFormatted(showDecimal: false), tint: DS.Colors.positive)
            exportPill(label: "Net", value: kpi.netSavings.currencyFormatted(showDecimal: false), tint: kpi.netSavings >= 0 ? DS.Colors.positive : DS.Colors.danger)
        }
    }

    private func exportPill(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
                .kerning(0.4)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 10))
    }

    private var trendCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Spending Trend")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                SpendingTrendChartV2(store: store, range: range)
            }
        }
    }

    private var categoryCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Category Breakdown")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                CategoryBreakdownChartV2(store: store, range: range)
            }
        }
    }

    private var cashflowCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cashflow")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                CashflowChartV2(store: store, range: range)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text("Generated \(Date.now.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
        }
    }
}

// MARK: - Share Sheet wrapper

struct ChartsShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
