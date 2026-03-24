import Foundation

// ============================================================
// MARK: - Request Guard
// ============================================================
//
// Client-side protections that complement server-side security:
//
//   1. Input validation   — sanitize prompts before sending
//   2. Abuse prevention   — detect prompt injection patterns
//   3. Request signing    — build safe metadata headers
//   4. Jailbreak guard    — block attempts to extract system prompts
//   5. Field validation   — sanitize user inputs for DB operations
//
// These do NOT replace server-side validation but add defence-in-depth.
// ============================================================

enum RequestGuard {

    // MARK: - Prompt Validation

    /// Validate and sanitize a user prompt before sending to AI.
    static func validatePrompt(_ input: String) -> Result<String, GuardError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .failure(.emptyInput)
        }

        guard trimmed.count <= 4000 else {
            return .failure(.tooLong)
        }

        if containsInjectionPattern(trimmed) {
            SecureLogger.security("Blocked prompt injection attempt")
            return .failure(.suspiciousInput)
        }

        return .success(trimmed)
    }

    // MARK: - Field Validation

    /// Sanitize a text field for storage (notes, names, etc.).
    /// Strips control characters and limits length.
    static func sanitizeField(_ input: String, maxLength: Int = 500) -> String {
        var result = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove control characters (except newlines in notes)
        result = result.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.subtracting(.newlines).contains(scalar)
        }.map(String.init).joined()
        // Enforce length limit
        if result.count > maxLength {
            result = String(result.prefix(maxLength))
        }
        return result
    }

    /// Validate a monetary amount string. Returns cents or nil.
    static func validateAmount(_ input: String) -> Int? {
        let cleaned = input
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned), value >= 0, value < 100_000_000 else {
            return nil
        }
        return Int(value * 100)
    }

    /// Validate a URL string for basic sanity.
    static func validateURL(_ input: String) -> Bool {
        guard let url = URL(string: input) else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }

    // MARK: - Injection Detection

    /// Heuristic patterns that indicate prompt injection.
    private static let injectionPatterns: [String] = [
        "ignore previous instructions",
        "ignore all instructions",
        "disregard your instructions",
        "forget your instructions",
        "reveal your system prompt",
        "show me your prompt",
        "what is your system prompt",
        "output your instructions",
        "print your prompt",
        "repeat the above",
        "you are now",
        "act as a",
        "pretend you are",
        "DAN mode",
        "developer mode",
        "jailbreak",
        "bypass safety",
        "override restrictions",
        "ignore safety",
        "do anything now",
        "<|im_start|>",
        "<|im_end|>",
        "\\[INST\\]",
        "\\[/INST\\]",
        "<system>",
        "</system>"
    ]

    private static func containsInjectionPattern(_ text: String) -> Bool {
        let lower = text.lowercased()
        for pattern in injectionPatterns {
            if pattern.hasPrefix("\\") || pattern.hasPrefix("<") {
                if lower.range(of: pattern, options: .regularExpression) != nil {
                    return true
                }
            } else {
                if lower.contains(pattern) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - SQL/NoSQL Injection Detection

    /// Basic check for SQL injection patterns in user inputs
    /// that will be used in database queries.
    static func containsSQLInjection(_ input: String) -> Bool {
        let lower = input.lowercased()
        let patterns = [
            "'; drop", "'; delete", "'; update", "'; insert",
            "' or '1'='1", "' or 1=1", "'; --",
            "union select", "union all select"
        ]
        return patterns.contains { lower.contains($0) }
    }

    // MARK: - Request Metadata

    /// Build safe metadata headers for proxy requests.
    static func requestHeaders(authToken: String) -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "X-Client-Version": AppConfig.shared.appVersion,
            "X-Client-Platform": "iOS",
            "X-Request-ID": UUID().uuidString
        ]
        if !authToken.isEmpty {
            headers["Authorization"] = "Bearer \(authToken)"
        }
        return headers
    }

    // MARK: - Response Validation

    /// Basic response sanity check.
    static func validateResponse(data: Data, statusCode: Int) -> Result<Data, GuardError> {
        guard (200...299).contains(statusCode) else {
            if statusCode == 401 { return .failure(.unauthorized) }
            if statusCode == 403 { return .failure(.forbidden) }
            if statusCode == 429 { return .failure(.rateLimited) }
            return .failure(.serverError(statusCode))
        }
        guard !data.isEmpty else {
            return .failure(.emptyResponse)
        }
        // Limit response size (10 MB)
        guard data.count < 10_000_000 else {
            return .failure(.responseTooLarge)
        }
        return .success(data)
    }
}

// MARK: - Guard Errors

enum GuardError: LocalizedError {
    case emptyInput
    case tooLong
    case suspiciousInput
    case unauthorized
    case forbidden
    case rateLimited
    case serverError(Int)
    case emptyResponse
    case responseTooLarge
    case invalidAmount

    var errorDescription: String? {
        switch self {
        case .emptyInput: return "Please enter a message."
        case .tooLong: return "Message is too long. Please shorten it."
        case .suspiciousInput: return "This request cannot be processed."
        case .unauthorized: return "Please sign in again."
        case .forbidden: return "You don't have permission for this action."
        case .rateLimited: return "Too many requests. Please wait."
        case .serverError: return "Service error. Please try again."
        case .emptyResponse: return "No response received."
        case .responseTooLarge: return "Response was too large."
        case .invalidAmount: return "Please enter a valid amount."
        }
    }
}
