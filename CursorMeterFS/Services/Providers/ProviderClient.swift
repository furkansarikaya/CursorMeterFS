import Foundation

/// One data source per provider. Clients return data (`ProviderSnapshot`); the app owns UI.
/// All credential reads are user-scoped (home-directory files or the login Keychain) —
/// never system locations, never sudo.
protocol ProviderClient: Sendable {
    var id: Provider { get }

    /// Fetches a fresh snapshot. Throws `ProviderError.notLoggedIn` when no local
    /// credentials exist; any other error is shown as a per-provider error badge
    /// while the last known snapshot stays visible.
    func fetch() async throws -> ProviderSnapshot
}

enum ProviderError: LocalizedError {
    case notLoggedIn
    case api(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:      return "Not signed in"
        case .api(let message): return message
        }
    }
}
