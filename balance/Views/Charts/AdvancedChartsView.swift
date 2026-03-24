import SwiftUI
import Charts

// MARK: - Advanced Charts View

struct AdvancedChartsView: View {
    @Binding var store: Store
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPeriod: ChartPeriod = .last3Months
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    periodSelector
                    spendingTrendCard
                    categoryPieCard
                    incomeExpenseCard
                    monthlyComparisonCard
                    
                    Spacer(minLength: 30)
                }
                .padding(.vertical)
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle("Charts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
            }
        }
    }
    
    // MARK: - Period Selector
    
    private var periodSelector: some View {
        HStack(spacing: 6) {
            ForEach(ChartPeriod.allCases, id: \.self) { period in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedPeriod = period
                    }
                    Haptics.selection()
                } label: {
                    Text(period.displayName)
                        .font(.system(size: 13, weight: selectedPeriod == period ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(selectedPeriod == period ? Color(uiColor: .systemBackground) : DS.Colors.subtext)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            selectedPeriod == period
                            ? AnyShapeStyle(Color(uiColor: .label))
                            : AnyShapeStyle(DS.Colors.surface2),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Spending Trend
    
    private var spendingTrendCard: some View {
        chartCard(icon: "chart.line.uptrend.xyaxis", title: "Spending Trend") {
            SpendingTrendChart(store: store, period: selectedPeriod)
                .frame(height: 200)
        }
    }
    
    // MARK: - Category Pie
    
    private var categoryPieCard: some View {
        chartCard(icon: "chart.pie.fill", title: "Category Breakdown") {
            CategoryPieChart(store: store, period: selectedPeriod)
        }
    }
    
    // MARK: - Income vs Expense
    
    private var incomeExpenseCard: some View {
        chartCard(icon: "chart.bar.fill", title: "Income vs Expense") {
            IncomeExpenseChart(store: store, period: selectedPeriod)
                .frame(height: 200)
        }
    }
    
    // MARK: - Monthly Comparison
    
    private var monthlyComparisonCard: some View {
        chartCard(icon: "chart.bar.xaxis", title: "Budget vs Spent") {
            MonthlyComparisonChart(store: store, period: selectedPeriod)
                .frame(height: 220)
        }
    }
    
    // MARK: - Chart Card Template
    
    private func chartCard<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                    
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                    
                    Spacer()
                }
                
                content()
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Chart Period

enum ChartPeriod: CaseIterable {
    case last3Months
    case last6Months
    case thisYear
    
    var displayName: String {
        switch self {
        case .last3Months: return "3 Months"
        case .last6Months: return "6 Months"
        case .thisYear: return "This Year"
        }
    }
    
    var monthsCount: Int {
        switch self {
        case .last3Months: return 3
        case .last6Months: return 6
        case .thisYear: return 12
        }
    }
}

// MARK: - Spending Trend Chart

struct SpendingTrendChart: View {
    let store: Store
    let period: ChartPeriod
    
    var data: [MonthData] {
        let calendar = Calendar.current
        let now = Date()
        var result: [MonthData] = []
        
        for i in (0..<period.monthsCount).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            let spent = store.spent(for: date)
            let monthName = shortMonth(date)
            result.append(MonthData(month: monthName, amount: spent, date: date))
        }
        
        return result
    }
    
    var body: some View {
        if data.isEmpty || data.allSatisfy({ $0.amount == 0 }) {
            emptyChartView
        } else {
            Chart(data) { item in
                AreaMark(
                    x: .value("Month", item.month),
                    y: .value("Amount", Double(item.amount) / 100.0)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [DS.Colors.accent.opacity(0.2), DS.Colors.accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
                
                LineMark(
                    x: .value("Month", item.month),
                    y: .value("Amount", Double(item.amount) / 100.0)
                )
                .foregroundStyle(DS.Colors.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
                
                PointMark(
                    x: .value("Month", item.month),
                    y: .value("Amount", Double(item.amount) / 100.0)
                )
                .foregroundStyle(DS.Colors.accent)
                .symbolSize(30)
            }
            .chartStyle()
        }
    }
}

// MARK: - Category Pie Chart

struct CategoryPieChart: View {
    let store: Store
    let period: ChartPeriod
    
    var data: [CategoryData] {
        let calendar = Calendar.current
        let now = Date()
        var categoryTotals: [Category: Int] = [:]
        
        for i in 0..<period.monthsCount {
            guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            
            let transactions = store.transactions.filter { tx in
                calendar.isDate(tx.date, equalTo: date, toGranularity: .month) && tx.type == .expense
            }
            
            for tx in transactions {
                categoryTotals[tx.category, default: 0] += tx.amount
            }
        }
        
        return categoryTotals
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { CategoryData(category: $0.key, amount: $0.value) }
    }
    
    private var totalAmount: Int {
        data.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        if data.isEmpty {
            emptyChartView
        } else {
            VStack(spacing: 20) {
                // Donut chart with manual colors
                Chart(data) { item in
                    SectorMark(
                        angle: .value("Amount", Double(item.amount)),
                        innerRadius: .ratio(0.55),
                        angularInset: 1.5
                    )
                    .cornerRadius(3)
                    .foregroundStyle(item.category.tint)
                }
                .chartLegend(.hidden)
                .frame(height: 180)
                
                // Custom legend with actual category colors
                VStack(spacing: 6) {
                    ForEach(data) { item in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(item.category.tint)
                                .frame(width: 14, height: 14)
                            
                            Text(item.category.title)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(DS.Colors.text)
                            
                            Spacer()
                            
                            // Percentage
                            let pct = totalAmount > 0 ? Double(item.amount) / Double(totalAmount) * 100 : 0
                            Text("\(Int(pct))%")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.Colors.subtext)
                                .frame(width: 36, alignment: .trailing)
                            
                            Text(DS.Format.money(item.amount))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.text)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
    }
}

// MARK: - Income vs Expense Chart

struct IncomeExpenseChart: View {
    let store: Store
    let period: ChartPeriod
    
    var data: [IncomeExpenseData] {
        let calendar = Calendar.current
        let now = Date()
        var result: [IncomeExpenseData] = []
        
        for i in (0..<period.monthsCount).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            
            let income = store.income(for: date)
            let expense = store.spent(for: date)
            let monthName = shortMonth(date)
            
            result.append(IncomeExpenseData(month: monthName, income: income, expense: expense))
        }
        
        return result
    }
    
    var body: some View {
        if data.isEmpty || data.allSatisfy({ $0.income == 0 && $0.expense == 0 }) {
            emptyChartView
        } else {
            VStack(spacing: 12) {
                Chart(data) { item in
                    BarMark(
                        x: .value("Month", item.month),
                        y: .value("Amount", Double(item.income) / 100.0)
                    )
                    .foregroundStyle(DS.Colors.positive.opacity(0.8))
                    .cornerRadius(4)
                    .position(by: .value("Type", "Income"))
                    
                    BarMark(
                        x: .value("Month", item.month),
                        y: .value("Amount", Double(item.expense) / 100.0)
                    )
                    .foregroundStyle(DS.Colors.danger.opacity(0.7))
                    .cornerRadius(4)
                    .position(by: .value("Type", "Expense"))
                }
                .chartStyle()
                
                // Inline legend
                HStack(spacing: 20) {
                    legendDot(color: DS.Colors.positive, label: "Income")
                    legendDot(color: DS.Colors.danger, label: "Expense")
                }
            }
        }
    }
}

// MARK: - Monthly Comparison Chart

struct MonthlyComparisonChart: View {
    let store: Store
    let period: ChartPeriod
    
    var data: [MonthComparisonData] {
        let calendar = Calendar.current
        let now = Date()
        var result: [MonthComparisonData] = []
        
        for i in (0..<period.monthsCount).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            
            let budget = store.budget(for: date)
            let spent = store.spent(for: date)
            let monthName = shortMonth(date)
            
            result.append(MonthComparisonData(month: monthName, budget: budget, spent: spent))
        }
        
        return result
    }
    
    var body: some View {
        if data.isEmpty || data.allSatisfy({ $0.budget == 0 && $0.spent == 0 }) {
            emptyChartView
        } else {
            VStack(spacing: 12) {
                Chart(data) { item in
                    BarMark(
                        x: .value("Month", item.month),
                        y: .value("Amount", Double(item.budget) / 100.0)
                    )
                    .foregroundStyle(DS.Colors.accent.opacity(0.3))
                    .cornerRadius(4)
                    .position(by: .value("Type", "Budget"))
                    
                    BarMark(
                        x: .value("Month", item.month),
                        y: .value("Amount", Double(item.spent) / 100.0)
                    )
                    .foregroundStyle(item.spent > item.budget ? DS.Colors.danger.opacity(0.8) : DS.Colors.positive.opacity(0.8))
                    .cornerRadius(4)
                    .position(by: .value("Type", "Spent"))
                }
                .chartStyle()
                
                HStack(spacing: 20) {
                    legendDot(color: DS.Colors.accent.opacity(0.5), label: "Budget")
                    legendDot(color: DS.Colors.positive, label: "Under")
                    legendDot(color: DS.Colors.danger, label: "Over")
                }
            }
        }
    }
}

// MARK: - Data Models

struct MonthData: Identifiable {
    let id = UUID()
    let month: String
    let amount: Int
    let date: Date
}

struct CategoryData: Identifiable {
    let id = UUID()
    let category: Category
    let amount: Int
}

struct IncomeExpenseData: Identifiable {
    let id = UUID()
    let month: String
    let income: Int
    let expense: Int
}

struct MonthComparisonData: Identifiable {
    let id = UUID()
    let month: String
    let budget: Int
    let spent: Int
}

// MARK: - Helpers

private func shortMonth(_ date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM"
    return fmt.string(from: date)
}

private var emptyChartView: some View {
    VStack(spacing: 8) {
        Image(systemName: "chart.bar")
            .font(.system(size: 28))
            .foregroundStyle(DS.Colors.subtext.opacity(0.3))
        
        Text("No data for this period")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(DS.Colors.subtext)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 120)
}

private func legendDot(color: Color, label: String) -> some View {
    HStack(spacing: 6) {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
        
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(DS.Colors.subtext)
    }
}

// MARK: - Chart Style Extension

extension View {
    func chartStyle() -> some View {
        self
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine()
                        .foregroundStyle(DS.Colors.grid.opacity(0.5))
                    AxisValueLabel()
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                        .foregroundStyle(DS.Colors.grid.opacity(0.3))
                    AxisValueLabel()
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
    }
}
