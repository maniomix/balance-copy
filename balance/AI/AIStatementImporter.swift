import Foundation

// ============================================================
// MARK: - AI Statement Importer
// ============================================================
//
// Phase 3 deliverable: parses CSV/text bank statement data
// into staged transactions for review.
//
// Flow: raw text → parse → normalize → deduplicate → stage → review
//
// Low-confidence entries are flagged for manual review.
// Supports common bank CSV formats and tab-separated data.
//
// ============================================================

/// A staged transaction awaiting user review before import.
struct StagedTransaction: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Int                     // cents (positive = expense, negative = income)
    let rawDescription: String          // Original merchant text from statement
    let normalizedMerchant: String      // Cleaned merchant name
    let suggestedCategory: String       // AI-suggested category
    let categoryConfidence: Double      // 0–1
    var status: ReviewStatus = .pending
    var isDuplicate: Bool = false        // True if matches existing transaction

    enum ReviewStatus: String {
        case pending
        case approved
        case rejected
        case modified
    }

    /// Transaction type inferred from amount sign.
    var transactionType: String {
        amount >= 0 ? "expense" : "income"
    }
}

/// Result of an import attempt.
struct ImportResult {
    let staged: [StagedTransaction]
    let duplicateCount: Int
    let lowConfidenceCount: Int
    let parseErrors: [String]

    var summary: String {
        var lines: [String] = []
        lines.append("Parsed \(staged.count) transactions")
        if duplicateCount > 0 {
            lines.append("  ⚠️ \(duplicateCount) potential duplicate(s)")
        }
        if lowConfidenceCount > 0 {
            lines.append("  📌 \(lowConfidenceCount) need category review")
        }
        if !parseErrors.isEmpty {
            lines.append("  ❌ \(parseErrors.count) line(s) couldn't be parsed")
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor
class AIStatementImporter {
    static let shared = AIStatementImporter()

    private init() {}

    // MARK: - Parse CSV/Text

    /// Parse raw CSV or tab-separated statement text.
    func parseStatement(_ rawText: String, existingTransactions: [Transaction] = []) -> ImportResult {
        let lines = rawText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return ImportResult(staged: [], duplicateCount: 0, lowConfidenceCount: 0,
                                parseErrors: ["Empty input"])
        }

        // Detect delimiter
        let delimiter = detectDelimiter(lines)

        // Detect header row
        let (dataLines, columnMap) = detectColumns(lines, delimiter: delimiter)

        var staged: [StagedTransaction] = []
        var errors: [String] = []

        for line in dataLines {
            let fields = splitLine(line, delimiter: delimiter)

            if let txn = parseLine(fields: fields, columnMap: columnMap) {
                staged.append(txn)
            } else {
                errors.append("Could not parse: \(line.prefix(60))...")
            }
        }

        // Deduplicate against existing transactions
        let duplicateCount = markDuplicates(&staged, existing: existingTransactions)

        // Count low-confidence categories
        let lowConfidenceCount = staged.filter { $0.categoryConfidence < 0.5 }.count

        return ImportResult(
            staged: staged,
            duplicateCount: duplicateCount,
            lowConfidenceCount: lowConfidenceCount,
            parseErrors: errors
        )
    }

    /// Convert approved staged transactions into AIActions for execution.
    func toActions(_ staged: [StagedTransaction]) -> [AIAction] {
        staged.filter { $0.status == .approved || $0.status == .modified }
            .map { txn in
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                return AIAction(
                    type: .addTransaction,
                    params: AIAction.ActionParams(
                        amount: abs(txn.amount),
                        category: txn.suggestedCategory,
                        note: txn.normalizedMerchant,
                        date: df.string(from: txn.date),
                        transactionType: txn.transactionType
                    )
                )
            }
    }

    // MARK: - Parsing Helpers

    private func detectDelimiter(_ lines: [String]) -> Character {
        let first = lines.prefix(3).joined()
        let commaCount = first.filter { $0 == "," }.count
        let tabCount = first.filter { $0 == "\t" }.count
        let semiCount = first.filter { $0 == ";" }.count

        if tabCount > commaCount && tabCount > semiCount { return "\t" }
        if semiCount > commaCount { return ";" }
        return ","
    }

    private func detectColumns(_ lines: [String], delimiter: Character) -> ([String], ColumnMap) {
        guard let header = lines.first else {
            return (lines, ColumnMap())
        }

        let fields = splitLine(header, delimiter: delimiter).map { $0.lowercased() }

        var map = ColumnMap()

        // Find date column
        for (i, f) in fields.enumerated() {
            if f.contains("date") || f.contains("تاریخ") || f.contains("datum") {
                map.dateIndex = i
            }
            if f.contains("amount") || f.contains("مبلغ") || f.contains("betrag") ||
               f.contains("sum") || f.contains("value") {
                map.amountIndex = i
            }
            if f.contains("description") || f.contains("merchant") || f.contains("payee") ||
               f.contains("شرح") || f.contains("memo") || f.contains("name") ||
               f.contains("detail") || f.contains("beschreibung") {
                map.descriptionIndex = i
            }
            if f.contains("debit") || f.contains("بدهکار") { map.debitIndex = i }
            if f.contains("credit") || f.contains("بستانکار") { map.creditIndex = i }
            if f.contains("category") || f.contains("دسته") { map.categoryIndex = i }
        }

        // If we found at least date and amount/description, skip header
        if map.dateIndex != nil && (map.amountIndex != nil || map.descriptionIndex != nil) {
            return (Array(lines.dropFirst()), map)
        }

        // No clear header — try positional (date, description, amount)
        map.dateIndex = 0
        map.descriptionIndex = 1
        map.amountIndex = fields.count > 2 ? 2 : 1
        return (lines, map)
    }

    private func parseLine(fields: [String], columnMap: ColumnMap) -> StagedTransaction? {
        // Date
        guard let dateIdx = columnMap.dateIndex, dateIdx < fields.count,
              let date = parseDate(fields[dateIdx]) else { return nil }

        // Amount
        var amount: Int?
        if let amtIdx = columnMap.amountIndex, amtIdx < fields.count {
            amount = parseAmount(fields[amtIdx])
        } else if let debIdx = columnMap.debitIndex, debIdx < fields.count {
            amount = parseAmount(fields[debIdx])
            // Check credit column too
            if (amount == nil || amount == 0), let credIdx = columnMap.creditIndex, credIdx < fields.count {
                if let credit = parseAmount(fields[credIdx]) {
                    amount = -credit // Negative = income
                }
            }
        }
        guard let finalAmount = amount, finalAmount != 0 else { return nil }

        // Description
        let rawDesc: String
        if let descIdx = columnMap.descriptionIndex, descIdx < fields.count {
            rawDesc = fields[descIdx]
        } else {
            rawDesc = fields.filter { !$0.isEmpty }.joined(separator: " ")
        }

        let normalized = normalizeMerchant(rawDesc)
        let (category, confidence) = suggestCategory(normalized)

        return StagedTransaction(
            date: date,
            amount: finalAmount,
            rawDescription: rawDesc,
            normalizedMerchant: normalized,
            suggestedCategory: category,
            categoryConfidence: confidence
        )
    }

    private func splitLine(_ line: String, delimiter: Character) -> [String] {
        // Handle quoted fields
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == delimiter && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    // MARK: - Date Parsing

    private func parseDate(_ raw: String) -> Date? {
        let formats = [
            "yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy", "dd.MM.yyyy",
            "yyyy/MM/dd", "M/d/yyyy", "d/M/yyyy", "dd-MM-yyyy",
            "yyyy.MM.dd", "MMM d, yyyy", "d MMM yyyy"
        ]
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")

        for format in formats {
            df.dateFormat = format
            if let date = df.date(from: trimmed) { return date }
        }
        return nil
    }

    // MARK: - Amount Parsing

    private func parseAmount(_ raw: String) -> Int? {
        var cleaned = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "﷼", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle European format: 1.234,56 → 1234.56
        if cleaned.contains(",") && cleaned.contains(".") {
            if let commaIdx = cleaned.lastIndex(of: ","),
               let dotIdx = cleaned.lastIndex(of: ".") {
                if commaIdx > dotIdx {
                    // European: 1.234,56
                    cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                        .replacingOccurrences(of: ",", with: ".")
                } else {
                    // US: 1,234.56
                    cleaned = cleaned.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if cleaned.contains(",") {
            // Could be decimal comma: 12,50 → 12.50
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }

        // Handle parentheses as negative: (50.00) → -50.00
        if cleaned.hasPrefix("(") && cleaned.hasSuffix(")") {
            cleaned = "-" + cleaned.dropFirst().dropLast()
        }

        guard let value = Double(cleaned) else { return nil }
        return Int((abs(value) * 100).rounded()) * (value < 0 ? -1 : 1)
    }

    // MARK: - Merchant Normalization

    private func normalizeMerchant(_ raw: String) -> String {
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove transaction codes, reference numbers
        let patterns = [
            "\\b[A-Z0-9]{10,}\\b",     // Long alphanumeric codes
            "\\bREF:\\s*\\S+",           // REF: numbers
            "\\b\\d{6,}\\b",            // Long number sequences
            "\\bPOS\\b",                 // POS terminal indicator
            "\\bVISA\\b|\\bMC\\b"        // Card type
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                result = regex.stringByReplacingMatches(in: result,
                    range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Category Suggestion

    private func suggestCategory(_ merchant: String) -> (String, Double) {
        if let cat = AICategorySuggester.shared.suggest(note: merchant) {
            return (cat.storageKey, 0.8)
        }
        return ("other", 0.2)
    }

    // MARK: - Duplicate Detection

    private func markDuplicates(_ staged: inout [StagedTransaction], existing: [Transaction]) -> Int {
        var count = 0
        for i in staged.indices {
            let txn = staged[i]
            let isDupe = existing.contains { ex in
                ex.amount == abs(txn.amount) &&
                Calendar.current.isDate(ex.date, inSameDayAs: txn.date) &&
                (ex.note.lowercased().contains(txn.normalizedMerchant.lowercased().prefix(5)) ||
                 txn.normalizedMerchant.lowercased().contains(ex.note.lowercased().prefix(5)))
            }
            if isDupe {
                staged[i].isDuplicate = true
                count += 1
            }
        }
        return count
    }
}

// MARK: - Column Map

private struct ColumnMap {
    var dateIndex: Int?
    var amountIndex: Int?
    var descriptionIndex: Int?
    var debitIndex: Int?
    var creditIndex: Int?
    var categoryIndex: Int?
}
