import SwiftUI

/// The AI tools this app can monitor. `allCases` order defines the tab order.
enum Provider: String, CaseIterable, Identifiable, Codable {
    case codex
    case claude
    case cursor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:  return "Codex"
        case .claude: return "Claude"
        case .cursor: return "Cursor"
        }
    }

    /// Bundled template-SVG resource (see Resources/ProviderIcons/).
    var iconResourceName: String { "ProviderIcon-\(rawValue)" }

    /// Brand color used for the tab underline.
    var brandColor: Color {
        switch self {
        case .codex:  return Color(red: 73 / 255, green: 163 / 255, blue: 176 / 255)
        case .claude: return Color(red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        case .cursor: return Color(red: 0 / 255, green: 191 / 255, blue: 165 / 255)
        }
    }

    /// Short hint shown when no credentials are found for this provider.
    var loginHint: String {
        switch self {
        case .codex:  return "Sign in with the Codex CLI (`codex`) — usage is read from ~/.codex."
        case .claude: return "Sign in with Claude Code (`claude`) — usage is read from your local login."
        case .cursor: return "Open Cursor and sign in — usage is read from the local Cursor installation."
        }
    }
}
