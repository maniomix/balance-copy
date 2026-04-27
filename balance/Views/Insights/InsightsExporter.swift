import Foundation

enum InsightsExportFormat {
    case csv
    case excel
    case pdf

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .excel: return "xlsx"
        case .pdf: return "pdf"
        }
    }
}

enum InsightsExporter {
    static func exportMonth(store: Store, format: InsightsExportFormat) throws -> URL {
        let summary = Analytics.monthSummary(store: store)
        let tx = Analytics.monthTransactions(store: store)
        let dailyPoints = Analytics.dailySpendPoints(store: store)
        let cats = Analytics.categoryBreakdown(store: store)

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: store.selectedMonth)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let monthKey = String(format: "%04d-%02d", y, m)

        let filename = "Centmond_\(monthKey).\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let data: Data
        switch format {
        case .csv:
            let csv = Exporter.makeCSV(
                monthKey: monthKey,
                currency: "EUR",
                budgetCents: store.budgetTotal,
                summary: summary,
                transactions: tx,
                categories: cats,
                daily: dailyPoints
            )
            data = csv.data(using: String.Encoding.utf8) ?? Data()
        case .excel:
            let caps: [Category: Int] = Dictionary(
                uniqueKeysWithValues: store.allCategories.map { ($0, store.categoryBudget(for: $0)) }
            )
            data = Exporter.makeXLSX(
                monthKey: monthKey,
                currency: "EUR",
                budgetCents: store.budgetTotal,
                categoryCapsCents: caps,
                summary: summary,
                transactions: tx,
                categories: cats,
                daily: dailyPoints
            )
        case .pdf:
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: store.selectedMonth))!
            let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart)!
            data = PDFReportGenerator.generate(
                type: .monthlySummary,
                store: store,
                startDate: monthStart,
                endDate: monthEnd
            )
        }

        try data.write(to: url, options: .atomic)
        return url
    }
}
