import Foundation

/// Fetches Codex/ChatGPT usage from `chatgpt.com/backend-api/wham/usage` and refreshes
/// OAuth tokens via `auth.openai.com`. Hosts are validated; tokens are never logged.
/// Refreshed tokens are kept IN MEMORY only — this app never writes to `~/.codex/auth.json`
/// (that file belongs to the Codex CLI).
actor CodexAPIClient {

    enum APIError: LocalizedError {
        case invalidURL
        case tokenInvalid
        case http(Int)
        case decoding

        var errorDescription: String? {
            switch self {
            case .invalidURL:      return "Invalid Codex API URL"
            case .tokenInvalid:    return "Codex session expired"
            case .http(let code):  return "Codex API error (HTTP \(code))"
            case .decoding:        return "Unexpected Codex API response"
            }
        }
    }

    // MARK: - Response models (defensive decoding — a malformed extra must never
    // disturb the primary/weekly mapping)

    struct UsageResponse: Decodable {
        let planType: String?
        let rateLimit: RateLimitDetails?
        let additionalRateLimits: [AdditionalRateLimit]?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
            case additionalRateLimits = "additional_rate_limits"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.planType = try? container.decodeIfPresent(String.self, forKey: .planType)
            self.rateLimit = try? container.decodeIfPresent(RateLimitDetails.self, forKey: .rateLimit)
            let lossy = try? container.decodeIfPresent([LossyAdditionalRateLimit].self, forKey: .additionalRateLimits)
            self.additionalRateLimits = lossy?.compactMap(\.value)
        }
    }

    struct RateLimitDetails: Decodable {
        let primaryWindow: WindowSnapshot?
        let secondaryWindow: WindowSnapshot?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.primaryWindow = try? container.decodeIfPresent(WindowSnapshot.self, forKey: .primaryWindow)
            self.secondaryWindow = try? container.decodeIfPresent(WindowSnapshot.self, forKey: .secondaryWindow)
        }
    }

    struct WindowSnapshot: Decodable {
        let usedPercent: Double
        let resetAt: Double?           // epoch seconds
        let limitWindowSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // The API has served both integer and floating percentages — accept either.
            if let d = try? container.decode(Double.self, forKey: .usedPercent) {
                self.usedPercent = d
            } else {
                self.usedPercent = Double(try container.decode(Int.self, forKey: .usedPercent))
            }
            if let d = try? container.decodeIfPresent(Double.self, forKey: .resetAt) {
                self.resetAt = d
            } else if let i = try? container.decodeIfPresent(Int.self, forKey: .resetAt) {
                self.resetAt = Double(i)
            } else {
                self.resetAt = nil
            }
            self.limitWindowSeconds = try? container.decodeIfPresent(Int.self, forKey: .limitWindowSeconds)
        }
    }

    /// A named, model-specific limit (e.g. a promotional "GPT-5.3-Codex-Spark") whose
    /// windows reuse the primary/weekly shape. The set is dynamic — render what arrives.
    struct AdditionalRateLimit: Decodable {
        let limitName: String?
        let rateLimit: RateLimitDetails?

        enum CodingKeys: String, CodingKey {
            case limitName = "limit_name"
            case rateLimit = "rate_limit"
        }
    }

    /// Decodes one `additional_rate_limits` element without throwing so a single
    /// malformed entry cannot discard its valid siblings.
    private struct LossyAdditionalRateLimit: Decodable {
        let value: AdditionalRateLimit?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.value = try? container.decode(AdditionalRateLimit.self)
        }
    }

    // MARK: - Session

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 1
        self.session = URLSession(configuration: config)
    }

    // MARK: - Usage

    func fetchUsage(accessToken: String, accountId: String?) async throws -> UsageResponse {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage"),
              url.host == "chatgpt.com" else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CursorMeterFS", forHTTPHeaderField: "User-Agent")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.decoding }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw APIError.tokenInvalid
        default: throw APIError.http(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    // MARK: - Token refresh (in-memory only)

    private static let refreshClientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    func refreshAccessToken(refreshToken: String) async throws -> String {
        guard let url = URL(string: "https://auth.openai.com/oauth/token"),
              url.host == "auth.openai.com" else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_id": Self.refreshClientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newToken = json["access_token"] as? String else {
            throw APIError.tokenInvalid
        }
        return newToken
    }
}
