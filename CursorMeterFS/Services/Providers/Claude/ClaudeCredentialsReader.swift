import Foundation
import Security

/// Reads Claude Code OAuth credentials — file first (`~/.claude/.credentials.json`),
/// then the user's LOGIN Keychain (service "Claude Code-credentials") as fallback.
/// Both are user-scoped: no admin, no sudo. The Keychain read may show a one-time
/// permission prompt; tokens are NEVER logged or persisted elsewhere.
enum ClaudeCredentialsReader {

    struct ClaudeCredentials {
        let accessToken: String     // DO NOT LOG
        let refreshToken: String?   // DO NOT LOG
        let expiresAt: Date?
        let subscriptionType: String?  // "max", "pro", "team"…
        let rateLimitTier: String?
    }

    static var credentialsFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }

    private static let keychainService = "Claude Code-credentials"

    static func read() throws -> ClaudeCredentials {
        if let data = try? Data(contentsOf: credentialsFileURL),
           let credentials = parse(data) {
            return credentials
        }
        if let data = readFromKeychain(),
           let credentials = parse(data) {
            return credentials
        }
        throw ProviderError.notLoggedIn
    }

    // MARK: - Parsing

    /// Shape: `{"claudeAiOauth": {"accessToken","refreshToken","expiresAt"(ms),
    ///           "scopes",["subscriptionType"],["rateLimitTier"]}}`
    static func parse(_ data: Data) -> ClaudeCredentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              !accessToken.isEmpty else {
            return nil
        }

        var expiresAt: Date?
        if let ms = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: ms / 1_000)
        } else if let ms = oauth["expiresAt"] as? Int {
            expiresAt = Date(timeIntervalSince1970: Double(ms) / 1_000)
        }

        return ClaudeCredentials(
            accessToken: accessToken,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String
        )
    }

    // MARK: - Account info (~/.claude.json)

    /// Reads the signed-in account e-mail from `~/.claude.json` (`oauthAccount.emailAddress`).
    /// Local file only, no network; returns nil when unavailable.
    /// The value is shown in the UI — never logged or exported.
    static func accountEmail() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any],
              let email = account["emailAddress"] as? String,
              !email.isEmpty else {
            return nil
        }
        return email
    }

    // MARK: - Keychain fallback (login keychain, generic password)

    private static func readFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}
