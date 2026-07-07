import Foundation

/// Fetches Claude subscription usage from the OAuth usage endpoint
/// (`api.anthropic.com/api/oauth/usage`). Host validated; tokens never logged.
actor ClaudeAPIClient {

    enum APIError: LocalizedError {
        case invalidURL
        case tokenInvalid
        case http(Int)
        case decoding

        var errorDescription: String? {
            switch self {
            case .invalidURL:     return "Invalid Claude API URL"
            case .tokenInvalid:   return "Claude session expired"
            case .http(let code): return "Claude API error (HTTP \(code))"
            case .decoding:       return "Unexpected Claude API response"
            }
        }
    }

    // MARK: - Response models
    // Every field is optional/defensive: the shape evolves (flat `seven_day_*` fields are
    // being superseded by the `limits[]` array) and must degrade gracefully.

    struct UsageResponse: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        let sevenDayOpus: Window?
        let sevenDaySonnet: Window?
        let limits: [LimitEntry]?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDayOpus = "seven_day_opus"
            case sevenDaySonnet = "seven_day_sonnet"
            case limits
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.fiveHour = try? container.decodeIfPresent(Window.self, forKey: .fiveHour)
            self.sevenDay = try? container.decodeIfPresent(Window.self, forKey: .sevenDay)
            self.sevenDayOpus = try? container.decodeIfPresent(Window.self, forKey: .sevenDayOpus)
            self.sevenDaySonnet = try? container.decodeIfPresent(Window.self, forKey: .sevenDaySonnet)
            let lossy = try? container.decodeIfPresent([LossyLimitEntry].self, forKey: .limits)
            self.limits = lossy?.compactMap(\.value)
        }
    }

    struct Window: Decodable {
        let utilization: Double?    // 0–100
        let resetsAt: String?       // ISO8601

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    /// One entry of `limits[]`. `kind`/`group` classify it (e.g. kind "weekly_scoped",
    /// group "weekly"); `scope.model.display_name` names the model when scoped —
    /// fully dynamic (Max plans expose a Sonnet-scoped lane; promo models come and go).
    struct LimitEntry: Decodable {
        let kind: String?
        let group: String?
        let percent: Double?
        let resetsAt: String?
        let scope: LimitScope?
        let isActive: Bool?

        enum CodingKeys: String, CodingKey {
            case kind, group, percent, scope
            case resetsAt = "resets_at"
            case isActive = "is_active"
        }
    }

    struct LimitScope: Decodable {
        let model: LimitScopeModel?
    }

    struct LimitScopeModel: Decodable {
        let id: String?
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    private struct LossyLimitEntry: Decodable {
        let value: LimitEntry?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.value = try? container.decode(LimitEntry.self)
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

    func fetchUsage(accessToken: String) async throws -> UsageResponse {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage"),
              url.host == "api.anthropic.com" else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The endpoint expects a Claude Code client UA.
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")

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
}
