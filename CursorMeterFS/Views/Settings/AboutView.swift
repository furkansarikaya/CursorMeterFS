import SwiftUI

struct AboutView: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
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

            Text("Monitor your Cursor AI subscription usage\ndirectly from the macOS menu bar.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            // Links
            VStack(spacing: 8) {
                linkButton("GitHub Repository", url: "https://github.com/furkansarikaya/CursorMeterFS", icon: "arrow.up.right.square")
                linkButton("Report an Issue", url: "https://github.com/furkansarikaya/CursorMeterFS/issues", icon: "exclamationmark.bubble")
                linkButton("cursor.com Dashboard", url: "https://cursor.com/dashboard", icon: "chart.bar.xaxis")
            }

            Divider()

            // Security note
            VStack(spacing: 4) {
                Label("Privacy & Security", systemImage: "lock.shield")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Text("Your session token is stored exclusively in macOS Keychain (encrypted, device-local only). No credentials are ever written to disk or transmitted outside cursor.com.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Text("MIT License · © 2026 Furkan Sarıkaya")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

#Preview("About") {
    AboutView()
        .frame(width: 480, height: 420)
}
