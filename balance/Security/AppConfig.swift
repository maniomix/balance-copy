import Foundation

// ============================================================
// MARK: - App Configuration
// ============================================================
//
// Secure, environment-aware configuration system.
// Reads from Config.plist at build time.
//
// IMPORTANT:
//   - Config.plist is gitignored; each environment has its own.
//   - Xcode build phases inject the correct plist per scheme.
//   - NEVER hardcode secrets in source code.
//
// Environment hierarchy:
//   development → staging → production
//
// Required keys in Config.plist:
//   SUPABASE_URL          – Supabase project URL
//   SUPABASE_ANON_KEY     – Supabase anonymous key (RLS-protected)
//   AI_PROXY_BASE_URL     – Edge function / backend URL for AI calls
//   ENVIRONMENT           – "development" | "staging" | "production"
//
// Optional:
//   GOOGLE_CLIENT_ID      – OAuth client ID (ok to embed)
//
// ============================================================

enum AppEnvironment: String {
    case development
    case staging
    case production

    var isDebug: Bool { self == .development }
    var allowsVerboseLogging: Bool { self != .production }

    /// Whether this environment should enforce strict security checks.
    var enforcesSecurity: Bool { self != .development }

    /// Whether direct AI provider calls are allowed (dev only).
    var allowsDirectAICalls: Bool { self == .development }

    /// Whether sensitive error details can be shown in UI.
    var showsDetailedErrors: Bool { self == .development }
}

struct AppConfig {

    // MARK: - Singleton

    static let shared: AppConfig = {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist") ??
                         Bundle.main.path(forResource: "Supabase", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            // Crash early in debug; return safe defaults in release.
            #if DEBUG
            fatalError("⛔ Config.plist (or Supabase.plist) not found. See SECURITY.md.")
            #else
            return AppConfig(dict: [:])
            #endif
        }
        return AppConfig(dict: dict)
    }()

    // MARK: - Public Properties

    let supabaseURL: String
    let supabaseAnonKey: String
    let aiProxyBaseURL: String
    let environment: AppEnvironment
    let googleClientID: String

    /// App version for request headers and diagnostics.
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    /// Build number for diagnostics.
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    // MARK: - Init

    private init(dict: [String: Any]) {
        supabaseURL = dict["SUPABASE_URL"] as? String ?? ""
        supabaseAnonKey = dict["SUPABASE_ANON_KEY"] as? String ?? ""
        aiProxyBaseURL = dict["AI_PROXY_BASE_URL"] as? String ?? ""
        googleClientID = dict["GOOGLE_CLIENT_ID"] as? String ?? ""

        let envString = dict["ENVIRONMENT"] as? String ?? "production"
        environment = AppEnvironment(rawValue: envString) ?? .production
    }

    // MARK: - Validation

    /// Call on app launch to surface misconfiguration.
    /// Returns true if configuration is valid for the current environment.
    @discardableResult
    func validate() -> Bool {
        var missing: [String] = []
        var warnings: [String] = []

        if supabaseURL.isEmpty {
            missing.append("SUPABASE_URL")
        } else if !supabaseURL.hasPrefix("https://") {
            warnings.append("SUPABASE_URL should use HTTPS")
        }

        if supabaseAnonKey.isEmpty {
            missing.append("SUPABASE_ANON_KEY")
        }

        // AI proxy required in staging/production
        if environment.enforcesSecurity && aiProxyBaseURL.isEmpty {
            missing.append("AI_PROXY_BASE_URL")
        }

        // Verify proxy URL is HTTPS in non-dev
        if environment.enforcesSecurity && !aiProxyBaseURL.isEmpty && !aiProxyBaseURL.hasPrefix("https://") {
            warnings.append("AI_PROXY_BASE_URL should use HTTPS in \(environment.rawValue)")
        }

        if !missing.isEmpty {
            SecureLogger.error("Missing config keys: \(missing.joined(separator: ", "))")
        }
        for w in warnings {
            SecureLogger.warning(w)
        }

        return missing.isEmpty
    }

    // MARK: - Safe Error Message

    /// Returns an appropriate error message based on environment.
    /// In production, masks internal details. In dev, passes through.
    func safeErrorMessage(detail: String, fallback: String = "Something went wrong. Please try again.") -> String {
        if environment.showsDetailedErrors {
            return detail
        }
        return fallback
    }
}
