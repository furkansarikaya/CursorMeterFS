import Foundation

/// Reads Codex CLI credentials from `$CODEX_HOME/auth.json` (default `~/.codex/auth.json`).
/// User-home only — no admin, no Keychain, read-only. Tokens are NEVER logged.
enum CodexAuthReader {

    struct CodexCredentials {
        let accessToken: String?   // ChatGPT OAuth access token — DO NOT LOG
        let refreshToken: String?  // DO NOT LOG
        let accountId: String?
        let apiKey: String?        // plain OPENAI_API_KEY installs — DO NOT LOG
        let lastRefresh: Date?
    }

    static var codexHome: URL {
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    static var authFileURL: URL { codexHome.appendingPathComponent("auth.json") }
    static var sessionsDirURL: URL { codexHome.appendingPathComponent("sessions") }

    /// Shape: `{"auth_mode": "chatgpt", "OPENAI_API_KEY": null,
    ///          "tokens": {"access_token","refresh_token","id_token","account_id"},
    ///          "last_refresh": ISO8601}`
    static func read() throws -> CodexCredentials {
        guard let data = try? Data(contentsOf: authFileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.notLoggedIn
        }

        let tokens = json["tokens"] as? [String: Any]
        let apiKey = json["OPENAI_API_KEY"] as? String

        var lastRefresh: Date?
        if let refreshStr = json["last_refresh"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            lastRefresh = formatter.date(from: refreshStr)
                ?? ISO8601DateFormatter().date(from: refreshStr)
        }

        let credentials = CodexCredentials(
            accessToken: tokens?["access_token"] as? String,
            refreshToken: tokens?["refresh_token"] as? String,
            accountId: tokens?["account_id"] as? String,
            apiKey: apiKey,
            lastRefresh: lastRefresh
        )

        guard credentials.accessToken != nil || credentials.apiKey != nil else {
            throw ProviderError.notLoggedIn
        }
        return credentials
    }
}
