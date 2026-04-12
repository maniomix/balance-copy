import Foundation
import Combine
import Vision
import UIKit

// ============================================================
// MARK: - AI Receipt Scanner
// ============================================================
//
// Uses Apple Vision framework to OCR receipts and extract:
//   • Total amount
//   • Merchant/store name
//   • Date
//   • Individual line items (best-effort)
//
// Runs entirely on-device — no data leaves the phone.
//
// ============================================================

/// Parsed receipt data from OCR.
struct ReceiptData: Equatable {
    var merchantName: String?
    var totalAmount: Int?        // cents
    var date: Date?
    var lineItems: [LineItem]
    var rawText: String          // full OCR output for fallback

    struct LineItem: Equatable, Identifiable {
        let id = UUID()
        let description: String
        let amount: Int          // cents
    }
}

@MainActor
class AIReceiptScanner: ObservableObject {
    static let shared = AIReceiptScanner()

    @Published var isScanning: Bool = false
    @Published var lastResult: ReceiptData?
    @Published var errorMessage: String?

    private init() {}

    // MARK: - Scan

    /// Scan a UIImage for receipt data using Vision OCR.
    func scan(image: UIImage) async -> ReceiptData? {
        guard let cgImage = image.cgImage else {
            errorMessage = "Invalid image"
            return nil
        }

        isScanning = true
        errorMessage = nil

        let recognizedText = await performOCR(cgImage: cgImage)

        guard !recognizedText.isEmpty else {
            isScanning = false
            errorMessage = "No text found in image"
            return nil
        }

        let rawText = recognizedText.joined(separator: "\n")
        let result = parseReceipt(lines: recognizedText, rawText: rawText)

        lastResult = result
        isScanning = false
        return result
    }

    // MARK: - Vision OCR

    private func performOCR(cgImage: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let lines = observations.compactMap { observation -> String? in
                    observation.topCandidates(1).first?.string
                }
                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "de-DE", "fa-IR"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Receipt Parsing

    private func parseReceipt(lines: [String], rawText: String) -> ReceiptData {
        var merchantName: String?
        var totalAmount: Int?
        var date: Date?
        var lineItems: [ReceiptData.LineItem] = []

        // Merchant: usually the first non-empty, non-numeric line
        for line in lines.prefix(5) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 3 && !isNumericLine(trimmed) && !isDateLine(trimmed) {
                merchantName = trimmed
                break
            }
        }

        // Find total amount — look for "total", "sum", "gesamt", "جمع"
        let totalPatterns = [
            "(?:total|sum|gesamt|summe|جمع|مجموع|amount due|balance due|to pay)\\s*[:\\-]?\\s*[$€]?\\s*([\\d.,]+)",
            "[$€]\\s*([\\d.,]+)\\s*(?:total|sum|gesamt)"
        ]
        for line in lines.reversed() { // Total is usually near the bottom
            let lower = line.lowercased()
            for pattern in totalPatterns {
                if let amount = extractAmountWithPattern(pattern, from: lower) {
                    totalAmount = amount
                    break
                }
            }
            if totalAmount != nil { break }
        }

        // If no labeled total found, take the largest amount
        if totalAmount == nil {
            var maxAmount = 0
            for line in lines {
                if let amount = extractAnyAmount(from: line), amount > maxAmount {
                    maxAmount = amount
                }
            }
            if maxAmount > 0 { totalAmount = maxAmount }
        }

        // Date extraction
        for line in lines {
            if let d = extractDate(from: line) {
                date = d
                break
            }
        }

        // Line items: lines that have a description + amount
        let itemPattern = "^(.+?)\\s+[$€]?([\\d]+[.,][\\d]{2})\\s*$"
        if let regex = try? NSRegularExpression(pattern: itemPattern) {
            for line in lines {
                let range = NSRange(line.startIndex..., in: line)
                if let match = regex.firstMatch(in: line, range: range) {
                    if let descRange = Range(match.range(at: 1), in: line),
                       let amtRange = Range(match.range(at: 2), in: line) {
                        let desc = String(line[descRange]).trimmingCharacters(in: .whitespaces)
                        let amtStr = String(line[amtRange]).replacingOccurrences(of: ",", with: ".")
                        if let value = Double(amtStr) {
                            let cents = Int(value * 100)
                            // Skip if it's the total
                            if cents != totalAmount && desc.count >= 2 {
                                lineItems.append(ReceiptData.LineItem(description: desc, amount: cents))
                            }
                        }
                    }
                }
            }
        }

        return ReceiptData(
            merchantName: merchantName,
            totalAmount: totalAmount,
            date: date,
            lineItems: lineItems,
            rawText: rawText
        )
    }

    // MARK: - Extraction Helpers

    private func extractAmountWithPattern(_ pattern: String, from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }

        let amtStr = String(text[range])
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)

        guard let value = Double(amtStr) else { return nil }
        return Int(value * 100)
    }

    private func extractAnyAmount(from line: String) -> Int? {
        let pattern = "[$€]\\s*([\\d]+[.,][\\d]{2})|([\\d]+[.,][\\d]{2})\\s*[$€]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        for i in 1...2 {
            let range = match.range(at: i)
            if range.location != NSNotFound, let r = Range(range, in: line) {
                let amtStr = String(line[r]).replacingOccurrences(of: ",", with: ".")
                if let value = Double(amtStr) {
                    return Int(value * 100)
                }
            }
        }
        return nil
    }

    private func extractDate(from line: String) -> Date? {
        let patterns = [
            "\\b(\\d{1,2})[./\\-](\\d{1,2})[./\\-](\\d{2,4})\\b",  // DD/MM/YYYY or MM/DD/YYYY
            "\\b(\\d{4})[./\\-](\\d{1,2})[./\\-](\\d{1,2})\\b"     // YYYY-MM-DD
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                continue
            }

            let groups = (1...3).compactMap { i -> String? in
                let range = match.range(at: i)
                guard range.location != NSNotFound, let r = Range(range, in: line) else { return nil }
                return String(line[r])
            }

            guard groups.count == 3 else { continue }

            let df = DateFormatter()
            // Try common formats
            for fmt in ["dd/MM/yyyy", "MM/dd/yyyy", "dd.MM.yyyy", "yyyy-MM-dd", "dd-MM-yyyy"] {
                df.dateFormat = fmt
                let fullRange = match.range(at: 0)
                if let r = Range(fullRange, in: line) {
                    if let d = df.date(from: String(line[r])) { return d }
                }
            }
        }
        return nil
    }

    private func isNumericLine(_ line: String) -> Bool {
        let digits = line.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "$" || $0 == "€" }
        return digits.count > line.count / 2
    }

    private func isDateLine(_ line: String) -> Bool {
        extractDate(from: line) != nil
    }

    // MARK: - Convert to Transaction

    /// Convert scanned receipt to an AIAction for adding a transaction.
    func toAction(from receipt: ReceiptData, category: Category? = nil) -> AIAction? {
        guard let amount = receipt.totalAmount else { return nil }

        let suggestedCategory: String
        if let cat = category {
            suggestedCategory = cat.storageKey
        } else if let merchant = receipt.merchantName {
            suggestedCategory = AICategorySuggester.shared.suggest(note: merchant)?.storageKey ?? "other"
        } else {
            suggestedCategory = "other"
        }

        let dateStr: String
        if let d = receipt.date {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            dateStr = f.string(from: d)
        } else {
            dateStr = "today"
        }

        return AIAction(
            type: .addTransaction,
            params: AIAction.ActionParams(
                amount: amount,
                category: suggestedCategory,
                note: receipt.merchantName ?? "Receipt scan",
                date: dateStr,
                transactionType: "expense"
            )
        )
    }
}
