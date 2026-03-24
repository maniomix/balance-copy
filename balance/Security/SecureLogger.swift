import Foundation
import os.log

// ============================================================
// MARK: - Secure Logger
// ============================================================
//
// Drop-in replacement for print() that:
//   1. Strips sensitive data (keys, tokens, emails, UUIDs) in production.
//   2. Uses os_log for structured logging.
//   3. Categorises messages for filtering in Console.app.
//   4. Completely suppresses debug-level logs in production.
//
// Usage:
//   SecureLogger.info("User loaded")
//   SecureLogger.error("Sync failed", error)
//   SecureLogger.debug("Raw: \(someDetail)")     // only in dev
//
// ============================================================

enum SecureLogger {

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.centmond.balance"
    private static let logger = Logger(subsystem: subsystem, category: "app")

    // ── Public API ───────────────────────────────────

    static func info(_ message: String) {
        logger.info("\(sanitize(message), privacy: .public)")
    }

    /// Debug logs are completely suppressed outside development.
    static func debug(_ message: String) {
        guard AppConfig.shared.environment.allowsVerboseLogging else { return }
        logger.debug("\(sanitize(message), privacy: .public)")
    }

    static func warning(_ message: String) {
        logger.warning("\(sanitize(message), privacy: .public)")
    }

    static func error(_ message: String, _ error: Error? = nil) {
        let full: String
        if let e = error {
            full = "\(message) — \(sanitizeError(e))"
        } else {
            full = message
        }
        logger.error("\(sanitize(full), privacy: .public)")
    }

    /// Log a security-relevant event (auth failure, injection attempt, etc.).
    /// Always logged regardless of environment, but still sanitized.
    static func security(_ message: String) {
        logger.critical("\(sanitize(message), privacy: .public)")
    }

    // ── Sanitization ─────────────────────────────────

    /// Redacts common secret patterns from log strings.
    static func sanitize(_ text: String) -> String {
        guard !AppConfig.shared.environment.isDebug else { return text }
        var result = text

        // JWT tokens (eyJ...)
        result = result.replacingOccurrences(
            of: "eyJ[A-Za-z0-9_-]{20,}\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+",
            with: "[REDACTED_JWT]",
            options: .regularExpression
        )

        // API keys (AIza..., sk-...)
        result = result.replacingOccurrences(
            of: "AIza[A-Za-z0-9_-]{30,}",
            with: "[REDACTED_KEY]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "sk-[A-Za-z0-9]{20,}",
            with: "[REDACTED_KEY]",
            options: .regularExpression
        )

        // Email addresses
        result = result.replacingOccurrences(
            of: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
            with: "[REDACTED_EMAIL]",
            options: .regularExpression
        )

        // UUIDs (user IDs, transaction IDs)
        result = result.replacingOccurrences(
            of: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
            with: "[REDACTED_ID]",
            options: .regularExpression
        )

        // File paths
        result = result.replacingOccurrences(
            of: "/Users/[^ \"'\\]]+",
            with: "[PATH]",
            options: .regularExpression
        )

        // Bearer tokens in headers
        result = result.replacingOccurrences(
            of: "Bearer [A-Za-z0-9._-]+",
            with: "Bearer [REDACTED]",
            options: .regularExpression
        )

        return result
    }

    /// Sanitize error descriptions — remove stack traces & internal paths.
    private static func sanitizeError(_ error: Error) -> String {
        let desc = error.localizedDescription
        guard !AppConfig.shared.environment.isDebug else { return desc }

        var result = desc
        // Strip file paths
        result = result.replacingOccurrences(
            of: "/Users/[^ ]+",
            with: "[PATH]",
            options: .regularExpression
        )
        // Strip internal Supabase/network details that might leak endpoint info
        result = result.replacingOccurrences(
            of: "https://[^ \"']+",
            with: "[URL]",
            options: .regularExpression
        )
        // Truncate overly long error messages
        if result.count > 300 {
            result = String(result.prefix(300)) + "..."
        }
        return result
    }
}
