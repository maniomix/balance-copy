import Foundation
import ZIPFoundation

enum Exporter {
    // MARK: - XLSX (real Office Open XML container)
    static func makeXLSX(
        monthKey: String,
        currency: String,
        budgetCents: Int,
        categoryCapsCents: [Category: Int],
        summary: Analytics.MonthSummary,
        transactions: [Transaction],
        categories: [Analytics.CategoryRow],
        daily: [Analytics.DayPoint]
    ) -> Data {
        // Build worksheets (richer export)
        let generatedAt = Date()
        let generatedFmt = DateFormatter()
        generatedFmt.locale = .current
        generatedFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // Parse YYYY-MM
        let parts = monthKey.split(separator: "-")
        let y = Int(parts.first ?? "0") ?? 0
        let m = Int(parts.dropFirst().first ?? "0") ?? 0

        let cal = Calendar.current
        var monthComps = DateComponents()
        monthComps.year = y
        monthComps.month = m
        monthComps.day = 1
        let monthDate = cal.date(from: monthComps) ?? Date()

        let dayNameFmt = DateFormatter()
        dayNameFmt.locale = .current
        dayNameFmt.dateFormat = "EEE" // Mon, Tue...

        // Category maps
        let spentByCategory: [Category: Int] = Dictionary(uniqueKeysWithValues: categories.map { ($0.category, $0.total) })
        let txCountByCategory: [Category: Int] = {
            var out: [Category: Int] = [:]
            for t in transactions { out[t.category, default: 0] += 1 }
            return out
        }()

        let totalSpentCents = categories.reduce(0) { $0 + $1.total }

        // Summary sheet
        let summaryRows: [[Cell]] = [
            [.s("Month"), .s(monthKey)],
            [.s("Currency"), .s(currency)],
            [.s("Generated at"), .s(generatedFmt.string(from: generatedAt))],
            [],
            [.s("Budget (€)"), .s("Spent (€)"), .s("Remaining (€)"), .s("Daily Avg (€)"), .s("Spent %")],
            [
                .n(Double(budgetCents) / 100.0),
                .n(Double(summary.totalSpent) / 100.0),
                .n(Double(summary.remaining) / 100.0),
                .n(Double(summary.dailyAvg) / 100.0),
                .n(summary.spentRatio * 100.0)
            ],
            [],
            [.s("Transactions count"), .n(Double(transactions.count))],
            [.s("Categories used"), .n(Double(Set(transactions.map { $0.category }).count))]
        ]

        // Categories sheet (add % share + transaction count)
        var catRows: [[Cell]] = [[.s("Category"), .s("Transactions"), .s("Spent (€)"), .s("Share (%)")]]
        for r in categories {
            let share = totalSpentCents > 0 ? (Double(r.total) / Double(totalSpentCents) * 100.0) : 0
            catRows.append([
                .s(r.category.title),
                .n(Double(txCountByCategory[r.category] ?? 0)),
                .n(Double(r.total) / 100.0),
                .n(share)
            ])
        }

        // Category caps sheet (full budgeting context)
        var capRows: [[Cell]] = [[.s("Category"), .s("Cap (€)"), .s("Spent (€)"), .s("Remaining (€)"), .s("Used (%)"), .s("Transactions")]]
        for c in Category.allCases {
            let cap = categoryCapsCents[c] ?? 0
            let spent = spentByCategory[c] ?? 0
            let remaining = cap - spent
            let used = cap > 0 ? (Double(spent) / Double(cap) * 100.0) : 0
            let cnt = txCountByCategory[c] ?? 0
            capRows.append([
                .s(c.title),
                .n(Double(cap) / 100.0),
                .n(Double(spent) / 100.0),
                .n(Double(remaining) / 100.0),
                .n(used),
                .n(Double(cnt))
            ])
        }

        // Daily sheet (add weekday + cumulative + remaining)
        var dailyRows: [[Cell]] = [[.s("Date"), .s("Weekday"), .s("Spent (€)"), .s("Cumulative (€)"), .s("Remaining (€)")]]
        var cumulativeDayCents = 0
        for d in daily.sorted(by: { $0.day < $1.day }) {
            cumulativeDayCents += d.amount

            var comps = DateComponents()
            comps.year = y
            comps.month = m
            comps.day = d.day
            let date = cal.date(from: comps) ?? monthDate

            dailyRows.append([
                .s(String(format: "%04d-%02d-%02d", y, m, d.day)),
                .s(dayNameFmt.string(from: date)),
                .n(Double(d.amount) / 100.0),
                .n(Double(cumulativeDayCents) / 100.0),
                .n(Double(budgetCents - cumulativeDayCents) / 100.0)
            ])
        }

        // Transactions sheet (most detailed)
        let df = DateFormatter()
        df.locale = .current
        df.dateFormat = "yyyy-MM-dd"

        var txRows: [[Cell]] = [[
            .s("Date"),
            .s("Type"),  // ← جدید
            .s("Category"),
            .s("Payment Method"),  // ← جدید
            .s("Note"),
            .s("Amount (€)"),
            .s("Amount (cents)"),
            .s("Running spent (€)"),
            .s("Remaining (€)"),
            .s("Transaction ID")
        ]]

        var runningCents = 0
        for t in transactions.sorted(by: { $0.date < $1.date }) {
            runningCents += t.amount
            txRows.append([
                .s(df.string(from: t.date)),
                .s(t.type == .income ? "Income" : "Expense"),  // ← جدید
                .s(t.category.title),
                .s(t.paymentMethod.displayName),  // ← جدید
                .s(t.note),
                .n(Double(t.amount) / 100.0),
                .n(Double(t.amount)),
                .n(Double(runningCents) / 100.0),
                .n(Double(budgetCents - runningCents) / 100.0),
                .s(t.id.uuidString)
            ])
        }

        // Payment breakdown sheet (new)
        var paymentMap: [PaymentMethod: Int] = [:]
        for t in transactions { paymentMap[t.paymentMethod, default: 0] += t.amount }
        
        let totalSpent = paymentMap.values.reduce(0, +)
        let paymentBreakdown = paymentMap.map { (method, total) in
            (method: method, total: total, percentage: totalSpent > 0 ? Double(total) / Double(totalSpent) : 0)
        }.sorted { $0.total > $1.total }
        
        var paymentRows: [[Cell]] = [[.s("Payment Method"), .s("Transactions"), .s("Amount (€)"), .s("Share (%)")]]
        for p in paymentBreakdown {
            let txCount = transactions.filter { $0.paymentMethod == p.method }.count
            paymentRows.append([
                .s(p.method.displayName),
                .n(Double(txCount)),
                .n(Double(p.total) / 100.0),
                .n(p.percentage * 100.0)
            ])
        }

        let sheets = [
            (name: "Summary", rows: summaryRows),
            (name: "Categories", rows: catRows),
            (name: "Category caps", rows: capRows),
            (name: "Payment methods", rows: paymentRows),  // ← جدید
            (name: "Daily", rows: dailyRows),
            (name: "Transactions", rows: txRows)
        ]

        let sheetNames = sheets.map { $0.name }
        let sheetCount = sheets.count

        // Assemble all files required for a minimal XLSX
        var entries: [(String, Data)] = []

        entries.append(("[Content_Types].xml", Data(contentTypesXML(sheetCount: sheetCount).utf8)))
        entries.append(("_rels/.rels", Data(relsXML().utf8)))
        entries.append(("xl/workbook.xml", Data(workbookXML(sheetNames: sheetNames).utf8)))
        entries.append(("xl/_rels/workbook.xml.rels", Data(workbookRelsXML(sheetCount: sheetCount).utf8)))

        // Minimal styles (so Excel is happy)
        entries.append(("xl/styles.xml", Data(stylesXML().utf8)))

        for (idx, s) in sheets.enumerated() {
            let xml = worksheetXML(rows: s.rows)
            entries.append(("xl/worksheets/sheet\(idx + 1).xml", Data(xml.utf8)))
        }

        return zipXLSX(entries: entries)
    }

    private static func contentTypesXML(sheetCount: Int) -> String {
        let overrides = (1...sheetCount).map { i in
            "  <Override PartName=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }.joined(separator: "\n")

        return """
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">
  <Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>
  <Default Extension=\"xml\" ContentType=\"application/xml\"/>
  <Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>
  <Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>
\(overrides)
</Types>
"""
    }

    private static func stylesXML() -> String {
        return """
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">
  <fonts count=\"1\"><font/></fonts>
  <fills count=\"2\">
    <fill><patternFill patternType=\"none\"/></fill>
    <fill><patternFill patternType=\"gray125\"/></fill>
  </fills>
  <borders count=\"1\"><border/></borders>
  <cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>
  <cellXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/></cellXfs>
  <cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>
</styleSheet>
"""
    }

private static func zipXLSX(entries: [(String, Data)]) -> Data {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("balance.xlsx.tmp", isDirectory: true)
    try? fm.removeItem(at: dir)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

    let zipURL = dir.appendingPathComponent("out.xlsx")
    try? fm.removeItem(at: zipURL)

    do {
        let archive = try Archive(url: zipURL, accessMode: .create)

        for (path, data) in entries {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate,
                bufferSize: 16_384,
                progress: nil,
                provider: { position, size in
                    let start = Int(position)
                    let end = min(start + Int(size), data.count)
                    return data.subdata(in: start..<end)
                }
            )
        }

        return (try? Data(contentsOf: zipURL)) ?? Data()
    } catch {
        return Data()
    }
}

    // ---------- CSV (همین که داری می‌مونه)

    // MARK: - CSV (single file with sections)
    static func makeCSV(
        monthKey: String,
        currency: String,
        budgetCents: Int,
        summary: Analytics.MonthSummary,
        transactions: [Transaction],
        categories: [Analytics.CategoryRow],
        daily: [Analytics.DayPoint]
    ) -> String {
        func esc(_ s: String) -> String {
            let needsQuotes = s.contains(",") || s.contains("\n") || s.contains("\"")
            var out = s.replacingOccurrences(of: "\"", with: "\"\"")
            if needsQuotes { out = "\"" + out + "\"" }
            return out
        }

        let df = DateFormatter()
        df.locale = .current
        df.dateFormat = "yyyy-MM-dd"

        var lines: [String] = []

        // Summary
        lines.append("# Summary")
        lines.append("month,currency,budget_eur,spent_eur,remaining_eur,daily_avg_eur,spent_percent")
        lines.append("\(monthKey),\(currency),\(String(format: "%.2f", Double(budgetCents)/100.0)),\(String(format: "%.2f", Double(summary.totalSpent)/100.0)),\(String(format: "%.2f", Double(summary.remaining)/100.0)),\(String(format: "%.2f", Double(summary.dailyAvg)/100.0)),\(Int((summary.spentRatio*100.0).rounded()))%")
        lines.append("")

        // Categories
        lines.append("# Categories")
        lines.append("category,spent_eur")
        for r in categories {
            lines.append("\(esc(r.category.title)),\(String(format: "%.2f", Double(r.total)/100.0))")
        }
        lines.append("")

        // Daily
        lines.append("# Daily")
        lines.append("day,spent_eur")
        for d in daily.sorted(by: { $0.day < $1.day }) {
            lines.append("\(d.day),\(String(format: "%.2f", Double(d.amount)/100.0))")
        }
        lines.append("")

        // Transactions
        lines.append("# Transactions")
        lines.append("date,type,category,payment_method,note,amount_eur")
        for t in transactions.sorted(by: { $0.date < $1.date }) {
            let dateStr = df.string(from: t.date)
            let typeStr = t.type == .income ? "income" : "expense"
            let cat = esc(t.category.title)
            let payment = esc(t.paymentMethod.displayName)  // ← جدید
            let note = esc(t.note)
            let eur = String(format: "%.2f", Double(t.amount) / 100.0)
            lines.append("\(dateStr),\(typeStr),\(cat),\(payment),\(note),\(eur)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - SpreadsheetML 2003 XML (Excel can open; extension is kept as .xlsx by caller)
    static func makeExcelXML(
        monthKey: String,
        currency: String,
        budgetCents: Int,
        summary: Analytics.MonthSummary,
        transactions: [Transaction],
        categories: [Analytics.CategoryRow],
        daily: [Analytics.DayPoint]
    ) -> String {
        func xesc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
             .replacingOccurrences(of: "\"", with: "&quot;")
             .replacingOccurrences(of: "'", with: "&apos;")
        }

        let df = DateFormatter()
        df.locale = .current
        df.dateFormat = "yyyy-MM-dd"

        func row(_ cells: [String], header: Bool = false) -> String {
            var out = "      <Row>\n"
            for c in cells {
                let style = header ? " ss:StyleID=\"sHeader\"" : ""
                out += "        <Cell\(style)><Data ss:Type=\"String\">\(xesc(c))</Data></Cell>\n"
            }
            out += "      </Row>\n"
            return out
        }

        func sheet(_ name: String, _ rows: [String]) -> String {
            var out = "  <Worksheet ss:Name=\"\(xesc(name))\">\n    <Table>\n"
            for r in rows { out += r }
            out += "    </Table>\n  </Worksheet>\n"
            return out
        }

        let summaryRows: [String] = [
            row(["Month", monthKey], header: true),
            row(["Currency", currency]),
            row([""], header: false),
            row(["Budget (€)", "Spent (€)", "Remaining (€)", "Daily Avg (€)", "Spent %"], header: true),
            row([
                String(format: "%.2f", Double(budgetCents)/100.0),
                String(format: "%.2f", Double(summary.totalSpent)/100.0),
                String(format: "%.2f", Double(summary.remaining)/100.0),
                String(format: "%.2f", Double(summary.dailyAvg)/100.0),
                String(format: "%.0f%%", summary.spentRatio*100.0)
            ])
        ]

        var catRows: [String] = [row(["Category", "Spent (€)"], header: true)]
        for r in categories {
            catRows.append(row([r.category.title, String(format: "%.2f", Double(r.total)/100.0)]))
        }

        var dayRows: [String] = [row(["Day", "Spent (€)"], header: true)]
        for d in daily.sorted(by: { $0.day < $1.day }) {
            dayRows.append(row(["\(d.day)", String(format: "%.2f", Double(d.amount)/100.0)]))
        }

        var txRows: [String] = [row(["Date", "Category", "Note", "Amount (€)"], header: true)]
        for t in transactions.sorted(by: { $0.date < $1.date }) {
            txRows.append(row([
                df.string(from: t.date),
                t.category.title,
                t.note,
                String(format: "%.2f", Double(t.amount)/100.0)
            ]))
        }

        let workbook = """
        <?xml version="1.0"?>
        <?mso-application progid="Excel.Sheet"?>
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
         xmlns:o="urn:schemas-microsoft-com:office:office"
         xmlns:x="urn:schemas-microsoft-com:office:excel"
         xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
          <Styles>
            <Style ss:ID="sHeader"><Font ss:Bold="1"/></Style>
          </Styles>
        """

        return workbook
            + sheet("Summary", summaryRows)
            + sheet("Categories", catRows)
            + sheet("Daily", dayRows)
            + sheet("Transactions", txRows)
            + "</Workbook>\n"
    }

    private static func relsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
    }

    private static func workbookXML(sheetNames: [String]) -> String {
        let sheets = sheetNames.enumerated().map { idx, name in
            "<sheet name=\"\(xmlEsc(name))\" sheetId=\"\(idx+1)\" r:id=\"rId\(idx+1)\"/>"
        }.joined()

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>\(sheets)</sheets>
        </workbook>
        """
    }

    private static func workbookRelsXML(sheetCount: Int) -> String {
        let sheetRels = (1...sheetCount).map { i in
            "<Relationship Id=\"rId\(i)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i).xml\"/>"
        }.joined(separator: "\n  ")

        let stylesRel = "<Relationship Id=\"rId\(sheetCount + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"

        return """
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">
  \(sheetRels)
  \(stylesRel)
</Relationships>
"""
    }
    
    private enum Cell {
        case s(String)   // string
        case n(Double)   // number
    }

    private static func worksheetXML(rows: [[Cell]]) -> String {
        func colRef(_ col: Int) -> String {
            var n = col
            var s = ""
            while n > 0 {
                let r = (n - 1) % 26
                s = String(UnicodeScalar(65 + r)!) + s
                n = (n - 1) / 26
            }
            return s
        }

        var xmlRows = ""
        for (rIdx, row) in rows.enumerated() {
            let rowNum = rIdx + 1
            var cells = ""
            for (cIdx, cell) in row.enumerated() {
                let ref = "\(colRef(cIdx + 1))\(rowNum)"
                switch cell {
                case .s(let v):
                    cells += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(xmlEsc(v))</t></is></c>"
                case .n(let v):
                    let s = String(format: "%.2f", v) // dot decimal
                    cells += "<c r=\"\(ref)\"><v>\(s)</v></c>"
                }
            }
            xmlRows += "<row r=\"\(rowNum)\">\(cells)</row>"
        }

        return """
<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>\(xmlRows)</sheetData>
</worksheet>
"""
    }

    private static func centsToEuros(_ cents: Int) -> Double { Double(cents) / 100.0 }

    private static func xmlEsc(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        out = out.replacingOccurrences(of: "'", with: "&apos;")
        return out
    }
}
