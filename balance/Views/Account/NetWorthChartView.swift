import SwiftUI
import Charts

// MARK: - Net Worth Chart View

struct NetWorthChartView: View {
    
    @StateObject private var netWorthManager = NetWorthManager.shared
    @State private var selectedPeriod: ChartPeriod = .sixMonths
    
    enum ChartPeriod: String, CaseIterable {
        case threeMonths = "3M"
        case sixMonths = "6M"
        case oneYear = "1Y"
        case allTime = "All"
        var months: Int {
            switch self {
            case .threeMonths: return 3; case .sixMonths: return 6
            case .oneYear: return 12; case .allTime: return 60
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryHeader
                periodSelector
                netWorthLineChart
                breakdownBarChart
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .background(DS.Colors.bg.ignoresSafeArea())
        .navigationTitle("Net Worth")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await netWorthManager.fetchHistory(months: selectedPeriod.months)
            await netWorthManager.computeSummary()
        }
        .onChange(of: selectedPeriod) { _, newPeriod in
            Task { await netWorthManager.fetchHistory(months: newPeriod.months) }
        }
    }
    
    private var summaryHeader: some View {
        VStack(spacing: 6) {
            Text("Total Net Worth").font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)
            Text(fmtCurrency(netWorthManager.summary.netWorth))
                .font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(DS.Colors.text)
            let change = netWorthManager.summary.changeFromLastMonth
            if change != 0 {
                HStack(spacing: 4) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right").font(.system(size: 11, weight: .bold))
                    Text("\(fmtCurrency(abs(change))) this month").font(DS.Typography.body)
                }.foregroundStyle(change >= 0 ? DS.Colors.positive : DS.Colors.danger)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 16)
    }
    
    private var periodSelector: some View {
        HStack(spacing: 0) {
            ForEach(ChartPeriod.allCases, id: \.self) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedPeriod = period }
                } label: {
                    Text(period.rawValue)
                        .font(DS.Typography.body.weight(.medium))
                        .foregroundStyle(selectedPeriod == period ? Color.white : DS.Colors.subtext)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(selectedPeriod == period ? DS.Colors.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(3)
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        
    }
    
    private var netWorthLineChart: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Net Worth Over Time").font(DS.Typography.section).foregroundStyle(DS.Colors.text)
                if netWorthManager.historyDataPoints.isEmpty {
                    emptyPlaceholder
                } else if #available(iOS 16.0, *) {
                    Chart(netWorthManager.historyDataPoints) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Net Worth", p.netWorth))
                            .interpolationMethod(.catmullRom).foregroundStyle(DS.Colors.accent).lineStyle(StrokeStyle(lineWidth: 2.5))
                        AreaMark(x: .value("Date", p.date), y: .value("Net Worth", p.netWorth))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(colors: [DS.Colors.accent.opacity(0.25), DS.Colors.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    }
                    .chartYAxis { AxisMarks(position: .leading) { v in AxisValueLabel { if let a = v.as(Double.self) { Text(fmtCompact(a)).font(.system(size: 10)).foregroundStyle(DS.Colors.subtext) } } } }
                    .chartXAxis { AxisMarks(values: .stride(by: .month)) { v in AxisValueLabel { if let d = v.as(Date.self) { Text(d, format: .dateTime.month(.abbreviated)).font(.system(size: 10)).foregroundStyle(DS.Colors.subtext) } } } }
                    .frame(height: 200)
                }
            }
        }
    }
    
    private var breakdownBarChart: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Assets vs Liabilities").font(DS.Typography.section).foregroundStyle(DS.Colors.text)
                if netWorthManager.historyDataPoints.isEmpty {
                    emptyPlaceholder
                } else if #available(iOS 16.0, *) {
                    Chart {
                        ForEach(netWorthManager.historyDataPoints) { p in
                            BarMark(x: .value("Date", p.date, unit: .month), y: .value("Amount", p.totalAssets))
                                .foregroundStyle(DS.Colors.positive.opacity(0.8)).cornerRadius(3)
                            BarMark(x: .value("Date", p.date, unit: .month), y: .value("Amount", p.totalLiabilities))
                                .foregroundStyle(DS.Colors.danger.opacity(0.8)).cornerRadius(3)
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading) { v in AxisValueLabel { if let a = v.as(Double.self) { Text(fmtCompact(a)).font(.system(size: 10)).foregroundStyle(DS.Colors.subtext) } } } }
                    .frame(height: 180)
                    
                    HStack(spacing: 14) {
                        HStack(spacing: 5) { Circle().fill(DS.Colors.positive).frame(width: 7, height: 7); Text("Assets").font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext) }
                        HStack(spacing: 5) { Circle().fill(DS.Colors.danger).frame(width: 7, height: 7); Text("Liabilities").font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext) }
                    }
                }
            }
        }
    }
    
    private var emptyPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.title2).foregroundStyle(DS.Colors.subtext.opacity(0.3))
            Text("Not enough data yet").font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)
        }.frame(maxWidth: .infinity).frame(height: 150)
    }
    
    private func fmtCurrency(_ value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencyCode = UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    private func fmtCompact(_ value: Double) -> String {
        let s = DS.Format.currencySymbol(); let a = abs(value)
        if a >= 1_000_000 { return String(format: "%@%.1fM", s, value / 1_000_000) }
        if a >= 1_000 { return String(format: "%@%.0fK", s, value / 1_000) }
        return String(format: "%@%.0f", s, value)
    }
}
