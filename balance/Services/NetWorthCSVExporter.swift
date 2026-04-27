import Foundation

// ============================================================
// MARK: - Net Worth CSV Exporter (Phase 4c — iOS port)
// ============================================================
//
// Renders net-worth snapshot history as a CSV string or writes it
// to a temporary file URL the caller can share via
// `UIActivityViewController` / `ShareLink`.
//
// Columns: date (YYYY-MM-DD), assets, liabilities, net_worth, source
// Numbers are plain decimals (no currency glyphs / thousands
// separators) so the file opens cleanly in Numbers / Excel.
//
// Ported from macOS Centmond. iOS adaptations:
//   - No AppKit / NSSavePanel. Returns either a String (for in-app
//     preview) or a file URL in the temp directory (for ShareLink).
//   - Amounts are Int cents → rendered with 2 decimals.
// ============================================================

enum NetWorthCSVExporter {

    /// Render the full snapshot history as a CSV string. Sorted by date
    /// ascending. Returns nil when there are no snapshots.
    static func renderCSV(from snapshots: [NetWorthSnapshot]) -> String? {
        guard !snapshots.isEmpty else { return nil }
        let sorted = snapshots.sorted { $0.date < $1.date }
        let header = "date,assets,liabilities,net_worth,source"
        let rows = sorted.map { s -> String in
            "\(isoDay(s.date)),\(plain(cents: s.totalAssets)),\(plain(cents: s.totalLiabilities)),\(plain(cents: s.netWorth)),\(s.source.rawValue)"
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// Write the CSV to a temporary file and return the URL for
    /// `ShareLink` / `UIActivityViewController`. Returns nil on empty
    /// history or write failure.
    static func writeTempFile(snapshots: [NetWorthSnapshot]) -> URL? {
        guard let csv = renderCSV(from: snapshots) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("centmond-networth-\(filenameDate()).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Internals

    private static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    private static func filenameDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }

    /// Plain decimal string — no thousands separators or currency glyphs.
    /// Keeps the CSV machine-parseable across locales.
    private static func plain(cents: Int) -> String {
        let dollars = Double(cents) / 100
        return String(format: "%.2f", dollars)
    }
}
