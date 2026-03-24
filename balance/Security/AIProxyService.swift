import Foundation

// ============================================================
// MARK: - AI Proxy Service
// ============================================================
//
// Secure wrapper for AI calls. The client NEVER holds a provider
// API key. Instead, requests go through a backend proxy (Supabase
// Edge Function, Cloudflare Worker, or custom server) that:
//
//   1. Validates the user's Supabase JWT.
//   2. Appends the provider API key server-side.
//   3. Forwards to the AI provider.
//   4. Returns the response.
//
// Fallback (development only):
//   If AI_PROXY_BASE_URL is empty AND environment == .development,
//   the service falls back to a local API key from Config.plist
//   under the key "GEMINI_API_KEY_DEV". This is for local testing
//   only and is blocked in staging/production.
//
// Edge Function contract:
//   POST /ai/generate-insights
//   POST /ai/chat
//   Headers:
//     Authorization: Bearer <supabase-jwt>
//     Content-Type: application/json
//   Body: { "prompt": "..." }
//   Response: { "text": "..." }
//
// ============================================================

actor AIProxyService {

    static let shared = AIProxyService()

    // MARK: - Rate Limiting

    private var requestTimestamps: [Date] = []
    private let maxRequestsPerMinute: Int = 10
    private let maxRequestsPerHour: Int = 60

    // MARK: - Request Validation

    private struct ProxyResponse: Codable {
        let text: String?
        let error: String?
    }

    // MARK: - Public API

    /// Generate AI insights through the secure proxy.
    func generateInsights(prompt: String, authToken: String) async throws -> String {
        try validateAuthToken(authToken)
        try checkRateLimit()
        let validated = try validateAndSanitizePrompt(prompt)
        return try await callProxy(endpoint: "ai/generate-insights", prompt: validated, authToken: authToken)
    }

    /// Chat with AI through the secure proxy.
    func chat(prompt: String, authToken: String) async throws -> String {
        try validateAuthToken(authToken)
        try checkRateLimit()
        let validated = try validateAndSanitizePrompt(prompt)
        return try await callProxy(endpoint: "ai/chat", prompt: validated, authToken: authToken)
    }

    // MARK: - Input Validation

    private func validateAuthToken(_ token: String) throws {
        guard !token.isEmpty else {
            throw AIProxyError.unauthorized
        }
    }

    private func validateAndSanitizePrompt(_ prompt: String) throws -> String {
        switch RequestGuard.validatePrompt(prompt) {
        case .success(let sanitized):
            return sanitized
        case .failure(let error):
            throw AIProxyError.serverError(400, AppConfig.shared.safeErrorMessage(detail: error.localizedDescription, fallback: "Invalid input"))
        }
    }

    // MARK: - Core Request

    private func callProxy(endpoint: String, prompt: String, authToken: String) async throws -> String {
        let config = await AppConfig.shared
        let baseURL = config.aiProxyBaseURL

        // ── Production / staging: use proxy ──────────
        if !baseURL.isEmpty {
            return try await proxyRequest(
                url: "\(baseURL)/\(endpoint)",
                prompt: prompt,
                authToken: authToken
            )
        }

        // ── Development fallback: direct call ────────
        let env = config.environment
        guard env == .development else {
            throw AIProxyError.proxyNotConfigured
        }

        SecureLogger.warning("AI proxy not configured — using dev fallback (direct Gemini call)")
        return try await devFallbackGemini(prompt: prompt)
    }

    // MARK: - Proxy Request

    private func proxyRequest(url: String, prompt: String, authToken: String) async throws -> String {
        guard let requestURL = URL(string: url) else {
            throw AIProxyError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        // Apply standard secure headers (includes auth, version, request ID)
        let headers = await RequestGuard.requestHeaders(authToken: authToken)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let body: [String: String] = ["prompt": prompt]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AIProxyError.invalidResponse
        }

        // Validate response using RequestGuard
        switch RequestGuard.validateResponse(data: data, statusCode: http.statusCode) {
        case .failure(let guardError):
            switch guardError {
            case .rateLimited:
                throw AIProxyError.rateLimited
            case .unauthorized:
                throw AIProxyError.unauthorized
            default:
                let safeMessage = await AppConfig.shared.safeErrorMessage(
                    detail: String(data: data, encoding: .utf8) ?? "Unknown error",
                    fallback: "Service temporarily unavailable"
                )
                throw AIProxyError.serverError(http.statusCode, safeMessage)
            }
        case .success:
            break
        }

        let proxyResp = try JSONDecoder().decode(ProxyResponse.self, from: data)
        if let error = proxyResp.error {
            throw AIProxyError.serverError(http.statusCode, error)
        }
        guard let text = proxyResp.text, !text.isEmpty else {
            throw AIProxyError.emptyResponse
        }
        return text
    }

    // MARK: - Dev Fallback (local testing only)

    /// Direct Gemini call for development. Reads key from Config.plist "GEMINI_API_KEY_DEV".
    /// BLOCKED in staging/production.
    private func devFallbackGemini(prompt: String) async throws -> String {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist") ??
                         Bundle.main.path(forResource: "Supabase", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let devKey = dict["GEMINI_API_KEY_DEV"] as? String,
              !devKey.isEmpty else {
            throw AIProxyError.proxyNotConfigured
        }

        let apiURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"
        guard var components = URLComponents(string: apiURL) else {
            throw AIProxyError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "key", value: devKey)]
        guard let url = components.url else {
            throw AIProxyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.7,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 1024
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIProxyError.serverError(
                (response as? HTTPURLResponse)?.statusCode ?? 0,
                "Gemini API error"
            )
        }

        struct GeminiResponse: Codable {
            let candidates: [Candidate]
            struct Candidate: Codable {
                let content: Content
                struct Content: Codable {
                    let parts: [Part]
                    struct Part: Codable { let text: String }
                }
            }
        }

        let gem = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = gem.candidates.first?.content.parts.first?.text else {
            throw AIProxyError.emptyResponse
        }
        return text
    }

    // MARK: - Rate Limiting

    private func checkRateLimit() throws {
        let now = Date()
        // Clean old entries
        requestTimestamps.removeAll { now.timeIntervalSince($0) > 3600 }

        // Per-minute check
        let lastMinute = requestTimestamps.filter { now.timeIntervalSince($0) < 60 }
        if lastMinute.count >= maxRequestsPerMinute {
            throw AIProxyError.rateLimited
        }

        // Per-hour check
        if requestTimestamps.count >= maxRequestsPerHour {
            throw AIProxyError.rateLimited
        }

        requestTimestamps.append(now)
    }
}

// MARK: - Errors

enum AIProxyError: LocalizedError {
    case proxyNotConfigured
    case invalidURL
    case invalidResponse
    case emptyResponse
    case rateLimited
    case serverError(Int, String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .proxyNotConfigured:
            return "AI service is not configured. Please check your setup."
        case .invalidURL:
            return "Invalid service URL."
        case .invalidResponse:
            return "Invalid response from AI service."
        case .emptyResponse:
            return "Empty response from AI service."
        case .rateLimited:
            return "Too many requests. Please wait a moment."
        case .serverError(_, let msg):
            // In production, msg is already sanitized by the caller
            return msg
        case .unauthorized:
            return "Authentication required. Please sign in again."
        }
    }
}
