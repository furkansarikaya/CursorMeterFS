import SwiftUI

struct AboutView: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App icon — NSWorkspace reliably returns the bundle icon for LSUIElement apps
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .cornerRadius(14)

                VStack(spacing: 4) {
                    Text("CursorMeterFS")
                        .font(.title2.weight(.bold))
                    Text("Version \(version) (\(build))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Started as a Cursor-only usage tracker — that's where the name comes from. It has since grown into a multi-provider menu bar monitor for Cursor, Codex, and Claude Code, showing live quotas, reset timers, and cost estimates side by side.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                // Links
                VStack(spacing: 8) {
                    linkButton("GitHub Repository", url: "https://github.com/furkansarikaya/CursorMeterFS", icon: "arrow.up.right.square")
                    linkButton("Report an Issue", url: "https://github.com/furkansarikaya/CursorMeterFS/issues", icon: "exclamationmark.bubble")
                }

                Divider()

                VStack(spacing: 8) {
                    linkButton("Codex Dashboard", url: "https://chatgpt.com", icon: "chart.bar.xaxis")
                    linkButton("Claude Dashboard", url: "https://claude.ai", icon: "chart.bar.xaxis")
                    linkButton("Cursor Dashboard", url: "https://cursor.com/dashboard", icon: "chart.bar.xaxis")
                }

                Divider()

                // Security note
                VStack(spacing: 4) {
                    Label("Privacy & Security", systemImage: "lock.shield")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text("No admin access required. Each provider's credentials are read locally and never leave your Mac: Cursor's session token lives in the macOS Keychain, while Codex and Claude Code are read from their own existing local auth files. Refreshed tokens are kept in memory only — nothing is ever written back to disk or sent anywhere beyond each provider's own API.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("MIT License · © 2026 Furkan Sarıkaya")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func linkButton(_ title: String, url: String, icon: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.callout)
            }
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("About") {
    AboutView()
        .frame(width: 480, height: 420)
}
#endif
