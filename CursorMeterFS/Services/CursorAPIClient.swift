import Foundation

/// Fetches Cursor usage data from the official cursor.com API.
///
/// Security contract:
/// - All requests go ONLY to `https://cursor.com` — host is validated before every call.
/// - The session token is sent only in the `Cookie` header of HTTPS requests; never logged.
/// - All `Codable` structs use optional fields for defensive parsing.
/// - Timeout: 15 s; retry: up to 2 attempts with exponential backoff on transient errors.
/// - On 401: signals `TokenInvalid` so the caller can refresh/re-read from SQLite.
actor CursorAPIClient {

    // MARK: - Errors
    enum APIError: Error, LocalizedError {
        case invalidHost(String)
        case httpError(Int)
        case tokenInvalid              // 401 — trigger re-auth
        case rateLimited               // 429
        case decodingError(Error)
        case noData
        case timeout

        var errorDescription: String? {
            switch self {
            case .invalidHost(let h):    return "Blocked request to unexpected host: \(h)"
            case .httpError(let code):   return "HTTP \(code)"
            case .tokenInvalid:          return "Session expired — re-reading from Cursor."
            case .rateLimited:           return "Rate limited (429). Backing off."
            case .decodingError(let e):  return "Response parsing failed: \(e.localizedDescription)"
            case .noData:                return "Empty response body."
            case .timeout:               return "Request timed out."
            }
        }
    }

    // MARK: - Config
    private let allowedHost = "cursor.com"
    private let baseURL     = "https://cursor.com"
    private let timeout: TimeInterval = 15
    private let maxRetries = 2

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 15
        config.timeoutIntervalForResource = 30
        // Never cache — always fresh data
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // One connection at a time to be a good API citizen
        config.httpMaximumConnectionsPerHost = 1
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Fetches monthly request quota and usage.
    /// Returns `(used, total/maxRequestUsage, startOfMonth)`.
    func fetchUsage(userId: String, sessionToken: String) async throws -> UsageAPIResponse {
        guard let url = URL(string: "\(baseURL)/api/usage?user=\(userId)") else {
            throw APIError.invalidHost(baseURL)
        }
        try validateHost(url)

        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "GET"
        setCookieHeader(on: &req, token: sessionToken)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await performRequest(req, attempt: 0)
        do {
            return try JSONDecoder().decode(UsageAPIResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Fetches monthly invoice with usage events (model, tokens, cost per request).
    func fetchMonthlyInvoice(
        month: Int,
        year: Int,
        sessionToken: String,
        teamId: Int? = nil,
        includeEvents: Bool = true
    ) async throws -> InvoiceResponse {
        guard let url = URL(string: "\(baseURL)/api/dashboard/get-monthly-invoice") else {
            throw APIError.invalidHost(baseURL)
        }
        try validateHost(url)

        var body: [String: Any] = [
            "month": month,
            "year": year,
            "includeUsageEvents": includeEvents,
        ]
        if let teamId { body["teamId"] = teamId }

        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        setCookieHeader(on: &req, token: sessionToken)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data = try await performRequest(req, attempt: 0)
        do {
            return try JSONDecoder().decode(InvoiceResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Fetches the spending hard limit configuration.
    func fetchHardLimit(sessionToken: String, teamId: Int? = nil) async throws -> HardLimitResponse {
        guard let url = URL(string: "\(baseURL)/api/dashboard/get-hard-limit") else {
            throw APIError.invalidHost(baseURL)
        }
        try validateHost(url)

        var body: [String: Any] = [:]
        if let teamId { body["teamId"] = teamId }

        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        setCookieHeader(on: &req, token: sessionToken)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data = try await performRequest(req, attempt: 0)
        do {
            return try JSONDecoder().decode(HardLimitResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Checks whether on-demand (usage-based) pricing is enabled.
    func fetchUsageBasedEnabled(sessionToken: String, teamId: Int? = nil) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/dashboard/get-usage-based-premium-requests") else {
            throw APIError.invalidHost(baseURL)
        }
        try validateHost(url)

        var body: [String: Any] = [:]
        if let teamId { body["teamId"] = teamId }

        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        setCookieHeader(on: &req, token: sessionToken)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data = try await performRequest(req, attempt: 0)
        struct EnabledResponse: Decodable {
            let usageBasedPremiumRequests: Bool?
        }
        let decoded = (try? JSONDecoder().decode(EnabledResponse.self, from: data))
        return decoded?.usageBasedPremiumRequests ?? false
    }

    // MARK: - Private helpers

    /// Sets auth and CSRF headers required by cursor.com.
    /// Referer is required for POST dashboard endpoints (CSRF check); Origin alone is not enough.
    private func setCookieHeader(on req: inout URLRequest, token: String) {
        // Token is sensitive — never include in log output
        req.setValue("WorkosCursorSessionToken=\(token)", forHTTPHeaderField: "Cookie")
        req.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        req.setValue("https://cursor.com/settings", forHTTPHeaderField: "Referer")
        req.setValue("cursor.com", forHTTPHeaderField: "Host")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
    }

    /// Validates that the URL's host is exactly `cursor.com`.
    private func validateHost(_ url: URL) throws {
        guard let host = url.host, host.hasSuffix(allowedHost) else {
            throw APIError.invalidHost(url.host ?? "nil")
        }
    }

    /// Performs the request with retry + exponential backoff on transient errors.
    private func performRequest(_ req: URLRequest, attempt: Int) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: req)

            guard let http = response as? HTTPURLResponse else {
                throw APIError.noData
            }

            switch http.statusCode {
            case 200...299:
                return data
            case 401, 403:
                throw APIError.tokenInvalid
            case 429:
                // Back off and retry once
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt + 1))) * 1_000_000_000)
                    return try await performRequest(req, attempt: attempt + 1)
                }
                throw APIError.rateLimited
            default:
                if attempt < maxRetries && (500...599).contains(http.statusCode) {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt + 1))) * 1_000_000_000)
                    return try await performRequest(req, attempt: attempt + 1)
                }
                throw APIError.httpError(http.statusCode)
            }
        } catch let error as APIError {
            throw error
        } catch let urlError as URLError where urlError.code == .timedOut {
            if attempt < maxRetries {
                return try await performRequest(req, attempt: attempt + 1)
            }
            throw APIError.timeout
        } catch {
            if attempt < maxRetries {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return try await performRequest(req, attempt: attempt + 1)
            }
            throw error
        }
    }
}

// MARK: - Response models

/// `/api/usage` response — model-keyed usage dictionary.
/// The actual response mixes model dicts with a top-level `startOfMonth` string key,
/// so we use a custom decoder that separates them instead of naive `[String: ModelUsage]`.
struct UsageAPIResponse: Decodable {
    let models: [String: ModelUsage]?
    let topLevelStartOfMonth: String?

    struct ModelUsage: Decodable {
        let numRequests: Int?
        let numRequestsTotal: Int?
        let numTokens: Int?
        let maxRequestUsage: Int?
        let startOfMonth: String?  // present in some API variants inside model dicts
    }

    private struct AnyCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        var parsedModels: [String: ModelUsage] = [:]
        var parsedStart: String?

        for key in container.allKeys {
            if key.stringValue == "startOfMonth" {
                parsedStart = try? container.decode(String.self, forKey: key)
            } else if let model = try? container.decode(ModelUsage.self, forKey: key) {
                parsedModels[key.stringValue] = model
            }
        }

        models = parsedModels.isEmpty ? nil : parsedModels
        topLevelStartOfMonth = parsedStart
    }

    /// Aggregated used requests across all models.
    var totalUsed: Int {
        models?.values.compactMap { $0.numRequests }.reduce(0, +) ?? 0
    }

    /// Max request allocation (dynamic — pick the highest value seen across models).
    var maxRequestUsage: Int? {
        models?.values.compactMap { $0.maxRequestUsage }.max()
    }

    /// Billing cycle start — top-level key (actual API) takes priority over per-model field (some API variants).
    var startOfMonth: String? {
        topLevelStartOfMonth ?? models?.values.compactMap { $0.startOfMonth }.first
    }
}

/// `/api/dashboard/get-monthly-invoice` response.
struct InvoiceResponse: Decodable {
    let usageBasedCents: Int?       // total on-demand spend in cents
    let items: [InvoiceItem]?
    let usageEvents: [UsageEvent.RawItem]?

    enum CodingKeys: String, CodingKey {
        case usageBasedCents
        case items
        case usageEvents
    }

    var totalUSD: Double { Double(usageBasedCents ?? 0) / 100.0 }
}

struct InvoiceItem: Decodable, Identifiable {
    let id: String?
    let description: String?
    let cents: Int?
    var costUSD: Double { Double(cents ?? 0) / 100.0 }
}

/// `/api/dashboard/get-hard-limit` response.
struct HardLimitResponse: Decodable {
    let hardLimit: Double?
    let hardLimitEnabled: Bool?
    let noUsageBasedAllowed: Bool?
}
