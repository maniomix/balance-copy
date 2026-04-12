import Foundation
import Combine

// ============================================================
// MARK: - AI Autonomous Ingestion (Phase 5)
// ============================================================
//
// Unified ingestion layer that brings financial data into the
// app from pasted text, statement rows, and receipt-style input.
//
// Flow:
//   raw text → parse → normalize → detect flags → stage → review → import
//
// Detects:
//   • merchant normalization
//   • category suggestions
//   • duplicates
//   • recurring/subscription candidates
//   • transfer candidates
//
// Integrates with: trust, audit, merchant memory, category suggester
//
// ============================================================

// ══════════════════════════════════════════════════════════════
// MARK: - Ingestion Models
// ══════════════════════════════════════════════════════════════

/// How the raw input was provided.
enum IngestionSourceType: String, Codable, CaseIterable, Identifiable {
    case pastedStatement     = "pasted_statement"
    case pastedTransactions  = "pasted_transactions"
    case receiptText         = "receipt_text"
    case genericText         = "generic_text"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pastedStatement:    return "Bank Statement"
        case .pastedTransactions: return "Transaction List"
        case .receiptText:        return "Receipt Text"
        case .genericText:        return "Generic Text"
        }
    }

    var icon: String {
        switch self {
        case .pastedStatement:    return "doc.text"
        case .pastedTransactions: return "list.bullet.clipboard"
        case .receiptText:        return "receipt"
        case .genericText:        return "text.alignleft"
        }
    }
}

/// A complete ingestion session from raw input to final import.
struct IngestionSession: Identifiable {
    let id: UUID
    let sourceType: IngestionSourceType
    let rawInput: String
    var candidates: [CandidateTransaction]
    var status: SessionStatus
    let startedAt: Date
    var completedAt: Date?
    let groupId: UUID               // shared with audit records

    // ── Stats ──
    var parseErrors: [String] = []

    var approvedCount: Int { candidates.filter { $0.approval == .approved }.count }
    var rejectedCount: Int { candidates.filter { $0.approval == .rejected }.count }
    var pendingCount: Int { candidates.filter { $0.approval == .pending }.count }
    var flaggedCount: Int { candidates.filter(\.requiresReview).count }
    var duplicateCount: Int { candidates.filter(\.isDuplicateSuspect).count }

    var safeToAutoApprove: [CandidateTransaction] {
        candidates.filter { $0.confidence >= 0.75 && !$0.requiresReview && $0.approval == .pending }
    }

    enum SessionStatus: String {
        case parsing
        case staged         // candidates ready for review
        case importing      // import in progress
        case completed
        case failed
    }
}

/// A parsed candidate transaction awaiting review before import.
struct CandidateTransaction: Identifiable {
    let id: UUID
    let rawText: String
    var merchant: String
    var normalizedMerchant: String
    var amount: Int                    // cents (always positive)
    var date: Date
    var transactionType: TransactionType
    var category: Category?
    var categoryConfidence: Double     // 0.0–1.0

    // ── Overall confidence ──
    var confidence: Double             // 0.0–1.0 composite

    // ── Flags ──
    var isDuplicateSuspect: Bool = false
    var duplicateOfId: UUID?           // existing transaction ID
    var duplicateConfidence: Double = 0
    var duplicateReason: String?

    var isRecurringSuspect: Bool = false
    var recurringHint: String?         // e.g. "Monthly from Netflix"

    var isSubscriptionSuspect: Bool = false
    var subscriptionHint: String?

    var isTransferSuspect: Bool = false
    var transferAccountHint: String?

    var requiresReview: Bool = false
    var reviewReasons: [String] = []

    // ── Approval state ──
    var approval: ApprovalStatus = .pending

    enum ApprovalStatus: String {
        case pending
        case approved
        case rejected
    }

    enum TransactionType: String {
        case expense
        case income
    }
}

/// Result of an ingestion import pass.
struct IngestionImportResult {
    let importedCount: Int
    let failedCount: Int
    let skippedCount: Int
    let summary: String
}

// ══════════════════════════════════════════════════════════════
// MARK: - Merchant Normalizer
// ══════════════════════════════════════════════════════════════

/// Cleans and normalizes merchant strings from bank statements and receipts.
enum MerchantNormalizer {

    /// Normalize a raw merchant/payee string into a clean, human-readable form.
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        // 1. Remove common prefixes (POS, card, direct debit markers)
        let prefixes = [
            "POS ", "POS-", "PURCHASE ", "CARD ", "DEBIT ", "DIRECT ",
            "CCD ", "ACH ", "EFT ", "PREAUTH ", "CHECKCARD ", "VISA ",
            "MC ", "MASTERCARD ", "AMEX ", "PAYPAL *", "SQ *", "TST* ",
            "PP*", "SP ", "GOOGLE *", "APPLE.COM/", "AMZN MKTP ",
        ]
        for prefix in prefixes {
            if text.uppercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                break
            }
        }

        // 2. Remove trailing reference/location codes
        //    Patterns: #1234, Store 1234, - TX, - US, *1234
        let trailingPatterns = [
            #"[\s\-]*#\d{2,}.*$"#,           // #1234...
            #"[\s\-]*\*\d{3,}.*$"#,          // *1234...
            #"\s+STORE\s*\d+.*$"#,            // STORE 1234
            #"\s+STR\s*\d+.*$"#,              // STR 1234
            #"\s+-\s*[A-Z]{2}\s*$"#,          // - TX, - US
            #"\s+\d{5,}$"#,                   // trailing long numbers
            #"\s+[A-Z]{2}\s+\d{5}$"#,         // ST 12345 (state + zip)
            #"\s+\d{2}/\d{2}$"#,              // trailing date fragment (04/08)
            #"\s+xx+\d{4}$"#,                 // card mask xx1234
        ]
        for pattern in trailingPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            }
        }

        // 3. Collapse whitespace
        text = text.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 4. Title case if all-caps
        if text == text.uppercased() && text.count > 2 {
            text = text.capitalized
        }

        return text
    }

    /// Check if two merchant strings likely refer to the same merchant.
    static func areSameMerchant(_ a: String, _ b: String) -> Bool {
        let na = normalize(a).lowercased()
        let nb = normalize(b).lowercased()

        if na == nb { return true }
        if na.isEmpty || nb.isEmpty { return false }

        // Prefix match (first 5+ chars)
        let minLen = min(na.count, nb.count, 8)
        guard minLen >= 4 else { return false }
        let prefixA = String(na.prefix(minLen))
        let prefixB = String(nb.prefix(minLen))
        if prefixA == prefixB { return true }

        // Word overlap (Jaccard similarity)
        let wordsA = Set(na.split(separator: " ").map(String.init))
        let wordsB = Set(nb.split(separator: " ").map(String.init))
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return false }
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        return Double(intersection) / Double(union) >= 0.6
    }

    /// Known subscription/service merchant patterns.
    static let subscriptionMerchants: Set<String> = [
        "netflix", "spotify", "apple music", "youtube premium", "youtube",
        "disney", "disney+", "hbo", "hulu", "amazon prime", "prime video",
        "adobe", "microsoft 365", "microsoft", "office 365",
        "dropbox", "google one", "google storage", "icloud",
        "chatgpt", "openai", "claude", "anthropic",
        "gym", "fitness", "planet fitness", "anytime fitness",
        "nordvpn", "expressvpn", "surfshark",
        "audible", "kindle", "scribd",
        "crunchyroll", "paramount", "peacock", "apple tv",
    ]

    /// Known transfer/self-payment keywords.
    static let transferKeywords: [String] = [
        "transfer", "xfer", "internal", "own account",
        "savings", "checking", "credit card payment",
        "payment to", "payment from", "self",
    ]
}

// ══════════════════════════════════════════════════════════════
// MARK: - Text Parser
// ══════════════════════════════════════════════════════════════

/// Parses free-form text into candidate transactions.
/// Handles pasted transaction lists, receipt text, and messy statement rows.
enum IngestionTextParser {

    /// Parse raw text into candidate rows. Each row has (merchant, amount, date, rawLine).
    static func parse(_ text: String) -> [ParsedRow] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return [] }

        // Detect if this is receipt-style (has "total" keyword)
        if isReceiptText(lines) {
            return parseReceipt(lines)
        }

        // Try line-by-line transaction parsing
        return lines.compactMap { parseLine($0) }
    }

    struct ParsedRow {
        let rawText: String
        let merchant: String
        let amount: Int          // cents
        let date: Date?
        let isIncome: Bool
        let isReceiptTotal: Bool
    }

    // MARK: - Line Parsing

    /// Parse a single line into a transaction row.
    private static func parseLine(_ line: String) -> ParsedRow? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }

        // Extract amount
        guard let amountResult = extractAmount(from: trimmed) else { return nil }

        // Extract date
        let dateResult = extractDate(from: trimmed)

        // Everything that isn't amount or date is the merchant
        var merchantText = trimmed
        merchantText = removePattern(amountResult.matched, from: merchantText)
        if let dateMatch = dateResult?.matched {
            merchantText = removePattern(dateMatch, from: merchantText)
        }

        // Clean up separators and whitespace
        merchantText = merchantText
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "|-–—•·,;")))
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !merchantText.isEmpty || amountResult.cents > 0 else { return nil }

        return ParsedRow(
            rawText: trimmed,
            merchant: merchantText.isEmpty ? "Unknown" : merchantText,
            amount: amountResult.cents,
            date: dateResult?.date,
            isIncome: amountResult.isNegative, // negative in statement = credit/income
            isReceiptTotal: false
        )
    }

    // MARK: - Receipt Detection

    private static func isReceiptText(_ lines: [String]) -> Bool {
        let joined = lines.joined(separator: " ").lowercased()
        let receiptKeywords = ["total", "subtotal", "tax", "change", "receipt",
                               "thank you", "gesamt", "summe", "جمع", "مجموع"]
        let matchCount = receiptKeywords.filter { joined.contains($0) }.count
        return matchCount >= 2
    }

    private static func parseReceipt(_ lines: [String]) -> [ParsedRow] {
        // 1. Extract merchant (first meaningful non-numeric line)
        var merchant = "Receipt"
        for line in lines.prefix(5) {
            let lower = line.lowercased()
            if lower.count >= 3,
               extractAmount(from: line) == nil,
               extractDate(from: line) == nil,
               !lower.contains("receipt"),
               !lower.contains("invoice") {
                merchant = line
                break
            }
        }

        // 2. Find total
        var totalAmount: Int?
        let totalKeywords = ["total", "sum", "gesamt", "summe", "amount due",
                             "balance", "جمع", "مجموع", "grand total"]
        for line in lines.reversed() {
            let lower = line.lowercased()
            if totalKeywords.contains(where: { lower.contains($0) }),
               let amt = extractAmount(from: line) {
                totalAmount = amt.cents
                break
            }
        }

        // Fallback: largest amount in last 5 lines
        if totalAmount == nil {
            var maxAmt = 0
            for line in lines.suffix(5) {
                if let amt = extractAmount(from: line), amt.cents > maxAmt {
                    maxAmt = amt.cents
                }
            }
            if maxAmt > 0 { totalAmount = maxAmt }
        }

        // 3. Extract date
        var receiptDate: Date?
        for line in lines {
            if let dr = extractDate(from: line) {
                receiptDate = dr.date
                break
            }
        }

        guard let total = totalAmount, total > 0 else { return [] }

        return [ParsedRow(
            rawText: lines.joined(separator: "\n"),
            merchant: merchant,
            amount: total,
            date: receiptDate,
            isIncome: false,
            isReceiptTotal: true
        )]
    }

    // MARK: - Amount Extraction

    struct AmountResult {
        let cents: Int
        let isNegative: Bool
        let matched: String
    }

    /// Extract an amount from text. Supports $5.50, 5,50€, 5.50, -$18.20 etc.
    static func extractAmount(from text: String) -> AmountResult? {
        // Pattern: optional sign, optional currency, digits with optional decimal
        let patterns = [
            // $5.50, -$18.20, $1,234.56
            #"(-?\$\s*[\d,]+\.?\d{0,2})"#,
            // 5.50€, 18,20€, 1.234,56€
            #"(-?[\d.]+,\d{2}\s*[€£])"#,
            // 5,50 €
            #"(-?[\d.]+,\d{2})\s*(?:€|EUR|eur)"#,
            // Plain number with decimal: 5.50, 18.20, 1234.56
            #"(?:^|[\s\-|])(-?\d{1,6}\.\d{2})(?:$|[\s\-|])"#,
            // Plain number with comma decimal (European): 5,50
            #"(?:^|[\s\-|])(-?\d{1,6},\d{2})(?:$|[\s\-|])"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)

            if let match = regex.firstMatch(in: text, range: range) {
                let matchRange = match.range(at: 1)
                guard let swiftRange = Range(matchRange, in: text) else { continue }
                let raw = String(text[swiftRange])

                if let cents = parseAmountToCents(raw) {
                    return AmountResult(
                        cents: abs(cents),
                        isNegative: cents < 0 || raw.contains("-"),
                        matched: raw
                    )
                }
            }
        }
        return nil
    }

    /// Convert a raw amount string to cents.
    private static func parseAmountToCents(_ raw: String) -> Int? {
        var cleaned = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "EUR", with: "")
            .replacingOccurrences(of: "eur", with: "")
            .trimmingCharacters(in: .whitespaces)

        let isNegative = cleaned.hasPrefix("-")
        cleaned = cleaned.replacingOccurrences(of: "-", with: "")

        // Detect European format: 1.234,56 → remove dots, replace comma with dot
        if cleaned.contains(",") {
            if cleaned.contains(".") && cleaned.lastIndex(of: ",")! > cleaned.lastIndex(of: ".")! {
                // 1.234,56 → European
                cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
            } else if !cleaned.contains(".") {
                // 5,50 → European
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            }
            // else: 1,234.56 → US format, remove commas
        }

        cleaned = cleaned.replacingOccurrences(of: ",", with: "")

        guard let value = Double(cleaned) else { return nil }
        let cents = Int(round(value * 100))
        return isNegative ? -cents : cents
    }

    // MARK: - Date Extraction

    struct DateResult {
        let date: Date
        let matched: String
    }

    static func extractDate(from text: String) -> DateResult? {
        let patterns: [(String, String)] = [
            // ISO: 2026-04-08
            (#"\b(\d{4}-\d{2}-\d{2})\b"#, "yyyy-MM-dd"),
            // US: 04/08/2026, 4/8/2026
            (#"\b(\d{1,2}/\d{1,2}/\d{4})\b"#, "M/d/yyyy"),
            // EU: 08.04.2026
            (#"\b(\d{1,2}\.\d{1,2}\.\d{4})\b"#, "dd.MM.yyyy"),
            // Short year: 04/08/26
            (#"\b(\d{1,2}/\d{1,2}/\d{2})\b"#, "M/d/yy"),
            // ISO short: 2026-04
            (#"\b(\d{4}-\d{2}-\d{2})"#, "yyyy-MM-dd"),
            // Mon DD: Apr 08
            (#"\b((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2})\b"#, "MMM d"),
        ]

        for (pattern, format) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)

            if let match = regex.firstMatch(in: text, range: range) {
                let matchRange = match.range(at: 1)
                guard let swiftRange = Range(matchRange, in: text) else { continue }
                let dateStr = String(text[swiftRange])

                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.dateFormat = format

                if var date = df.date(from: dateStr) {
                    // If year is missing (Mon DD format), use current year
                    let cal = Calendar.current
                    if format == "MMM d" {
                        var comps = cal.dateComponents([.month, .day], from: date)
                        comps.year = cal.component(.year, from: Date())
                        date = cal.date(from: comps) ?? date
                    }
                    return DateResult(date: date, matched: dateStr)
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func removePattern(_ pattern: String, from text: String) -> String {
        guard !pattern.isEmpty else { return text }
        return text.replacingOccurrences(of: pattern, with: "")
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: - Ingestion Engine
// ══════════════════════════════════════════════════════════════

@MainActor
class AIIngestionEngine: ObservableObject {
    static let shared = AIIngestionEngine()

    @Published var activeSession: IngestionSession?

    private let categorySuggester = AICategorySuggester.shared
    private let merchantMemory = AIMerchantMemory.shared
    private let duplicateDetector = AIDuplicateDetector.shared
    private let actionHistory = AIActionHistory.shared

    private init() {}

    // ══════════════════════════════════════════════════════════
    // MARK: - Public API
    // ══════════════════════════════════════════════════════════

    /// Ingest raw text: parse, normalize, detect flags, stage for review.
    func ingest(rawText: String, sourceType: IngestionSourceType, store: Store) -> IngestionSession {
        let groupId = UUID()

        // 1. Parse raw text into rows
        let parsedRows = IngestionTextParser.parse(rawText)

        // 2. Convert rows to candidate transactions
        var candidates = parsedRows.map { row in
            buildCandidate(from: row, store: store)
        }

        // 3. Detect duplicates against existing transactions
        detectDuplicates(&candidates, existingTransactions: store.transactions)

        // 4. Detect recurring/subscription/transfer patterns
        detectRecurring(&candidates, store: store)
        detectSubscriptions(&candidates)
        detectTransfers(&candidates, store: store)

        // 5. Compute final confidence and review flags
        computeConfidenceAndFlags(&candidates)

        let session = IngestionSession(
            id: UUID(),
            sourceType: sourceType,
            rawInput: rawText,
            candidates: candidates,
            status: candidates.isEmpty ? .failed : .staged,
            startedAt: Date(),
            groupId: groupId,
            parseErrors: candidates.isEmpty ? ["No transactions could be parsed from this text."] : []
        )

        activeSession = session
        return session
    }

    /// Auto-approve all safe candidates (high confidence, no flags).
    func autoApproveSafe() {
        guard var session = activeSession else { return }
        for i in session.candidates.indices {
            let c = session.candidates[i]
            if c.confidence >= 0.75 && !c.requiresReview && c.approval == .pending {
                session.candidates[i].approval = .approved
            }
        }
        activeSession = session
    }

    /// Toggle approval on a specific candidate.
    func toggleApproval(_ candidateId: UUID) {
        guard var session = activeSession else { return }
        guard let idx = session.candidates.firstIndex(where: { $0.id == candidateId }) else { return }

        switch session.candidates[idx].approval {
        case .pending, .rejected:
            session.candidates[idx].approval = .approved
        case .approved:
            session.candidates[idx].approval = .rejected
        }
        activeSession = session
    }

    /// Set approval on a specific candidate.
    func setApproval(_ candidateId: UUID, to status: CandidateTransaction.ApprovalStatus) {
        guard var session = activeSession else { return }
        guard let idx = session.candidates.firstIndex(where: { $0.id == candidateId }) else { return }
        session.candidates[idx].approval = status
        activeSession = session
    }

    /// Import all approved candidates into the store.
    func importApproved(store: inout Store) async -> IngestionImportResult {
        guard var session = activeSession else {
            return IngestionImportResult(importedCount: 0, failedCount: 0, skippedCount: 0,
                                         summary: "No active session")
        }

        session.status = .importing
        activeSession = session

        let approved = session.candidates.filter { $0.approval == .approved }
        let skipped = session.candidates.count - approved.count

        var imported = 0
        var failed = 0

        for candidate in approved {
            let action = candidateToAction(candidate)
            let result = await AIActionExecutor.execute(action, store: &store)

            if result.success {
                imported += 1
                // Record in audit history
                actionHistory.record(
                    action: action,
                    result: result,
                    trustDecision: nil,
                    classification: nil,
                    groupId: session.groupId,
                    groupLabel: "Import: \(session.sourceType.title)",
                    isAutoExecuted: candidate.confidence >= 0.75
                )

                // Teach merchant memory
                if let cat = candidate.category {
                    merchantMemory.learnFromTransaction(
                        note: candidate.normalizedMerchant,
                        category: cat.storageKey,
                        amount: candidate.amount
                    )
                }
            } else {
                failed += 1
            }
        }

        session.status = .completed
        session.completedAt = Date()
        activeSession = session

        let summary = "Imported \(imported) transaction(s)" +
            (failed > 0 ? ", \(failed) failed" : "") +
            (skipped > 0 ? ", \(skipped) skipped" : "")

        return IngestionImportResult(
            importedCount: imported,
            failedCount: failed,
            skippedCount: skipped,
            summary: summary
        )
    }

    /// Dismiss the current session.
    func dismiss() {
        activeSession = nil
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Candidate Builder
    // ══════════════════════════════════════════════════════════

    private func buildCandidate(from row: IngestionTextParser.ParsedRow, store: Store) -> CandidateTransaction {
        let normalized = MerchantNormalizer.normalize(row.merchant)

        // Phase 7: Use unified memory retrieval for category suggestion
        var category: Category? = nil
        var catConfidence: Double = 0

        if let memorySuggestion = AIMemoryRetrieval.suggestCategory(for: normalized),
           let cat = Category(storageKey: memorySuggestion.category) {
            category = cat
            catConfidence = memorySuggestion.confidence
        }

        return CandidateTransaction(
            id: UUID(),
            rawText: row.rawText,
            merchant: row.merchant,
            normalizedMerchant: normalized,
            amount: row.amount,
            date: row.date ?? Date(),
            transactionType: row.isIncome ? .income : .expense,
            category: category,
            categoryConfidence: catConfidence,
            confidence: 0 // computed later
        )
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Duplicate Detection
    // ══════════════════════════════════════════════════════════

    private func detectDuplicates(_ candidates: inout [CandidateTransaction], existingTransactions: [Transaction]) {
        let cal = Calendar.current

        for i in candidates.indices {
            let c = candidates[i]

            for existing in existingTransactions {
                var matchScore: Double = 0
                var reasons: [String] = []

                // Same amount
                if abs(c.amount - existing.amount) < 100 { // within $1
                    matchScore += 0.3
                    if c.amount == existing.amount {
                        matchScore += 0.1
                        reasons.append("exact amount")
                    } else {
                        reasons.append("similar amount")
                    }
                } else {
                    continue // amount must be close
                }

                // Same date
                if cal.isDate(c.date, inSameDayAs: existing.date) {
                    matchScore += 0.3
                    reasons.append("same date")
                } else {
                    // ±1 day
                    let dayDiff = abs(cal.dateComponents([.day], from: c.date, to: existing.date).day ?? 99)
                    if dayDiff <= 1 {
                        matchScore += 0.15
                        reasons.append("±1 day")
                    }
                }

                // Merchant similarity
                if MerchantNormalizer.areSameMerchant(c.normalizedMerchant, existing.note) {
                    matchScore += 0.3
                    reasons.append("same merchant")
                }

                if matchScore >= 0.5 {
                    candidates[i].isDuplicateSuspect = true
                    candidates[i].duplicateOfId = existing.id
                    candidates[i].duplicateConfidence = min(matchScore, 0.95)
                    candidates[i].duplicateReason = reasons.joined(separator: ", ")
                    break // one match is enough
                }
            }
        }

        // Also check within the batch itself
        for i in candidates.indices {
            for j in (i + 1)..<candidates.count {
                if candidates[i].amount == candidates[j].amount,
                   Calendar.current.isDate(candidates[i].date, inSameDayAs: candidates[j].date),
                   MerchantNormalizer.areSameMerchant(candidates[i].normalizedMerchant, candidates[j].normalizedMerchant) {
                    candidates[j].isDuplicateSuspect = true
                    candidates[j].duplicateReason = "duplicate within this import"
                    candidates[j].duplicateConfidence = 0.8
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Recurring Detection
    // ══════════════════════════════════════════════════════════

    private func detectRecurring(_ candidates: inout [CandidateTransaction], store: Store) {
        let existing = store.recurringTransactions.filter(\.isActive)

        for i in candidates.indices {
            let c = candidates[i]

            // Check against known recurring transactions
            for rec in existing {
                if MerchantNormalizer.areSameMerchant(c.normalizedMerchant, rec.name) {
                    let amountMatch = abs(c.amount - rec.amount) < max(100, rec.amount / 10) // within $1 or 10%
                    if amountMatch {
                        candidates[i].isRecurringSuspect = true
                        candidates[i].recurringHint = "Matches recurring: \(rec.name) (\(rec.frequency.rawValue))"
                        break
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Subscription Detection
    // ══════════════════════════════════════════════════════════

    private func detectSubscriptions(_ candidates: inout [CandidateTransaction]) {
        let knownSubs = SubscriptionEngine.shared.subscriptions.filter { $0.status == .active }

        for i in candidates.indices {
            let c = candidates[i]
            let lower = c.normalizedMerchant.lowercased()

            // Check against known subscription merchants
            if MerchantNormalizer.subscriptionMerchants.contains(where: { lower.contains($0) }) {
                candidates[i].isSubscriptionSuspect = true
                candidates[i].subscriptionHint = "Looks like a subscription service"
            }

            // Check against existing detected subscriptions
            for sub in knownSubs {
                if MerchantNormalizer.areSameMerchant(c.normalizedMerchant, sub.merchantName) {
                    candidates[i].isSubscriptionSuspect = true
                    candidates[i].subscriptionHint = "Matches subscription: \(sub.merchantName)"

                    // Also mark as recurring
                    if !candidates[i].isRecurringSuspect {
                        candidates[i].isRecurringSuspect = true
                        candidates[i].recurringHint = "Known subscription charge"
                    }
                    break
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Transfer Detection
    // ══════════════════════════════════════════════════════════

    private func detectTransfers(_ candidates: inout [CandidateTransaction], store: Store) {
        let accounts = AccountManager.shared.activeAccounts
        let accountNames = accounts.map { $0.name.lowercased() }

        for i in candidates.indices {
            let lower = candidates[i].normalizedMerchant.lowercased()

            // Check for transfer keywords
            let hasTransferKeyword = MerchantNormalizer.transferKeywords.contains { lower.contains($0) }

            // Check if merchant matches an account name
            let matchesAccount = accountNames.first { name in
                lower.contains(name) || MerchantNormalizer.areSameMerchant(lower, name)
            }

            if hasTransferKeyword || matchesAccount != nil {
                candidates[i].isTransferSuspect = true
                if let acct = matchesAccount {
                    candidates[i].transferAccountHint = "May be a transfer to/from: \(acct)"
                } else {
                    candidates[i].transferAccountHint = "Contains transfer-related keywords"
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Confidence + Review Flags
    // ══════════════════════════════════════════════════════════

    private func computeConfidenceAndFlags(_ candidates: inout [CandidateTransaction]) {
        for i in candidates.indices {
            var conf: Double = 0.5 // baseline
            var reasons: [String] = []

            let c = candidates[i]

            // Amount present and positive
            if c.amount > 0 { conf += 0.1 }

            // Date was parsed (not defaulting to today)
            // We can't easily tell if date was parsed vs defaulted,
            // but rawText containing a date pattern is a signal
            if IngestionTextParser.extractDate(from: c.rawText) != nil {
                conf += 0.1
            }

            // Category suggestion exists
            if c.category != nil {
                conf += c.categoryConfidence * 0.2 // up to +0.2
            }

            // Merchant was normalized to something meaningful
            if !c.normalizedMerchant.isEmpty && c.normalizedMerchant != "Unknown" {
                conf += 0.1
            }

            // ── Penalties ──

            if c.isDuplicateSuspect {
                conf -= 0.25
                reasons.append("Possible duplicate")
            }

            if c.isTransferSuspect {
                conf -= 0.15
                reasons.append("May be a transfer, not spending")
            }

            if c.amount == 0 {
                conf -= 0.3
                reasons.append("Zero amount")
            }

            if c.normalizedMerchant == "Unknown" || c.normalizedMerchant.isEmpty {
                conf -= 0.2
                reasons.append("Unknown merchant")
            }

            // ── Review required? ──
            let needsReview = conf < 0.6
                || c.isDuplicateSuspect
                || c.isTransferSuspect
                || c.category == nil
                || (c.category != nil && c.categoryConfidence < 0.5)

            if c.category == nil { reasons.append("No category suggestion") }
            if c.category != nil && c.categoryConfidence < 0.5 { reasons.append("Low category confidence") }

            candidates[i].confidence = max(0, min(1, conf))
            candidates[i].requiresReview = needsReview
            candidates[i].reviewReasons = reasons
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Conversion
    // ══════════════════════════════════════════════════════════

    private func candidateToAction(_ candidate: CandidateTransaction) -> AIAction {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        return AIAction(
            type: .addTransaction,
            params: AIAction.ActionParams(
                amount: candidate.amount,
                category: candidate.category?.storageKey ?? "other",
                note: candidate.normalizedMerchant,
                date: df.string(from: candidate.date),
                transactionType: candidate.transactionType == .income ? "income" : "expense"
            )
        )
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Helpers
    // ══════════════════════════════════════════════════════════

    private func fmtCents(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100.0)
    }
}
