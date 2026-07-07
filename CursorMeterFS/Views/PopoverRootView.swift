import SwiftUI

struct PopoverRootView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            // ── Header + provider tabs ───────────────────────────────
            header
            ProviderTabStrip()

            Divider()

            // ── Selected provider detail ─────────────────────────────
            ScrollView {
                ProviderDetailView(provider: store.selectedProvider)
                    .padding(14)
            }

            Divider()

            // ── Footer ──────────────────────────────────────────────
            footer
        }
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { store.notePopoverOpened() }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Text("AI Usage")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            // ProgressView replaces the old .repeatForever rotation animation.
            // .repeatForever kept the compositor spinning ~60fps even when the
            // popover was hidden (.window style keeps the content tree alive).
            // ProgressView stops driving frames the moment it leaves the tree.
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .help("Refreshing…")
            } else {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh usage data")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    // MARK: - Footer
    private var footer: some View {
        HStack {
            Button("Settings") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            .font(.callout)
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.callout)
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Notification name
extension Notification.Name {
    static let openSettings = Notification.Name("CursorMeterFSOpenSettings")
}

#if DEBUG
#Preview("Popover — Ready") {
    PopoverRootView()
        .environmentObject(UsageStore.preview)
        .frame(height: 480)
}

#Preview("Popover — Onboarding") {
    PopoverRootView()
        .environmentObject(UsageStore.previewLoggedOut)
        .frame(height: 480)
}
#endif
