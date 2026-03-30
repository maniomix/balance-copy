import Foundation

// MARK: - CSV Parser

enum CSV {
    static func parse(_ text: String) -> [[String]] {
        // Strip UTF-8 BOM if present (common with Excel/Numbers exports)
        let cleaned = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text

        // Normalize line endings so parsing is consistent:
        // - CRLF (\r\n)
        // - CR-only (\r)
        // - Unicode line separators (\u2028 / \u2029)
        let normalized = cleaned
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")

        // Auto-detect delimiter: Excel in many EU locales uses ';' instead of ','
        let firstLine = normalized.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let commaCount = firstLine.filter { $0 == "," }.count
        let semiCount = firstLine.filter { $0 == ";" }.count
        let delimiter: Character = (semiCount > commaCount) ? ";" : ","

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        func endField() {
            row.append(field)
            field = ""
        }

        func endRow() {
            rows.append(row)
            row = []
        }

        let chars = Array(normalized)
        var i = 0
        while i < chars.count {
            let ch = chars[i]

            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                if ch == "\"" {
                    inQuotes = true
                } else if ch == delimiter {
                    endField()
                } else if ch == "\n" {
                    endField()
                    endRow()
                } else {
                    field.append(ch)
                }
            }

            i += 1
        }

        if !field.isEmpty || !row.isEmpty {
            endField()
            endRow()
        }

        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
    }
}
