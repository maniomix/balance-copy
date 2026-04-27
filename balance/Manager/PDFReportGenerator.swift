import Foundation
import UIKit

// ============================================================
// MARK: - PDF Report Generator
// ============================================================
//
// Production PDF generation for financial reports.
// Uses UIGraphicsPDFRenderer for native iOS PDF creation.
//
// Report Types:
//   1. Monthly Summary — budget, spending, categories, transactions
//   2. Annual Summary — 12-month overview, trends, totals
//   3. Category Spending — deep dive into category breakdown
//   4. Cash Flow — income vs expenses flow
//   5. Net Worth Summary — accounts and net worth snapshot
//
// All amounts are in cents (Int). Currency defaults to EUR.
// ============================================================

enum ReportType: String, CaseIterable, Identifiable {
    case monthlySummary = "monthly"
    case annualSummary = "annual"
    case categorySpending = "category"
    case cashFlow = "cashflow"
    case netWorth = "networth"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monthlySummary: return "Monthly Summary"
        case .annualSummary: return "Annual Summary"
        case .categorySpending: return "Category Spending"
        case .cashFlow: return "Cash Flow"
        case .netWorth: return "Net Worth"
        }
    }

    var icon: String {
        switch self {
        case .monthlySummary: return "calendar"
        case .annualSummary: return "chart.bar.fill"
        case .categorySpending: return "chart.pie.fill"
        case .cashFlow: return "arrow.left.arrow.right"
        case .netWorth: return "building.columns.fill"
        }
    }

    var description: String {
        switch self {
        case .monthlySummary: return "Budget, spending breakdown, and transactions for a single month"
        case .annualSummary: return "12-month overview with trends and yearly totals"
        case .categorySpending: return "Detailed spending by category with comparisons"
        case .cashFlow: return "Income vs expenses over the selected period"
        case .netWorth: return "Account balances and net worth snapshot"
        }
    }
}

struct PDFReportGenerator {

    // MARK: - Page Constants

    private static let pageWidth: CGFloat = 612  // US Letter
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 50
    private static let contentWidth: CGFloat = 512 // pageWidth - 2*margin

    // MARK: - Colors

    private static let brandColor = UIColor(red: 0.4, green: 0.494, blue: 0.918, alpha: 1.0) // #667EEA
    private static let positiveColor = UIColor(red: 0.18, green: 0.836, blue: 0.451, alpha: 1.0) // #2ED573
    private static let dangerColor = UIColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0) // #FF3B30
    private static let warningColor = UIColor(red: 1.0, green: 0.624, blue: 0.039, alpha: 1.0) // #FF9F0A
    private static let textColor = UIColor.black
    private static let subtextColor = UIColor.darkGray
    private static let lightBg = UIColor(white: 0.96, alpha: 1.0)

    // MARK: - Fonts

    private static let titleFont = UIFont.systemFont(ofSize: 24, weight: .bold)
    private static let headingFont = UIFont.systemFont(ofSize: 16, weight: .bold)
    private static let subheadingFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
    private static let bodyFont = UIFont.systemFont(ofSize: 11, weight: .regular)
    private static let bodyBoldFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
    private static let captionFont = UIFont.systemFont(ofSize: 9, weight: .regular)
    private static let numberFont = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    private static let bigNumberFont = UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .bold)

    // MARK: - Public Interface

    static func generate(
        type: ReportType,
        store: Store,
        startDate: Date,
        endDate: Date,
        accounts: [Account] = [],
        netWorth: Double = 0
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let currency = UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"

        return renderer.pdfData { ctx in
            switch type {
            case .monthlySummary:
                drawMonthlySummary(ctx: ctx, pageRect: pageRect, store: store, date: startDate, currency: currency)
            case .annualSummary:
                drawAnnualSummary(ctx: ctx, pageRect: pageRect, store: store, year: Calendar.current.component(.year, from: startDate), currency: currency)
            case .categorySpending:
                drawCategoryReport(ctx: ctx, pageRect: pageRect, store: store, start: startDate, end: endDate, currency: currency)
            case .cashFlow:
                drawCashFlowReport(ctx: ctx, pageRect: pageRect, store: store, start: startDate, end: endDate, currency: currency)
            case .netWorth:
                drawNetWorthReport(ctx: ctx, pageRect: pageRect, accounts: accounts, netWorth: netWorth, currency: currency)
            }
        }
    }

    // =====================================================================
    // MARK: - 1. Monthly Summary Report
    // =====================================================================

    private static func drawMonthlySummary(ctx: UIGraphicsPDFRendererContext, pageRect: CGRect, store: Store, date: Date, currency: String) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        guard let monthStart = cal.date(from: comps),
              let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return }

        let monthTx = store.transactions.filter { $0.date >= monthStart && $0.date < monthEnd }
        let expenses = monthTx.filter { $0.type == .expense && !$0.isTransfer }
        let income = monthTx.filter { $0.type == .income && !$0.isTransfer }

        let totalExpense = expenses.reduce(0) { $0 + $1.amount }
        let totalIncome = income.reduce(0) { $0 + $1.amount }
        let budget = store.budgetTotal

        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        let monthName = fmt.string(from: date)

        // Category breakdown
        var catMap: [String: Int] = [:]
        for tx in expenses { catMap[tx.category.title, default: 0] += tx.amount }
        let catSorted = catMap.sorted { $0.value > $1.value }

        // Page 1
        ctx.beginPage()
        var y = drawHeader(ctx: ctx.cgContext, pageRect: pageRect, title: "Monthly Summary", subtitle: monthName)

        // KPI cards
        y = drawKPIRow(ctx: ctx.cgContext, y: y, items: [
            ("Budget", formatCurrency(budget, currency), brandColor),
            ("Spent", formatCurrency(totalExpense, currency), dangerColor),
            ("Remaining", formatCurrency(budget - totalExpense, currency), (budget - totalExpense) >= 0 ? positiveColor : dangerColor),
            ("Income", formatCurrency(totalIncome, currency), positiveColor)
        ])

        y += 20

        // Spending pace
        let daysInMonth = cal.range(of: .day, in: .month, for: date)?.count ?? 30
        let dayOfMonth = cal.component(.day, from: Date())
        let dailyAvg = dayOfMonth > 0 ? totalExpense / dayOfMonth : 0
        y = drawInfoRow(ctx: ctx.cgContext, y: y, label: "Daily Average Spending", value: "\(formatCurrency(dailyAvg, currency)) / day")
        let projectedTotal = dailyAvg * daysInMonth
        y = drawInfoRow(ctx: ctx.cgContext, y: y, label: "Projected Month Total", value: formatCurrency(projectedTotal, currency))
        y += 10

        // Category breakdown
        y = drawSectionTitle(ctx: ctx.cgContext, y: y, title: "Spending by Category")
        y = drawCategoryTable(ctx: ctx.cgContext, y: y, categories: catSorted, total: totalExpense, currency: currency, pageRect: pageRect, pdfCtx: ctx)

        // Transactions (Page 2 if needed)
        y = checkPageBreak(ctx: ctx, y: y, pageRect: pageRect, needed: 100)
        y = drawSectionTitle(ctx: ctx.cgContext, y: y, title: "Transactions (\(monthTx.count))")
        y = drawTransactionTable(ctx: ctx, y: y, transactions: Array(monthTx.sorted { $0.date > $1.date }.prefix(30)), currency: currency, pageRect: pageRect)

        drawFooter(ctx: ctx.cgContext, pageRect: pageRect)
    }

    // =====================================================================
    // MARK: - 2. Annual Summary Report
    // =====================================================================

    private static func drawAnnualSummary(ctx: UIGraphicsPDFRendererContext, pageRect: CGRect, store: Store, year: Int, currency: String) {
        let cal = Calendar.current

        ctx.beginPage()
        var y = drawHeader(ctx: ctx.cgContext, pageRect: pageRect, title: "Annual Summary", subtitle: "\(year)")

        // Monthly breakdown
        var monthlyExpenses: [(String, Int)] = []
        var monthlyIncome: [(String, Int)] = []
        var totalYearExpense = 0
        var totalYearIncome = 0

        let monthFmt = DateFormatter()
        monthFmt.dateFormat = "MMM"

        for month in 1...12 {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 1
            guard let start = cal.date(from: comps),
                  let end = cal.date(byAdding: .month, value: 1, to: start) else { continue }

            let monthTx = store.transactions.filter { $0.date >= start && $0.date < end }
            let exp = monthTx.filter { $0.type == .expense && !$0.isTransfer }.reduce(0) { $0 + $1.amount }
            let inc = monthTx.filter { $0.type == .income && !$0.isTransfer }.reduce(0) { $0 + $1.amount }

            let label = monthFmt.string(from: start)
            monthlyExpenses.append((label, exp))
            monthlyIncome.append((label, inc))
            totalYearExpense += exp
            totalYearIncome += inc
        }

        // KPI
        y = drawKPIRow(ctx: ctx.cgContext, y: y, items: [
            ("Total Income", formatCurrency(totalYearIncome, currency), positiveColor),
            ("Total Expenses", formatCurrency(totalYearExpense, currency), dangerColor),
            ("Net Savings", formatCurrency(totalYearIncome - totalYearExpense, currency), (totalYearIncome - totalYearExpense) >= 0 ? positiveColor : dangerColor),
            ("Avg Monthly", formatCurrency(totalYearExpense / 12, currency), brandColor)
        ])

        y += 20

        // Monthly table
        y = drawSectionTitle(ctx: ctx.cgContext, y: y, title: "Month-by-Month Breakdown")

        // Table header
        let cols: [(String, CGFloat)] = [("Month", 60), ("Income", 100), ("Expenses", 100), ("Net", 100), ("Savings %", 80)]
        y = drawTableHeader(ctx: ctx.cgContext, y: y, columns: cols)

        for i in 0..<12 {
            let (label, exp) = monthlyExpenses[i]
            let (_, inc) = monthlyIncome[i]
            let net = inc - exp
            let savingsRate = inc > 0 ? Double(net) / Double(inc) * 100 : 0

            let values = [
                label,
                formatCurrency(inc, currency),
                formatCurrency(exp, currency),
                formatCurrency(net, currency),
                String(format: "%.1f%%", savingsRate)
            ]

            let rowColor: UIColor? = net < 0 ? UIColor(red: 1, green: 0.9, blue: 0.9, alpha: 1) : nil
            y = drawTableRow(ctx: ctx.cgContext, y: y, columns: cols, values: values, highlight: rowColor)
            y = checkPageBreak(ctx: ctx, y: y, pageRect: pageRect, needed: 25)
        }

        // Annual category breakdown
        y = checkPageBreak(ctx: ctx, y: y, pageRect: pageRect, needed: 200)
        y += 15

        let yearTx = store.transactions.filter {
            cal.component(.year, from: $0.date) == year && $0.type == .expense && !$0.isTransfer
        }
        var catMap: [String: Int] = [:]
        for tx in yearTx { catMap[tx.category.title, default: 0] += tx.amount }
        let catSorted = catMap.sorted { $0.value > $1.value }

        y = drawSectionTitle(ctx: ctx.cgContext, y: y, title: "Annual Spending by Category")
        y = drawCategoryTable(ctx: ctx.cgContext, y: y, categories: catSorted, total: totalYearExpense, currency: currency, pageRect: pageRect, pdfCtx: ctx)

        drawFooter(ctx: ctx.cgContext, pageRect: pageRect)
    }

    // =====================================================================
    // MARK: - 3. Category Spending Report
    // =====================================================================

    private static func drawCategoryReport(ctx: UIGraphicsPDFRendererContext, pageRect: CGRect, store: Store, start: Date, end: Date, currency: String) {
        let expenses = store.transactions.filter { $0.type == .expense && !$0.isTransfer && $0.date >= start && $0.date < end }

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "MMM d, yyyy"

        ctx.beginPage()
        var y = drawHeader(ctx: ctx.cgContext, pageRect: pageRect, title: "Category Spending Report", subtitle: "\(dateFmt.string(from: start)) – \(dateFmt.string(from: end))")

        let totalExpense = expenses.reduce(0) { $0 + $1.amount }

        y = drawKPIRow(ctx: ctx.cgContext, y: y, items: [
            ("Total Spending", formatCurrency(totalExpense, currency), dangerColor),
            ("Transactions", "\(expenses.count)", brandColor),
            ("Categories", "\(Set(expenses.map { $0.category.title }).count)", brandColor),
            ("Period", "\(Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) days", subtextColor)
        ])

        y += 20

        // Group by category
        var catMap: [String: (total: Int, count: Int, txs: [Transaction])] = [:]
        for tx in expenses {
            let key = tx.category.title
            var entry = catMap[key] ?? (0, 0, [])
            entry.total += tx.amount
            entry.count += 1
            entry.txs.append(tx)
            catMap[key] = entry
        }

        let sorted = catMap.sorted { $0.value.total > $1.value.total }

        // Detailed category table
        y = drawSectionTitle(ctx: ctx.cgContext, y: y, title: "Category Breakdown")

        let cols: [(String, CGFloat)] = [("Category", 120), ("Amount", 100), ("% of Total", 80), ("# Txns", 60), ("Avg per Txn", 100)]
        y = drawTableHeader(ctx: ctx.cgContext, y: y, columns: cols)

        for (name, data) in sorted {
            let pct = totalExpense > 0 ? Double(data.total) / Double(totalExpense) * 100 : 0
            let avg = data.count > 0 ? data.total / data.count : 0
            let values = [
                name,
                formatCurrency(data.total, currency),
                String(format: "%.1f%%", pct),
                "\(data.count)",
                formatCurrency(avg, currency)
            ]
            y = drawTableRow(ctx: ctx.cgContext, y: y, columns: cols, values: values, highlight: nil)
            y = checkPageBreak(ctx: ctx, y: y, pageRect: pageRect, needed: 25)
        }

        // Top category details
        for (name, data) in sorted.prefix(5) {
            y = checkPageBreak(ctx: ctx, y: y, pageRect: pageRect, needed: 120)
            y += 15
            y = drawSectionTitle(ctx: ctx.cgContext, y: y, title: "\(name) — Top Transactions")

            let topTxs = data.txs.sorted { $0.amount > $1.amount }.prefix(8)
            y = drawTransactionTable(ctx: ctx, y: y, transactions: Array(topTxs), currency: currency, pageRect: pageRect)
        }

        drawFooter(ctx: ctx.cgContext, pageRect: pageRect)
    }

    // =====================================================================
    // MARK: - 4. Cash Flow Report
    // =====================================================================

    private static func drawCashFlowReport(ctx: UIGraphicsPDFRendererContext, pageRect: CGRect, store: Store, start: Date, end: Date, currency: String) {
        let cal = Calendar.current
        let txs = store.transactions.filter { $0.date >= start && $0.date < end }

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "MMM d, yyyy"

        ctx.beginPage()
        var y = drawHeader(ctx: ctx.cgContext, pageRect: pageRect, title: "Cash Flow Report", subtitle: "\(dateFmt.string(from: start)) – \(dateFmt.string(from: end))")

        let totalIncome = txs.filter { $0.type == .income && !$0.isTransfer }.reduce(0) { $0 + $1.amount }
        let totalExpense = txs.filter { $0.type == .expense && !$0.isTransfer }.reduce(0) { $0 + $1.amount }
        let netFlow = totalIncome - totalExpense

        y = drawKPIRow(ctx: ctx.cgContext, y: y, items: [
            ("Income", formatCurrency(totalIncome, currency), positiveColor),
            ("Expenses", formatCurrency(totalExpense, currency), dangerColor),
            ("Net Flow", formatCurrency(netFlow, currency), netFlow >= 0 ? positiveColor : dangerColor),
            ("Flow Ratio", totalExpense > 0 ? String(format: "%.1f%%", Double(totalIncome) / Double(totalExpense) * 100) : "—", brandColor)
        ])

        y += 20

        // Monthly cash flow table
        y = drawSectionTitle(ctx: ctx.cgContext, y: y, title: "Monthly Cash Flow")

        // Collect months in range
        var monthData: [(label: String, income: Int, expense: Int)] = []
        var current = start
        let monthFmt = DateFormatter()
        monthFmt.dateFormat = "MMM yyyy"

        while current < end {
            guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: current)),
                  let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { break }
            let effectiveEnd = min(monthEnd, end)
            let monthTx = txs.filter { $0.date >= current && $0.date < effectiveEnd }

            let inc = monthTx.filter { $0.type == .income && !$0.isTransfer }.reduce(0) { $0 + $1.amount }
            let exp = monthTx.filter { $0.type == .expense && !$0.isTransfer }.reduce(0) { $0 + $1.amount }

            monthData.append((monthFmt.string(from: current), inc, exp))
            current = monthEnd
        }

        let cols: [(String, CGFloat)] = [("Month", 100), ("Income", 110), ("Expenses", 110), ("Net", 110)]
        y = drawTableHeader(ctx: ctx.cgContext, y: y, columns: cols)

        for data in monthData {
            let net = data.income - data.expense
            let values = [
                data.label,
                formatCurrency(data.income, currency),
                formatCurrency(data.expense, currency),
                formatCurrency(net, currency)
            ]
            let rowColor: UIColor? = net < 0 ? UIColor(red: 1, green: 0.92, blue: 0.92, alpha: 1) : nil
            y = drawTableRow(ctx: ctx.cgContext, y: y, columns: cols, values: values, highlight: rowColor)
            y = checkPageBreak(ctx: ctx, y: y, pageRect: pageRect, needed: 25)
        }

        // Cash flow bar chart
        y = checkPageBreak(ctx: ctx, y: y, pageRect: pageRect, needed: 180)
        y += 15
        y = drawSectionTitle(ctx: ctx.cgContext, y: y, title: "Cash Flow Visualization")
        y = drawBarChart(ctx: ctx.cgContext, y: y, data: monthData)

        // Income sources
        y = checkPageBreak(ctx: ctx, y: y, pageRect: pageRect, needed: 100)
        y += 10
        y = drawSectionTitle(ctx: ctx.cgContext, y: y, title: "Income Transactions")
        let incomeTxs = txs.filter { $0.type == .income }.sorted { $0.date > $1.date }
        y = drawTransactionTable(ctx: ctx, y: y, transactions: Array(incomeTxs.prefix(15)), currency: currency, pageRect: pageRect)

        drawFooter(ctx: ctx.cgContext, pageRect: pageRect)
    }

    // =====================================================================
    // MARK: - 5. Net Worth Report
    // =====================================================================

    private static func drawNetWorthReport(ctx: UIGraphicsPDFRendererContext, pageRect: CGRect, accounts: [Account], netWorth: Double, currency: String) {
        ctx.beginPage()
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "MMMM d, yyyy"
        var y = drawHeader(ctx: ctx.cgContext, pageRect: pageRect, title: "Net Worth Summary", subtitle: dateFmt.string(from: Date()))

        let netWorthCents = Int(netWorth * 100)

        y = drawKPIRow(ctx: ctx.cgContext, y: y, items: [
            ("Net Worth", formatCurrency(netWorthCents, currency), netWorthCents >= 0 ? positiveColor : dangerColor),
            ("Accounts", "\(accounts.count)", brandColor),
            ("Assets", formatCurrency(Int(accounts.filter { $0.currentBalance >= 0 }.reduce(0) { $0 + $1.currentBalance } * 100), currency), positiveColor),
            ("Liabilities", formatCurrency(Int(abs(accounts.filter { $0.currentBalance < 0 }.reduce(0) { $0 + $1.currentBalance }) * 100), currency), dangerColor)
        ])

        y += 20

        // Accounts table
        y = drawSectionTitle(ctx: ctx.cgContext, y: y, title: "Account Balances")

        let cols: [(String, CGFloat)] = [("Account", 160), ("Type", 100), ("Balance", 120), ("% of Total", 80)]
        y = drawTableHeader(ctx: ctx.cgContext, y: y, columns: cols)

        let totalAbs = max(1.0, accounts.reduce(0) { $0 + abs($1.currentBalance) })

        for account in accounts.sorted(by: { $0.currentBalance > $1.currentBalance }) {
            let balCents = Int(account.currentBalance * 100)
            let pct = abs(account.currentBalance) / totalAbs * 100
            let values = [
                account.name,
                account.type.displayName,
                formatCurrency(balCents, currency),
                String(format: "%.1f%%", pct)
            ]
            let rowColor: UIColor? = account.currentBalance < 0 ? UIColor(red: 1, green: 0.92, blue: 0.92, alpha: 1) : nil
            y = drawTableRow(ctx: ctx.cgContext, y: y, columns: cols, values: values, highlight: rowColor)
            y = checkPageBreak(ctx: ctx, y: y, pageRect: pageRect, needed: 25)
        }

        // Summary
        y = checkPageBreak(ctx: ctx, y: y, pageRect: pageRect, needed: 80)
        y += 20
        y = drawSectionTitle(ctx: ctx.cgContext, y: y, title: "Summary")
        y = drawInfoRow(ctx: ctx.cgContext, y: y, label: "Total Assets", value: formatCurrency(Int(accounts.filter { $0.currentBalance >= 0 }.reduce(0) { $0 + $1.currentBalance } * 100), currency))
        y = drawInfoRow(ctx: ctx.cgContext, y: y, label: "Total Liabilities", value: formatCurrency(Int(abs(accounts.filter { $0.currentBalance < 0 }.reduce(0) { $0 + $1.currentBalance }) * 100), currency))
        y = drawInfoRow(ctx: ctx.cgContext, y: y, label: "Net Worth", value: formatCurrency(netWorthCents, currency))

        drawFooter(ctx: ctx.cgContext, pageRect: pageRect)
    }

    // =====================================================================
    // MARK: - Drawing Primitives
    // =====================================================================

    // MARK: Header

    private static func drawHeader(ctx: CGContext, pageRect: CGRect, title: String, subtitle: String) -> CGFloat {
        var y: CGFloat = margin

        // Brand bar
        ctx.setFillColor(brandColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pageRect.width, height: 6))

        // Logo text
        let logoAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: brandColor
        ]
        "CENTMOND".draw(at: CGPoint(x: margin, y: y), withAttributes: logoAttrs)
        y += 20

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: textColor
        ]
        title.draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
        y += 32

        // Subtitle
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: subtextColor
        ]
        subtitle.draw(at: CGPoint(x: margin, y: y), withAttributes: subAttrs)
        y += 22

        // Divider
        ctx.setStrokeColor(UIColor.lightGray.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: margin, y: y))
        ctx.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
        ctx.strokePath()
        y += 15

        return y
    }

    // MARK: Footer

    private static func drawFooter(ctx: CGContext, pageRect: CGRect) {
        let y = pageRect.height - 30
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .long
        dateFmt.timeStyle = .short

        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: captionFont,
            .foregroundColor: UIColor.lightGray
        ]
        "Generated \(dateFmt.string(from: Date())) • Centmond App".draw(
            at: CGPoint(x: margin, y: y),
            withAttributes: footerAttrs
        )
    }

    // MARK: KPI Row

    private static func drawKPIRow(ctx: CGContext, y: CGFloat, items: [(String, String, UIColor)]) -> CGFloat {
        let count = CGFloat(items.count)
        let gap: CGFloat = 10
        let cardWidth = (contentWidth - gap * (count - 1)) / count
        let cardHeight: CGFloat = 60

        for (i, item) in items.enumerated() {
            let x = margin + CGFloat(i) * (cardWidth + gap)
            let rect = CGRect(x: x, y: y, width: cardWidth, height: cardHeight)

            // Card background
            ctx.setFillColor(item.2.withAlphaComponent(0.06).cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(item.2.withAlphaComponent(0.2).cgColor)
            ctx.setLineWidth(0.5)
            ctx.stroke(rect)

            // Label
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: subtextColor
            ]
            item.0.draw(at: CGPoint(x: x + 8, y: y + 8), withAttributes: labelAttrs)

            // Value
            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold),
                .foregroundColor: item.2
            ]
            item.1.draw(at: CGPoint(x: x + 8, y: y + 28), withAttributes: valAttrs)
        }

        return y + cardHeight + 10
    }

    // MARK: Section Title

    private static func drawSectionTitle(ctx: CGContext, y: CGFloat, title: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: headingFont,
            .foregroundColor: textColor
        ]
        title.draw(at: CGPoint(x: margin, y: y), withAttributes: attrs)
        return y + 24
    }

    // MARK: Info Row

    private static func drawInfoRow(ctx: CGContext, y: CGFloat, label: String, value: String) -> CGFloat {
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: subtextColor]
        let valAttrs: [NSAttributedString.Key: Any] = [.font: bodyBoldFont, .foregroundColor: textColor]

        label.draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
        value.draw(at: CGPoint(x: margin + 200, y: y), withAttributes: valAttrs)

        return y + 20
    }

    // MARK: Table Header

    private static func drawTableHeader(ctx: CGContext, y: CGFloat, columns: [(String, CGFloat)]) -> CGFloat {
        let headerRect = CGRect(x: margin, y: y, width: contentWidth, height: 22)
        ctx.setFillColor(lightBg.cgColor)
        ctx.fill(headerRect)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: subtextColor
        ]

        var x = margin + 6
        for (title, width) in columns {
            title.uppercased().draw(at: CGPoint(x: x, y: y + 5), withAttributes: attrs)
            x += width
        }

        return y + 24
    }

    // MARK: Table Row

    private static func drawTableRow(ctx: CGContext, y: CGFloat, columns: [(String, CGFloat)], values: [String], highlight: UIColor?) -> CGFloat {
        if let bg = highlight {
            let rowRect = CGRect(x: margin, y: y, width: contentWidth, height: 20)
            ctx.setFillColor(bg.cgColor)
            ctx.fill(rowRect)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: textColor
        ]

        var x = margin + 6
        for (i, (_, width)) in columns.enumerated() {
            let val = i < values.count ? values[i] : ""
            val.draw(at: CGPoint(x: x, y: y + 3), withAttributes: attrs)
            x += width
        }

        // Light separator
        ctx.setStrokeColor(UIColor(white: 0.9, alpha: 1).cgColor)
        ctx.setLineWidth(0.25)
        ctx.move(to: CGPoint(x: margin, y: y + 20))
        ctx.addLine(to: CGPoint(x: margin + contentWidth, y: y + 20))
        ctx.strokePath()

        return y + 21
    }

    // MARK: Category Table with Bars

    private static func drawCategoryTable(ctx: CGContext, y startY: CGFloat, categories: [(key: String, value: Int)], total: Int, currency: String, pageRect: CGRect, pdfCtx: UIGraphicsPDFRendererContext) -> CGFloat {
        var y = startY
        let maxVal = categories.first?.value ?? 1

        for (name, amount) in categories.prefix(10) {
            y = checkPageBreak(ctx: pdfCtx, y: y, pageRect: pageRect, needed: 28)

            let pct = total > 0 ? Double(amount) / Double(total) * 100 : 0

            // Name
            let nameAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: textColor]
            name.draw(at: CGPoint(x: margin, y: y + 4), withAttributes: nameAttrs)

            // Bar
            let barX: CGFloat = margin + 120
            let barMaxW: CGFloat = contentWidth - 250
            let barW = barMaxW * CGFloat(amount) / CGFloat(max(1, maxVal))
            let barRect = CGRect(x: barX, y: y + 2, width: barW, height: 16)
            ctx.setFillColor(brandColor.withAlphaComponent(0.2).cgColor)
            ctx.fill(barRect)

            // Amount + percentage
            let valAttrs: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: textColor]
            let valStr = "\(formatCurrency(amount, currency))  (\(String(format: "%.1f", pct))%)"
            valStr.draw(at: CGPoint(x: barX + barMaxW + 10, y: y + 4), withAttributes: valAttrs)

            y += 25
        }

        return y
    }

    // MARK: Transaction Table

    private static func drawTransactionTable(ctx: UIGraphicsPDFRendererContext, y startY: CGFloat, transactions: [Transaction], currency: String, pageRect: CGRect) -> CGFloat {
        var y = startY

        let cols: [(String, CGFloat)] = [("Date", 65), ("Category", 85), ("Note", 160), ("Amount", 90)]
        y = drawTableHeader(ctx: ctx.cgContext, y: y, columns: cols)

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "MMM d"

        for tx in transactions {
            y = checkPageBreak(ctx: ctx, y: y, pageRect: pageRect, needed: 25)

            let note = tx.note.isEmpty ? "—" : String(tx.note.prefix(25)) + (tx.note.count > 25 ? "…" : "")
            let prefix = tx.type == .expense ? "-" : "+"
            let values = [
                dateFmt.string(from: tx.date),
                tx.category.title,
                note,
                "\(prefix)\(formatCurrency(tx.amount, currency))"
            ]

            let highlight: UIColor? = tx.type == .income ? UIColor(red: 0.92, green: 1, blue: 0.92, alpha: 1) : nil
            y = drawTableRow(ctx: ctx.cgContext, y: y, columns: cols, values: values, highlight: highlight)
        }

        return y
    }

    // MARK: Bar Chart

    private static func drawBarChart(ctx: CGContext, y startY: CGFloat, data: [(label: String, income: Int, expense: Int)]) -> CGFloat {
        guard !data.isEmpty else { return startY }

        let chartHeight: CGFloat = 120
        let chartWidth = contentWidth
        let barGroupWidth = chartWidth / CGFloat(data.count)
        let barWidth = barGroupWidth * 0.35
        let maxVal = CGFloat(max(
            data.map { $0.income }.max() ?? 1,
            data.map { $0.expense }.max() ?? 1
        ))

        let chartY = startY

        for (i, item) in data.enumerated() {
            let groupX = margin + CGFloat(i) * barGroupWidth

            // Income bar
            let incH = maxVal > 0 ? CGFloat(item.income) / maxVal * chartHeight : 0
            let incRect = CGRect(x: groupX + 2, y: chartY + chartHeight - incH, width: barWidth, height: incH)
            ctx.setFillColor(positiveColor.withAlphaComponent(0.6).cgColor)
            ctx.fill(incRect)

            // Expense bar
            let expH = maxVal > 0 ? CGFloat(item.expense) / maxVal * chartHeight : 0
            let expRect = CGRect(x: groupX + barWidth + 4, y: chartY + chartHeight - expH, width: barWidth, height: expH)
            ctx.setFillColor(dangerColor.withAlphaComponent(0.6).cgColor)
            ctx.fill(expRect)

            // Label
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 7, weight: .medium),
                .foregroundColor: subtextColor
            ]
            item.label.draw(at: CGPoint(x: groupX + 2, y: chartY + chartHeight + 3), withAttributes: labelAttrs)
        }

        // Legend
        let legendY = chartY + chartHeight + 16
        ctx.setFillColor(positiveColor.withAlphaComponent(0.6).cgColor)
        ctx.fill(CGRect(x: margin, y: legendY, width: 10, height: 10))
        let legAttrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: subtextColor]
        "Income".draw(at: CGPoint(x: margin + 14, y: legendY), withAttributes: legAttrs)

        ctx.setFillColor(dangerColor.withAlphaComponent(0.6).cgColor)
        ctx.fill(CGRect(x: margin + 60, y: legendY, width: 10, height: 10))
        "Expenses".draw(at: CGPoint(x: margin + 74, y: legendY), withAttributes: legAttrs)

        return legendY + 20
    }

    // MARK: Page Break

    private static func checkPageBreak(ctx: UIGraphicsPDFRendererContext, y: CGFloat, pageRect: CGRect, needed: CGFloat) -> CGFloat {
        if y + needed > pageRect.height - 50 {
            drawFooter(ctx: ctx.cgContext, pageRect: pageRect)
            ctx.beginPage()
            return margin + 10
        }
        return y
    }

    // MARK: Currency Formatting

    private static func formatCurrency(_ cents: Int, _ currency: String) -> String {
        let value = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        switch currency {
        case "EUR": formatter.currencySymbol = "€"
        case "USD": formatter.currencySymbol = "$"
        case "GBP": formatter.currencySymbol = "£"
        case "JPY": formatter.currencySymbol = "¥"; formatter.maximumFractionDigits = 0
        default: break
        }

        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
