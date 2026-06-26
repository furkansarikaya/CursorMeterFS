import SwiftUI

struct PopoverRootView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────
            header

            Divider()

            // ── Content ─────────────────────────────────────────────
            ScrollView {
                VStack(spacing: 12) {
                    contentArea
                }
                .padding(14)
            }

            Divider()

            // ── Footer ──────────────────────────────────────────────
            footer
        }
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Text("Cursor Usage")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            // Last refreshed indicator
            if let refreshed = store.lastRefreshed {
                Text(refreshed, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Refresh button
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: store.isRefreshing ? "arrow.clockwise.circle" : "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .rotationEffect(store.isRefreshing ? .degrees(360) : .zero)
                    .animation(store.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: store.isRefreshing)
            }
            .buttonStyle(.plain)
            .help("Refresh usage data")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Content
    @ViewBuilder
    private var contentArea: some View {
        switch store.appState {
        case .loading:
            loadingView

        case .loggedOut:
            OnboardingView()

        case .ready, .error:
            // Always show last known data; show error badge if state == .error
            usageCards

        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading usage data…")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    @ViewBuilder
    private var usageCards: some View {
        // Error banner (shows on top of stale data)
        if case .error(let msg) = store.appState {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.usageWarning)
                    .font(.caption)
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(8)
            .background(Color.usageWarning.opacity(0.12))
            .cornerRadius(8)
        }

        // Main quota card
        UsageCardView(
            title: "Monthly Quota",
            subtitle: "\(store.usage.plan.displayName) Plan",
            systemImage: "calendar",
            usage: store.usage,
            warningThreshold: store.warningThreshold,
            criticalThreshold: store.criticalThreshold
        )

        // On-demand spend card (show if non-zero or if enabled)
        if store.usage.usageBasedEnabled || store.usage.onDemandSpendUSD > 0 {
            OnDemandCardView(usage: store.usage)
        }

        // Recent requests
        if store.showRecentRequests && !store.recentEvents.isEmpty {
            RecentRequestsView(events: Array(store.recentEvents.prefix(store.recentRequestCount)))
        }
    }

    // MARK: - Footer
    private var footer: some View {
        HStack {
            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                // Fallback for older macOS:
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

// MARK: - On-demand spend card
private struct OnDemandCardView: View {
    let usage: UsageData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("On-Demand", systemImage: "creditcard")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let limit = usage.hardLimitUSD {
                    Text("Limit: $\(limit, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("$\(usage.onDemandSpendUSD, specifier: "%.2f")")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(usage.onDemandSpendUSD > 0 ? .usageWarning : .primary)
                Text("this month")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

#Preview("Popover — Ready") {
    PopoverRootView()
        .environmentObject(UsageStore.preview)
}

#Preview("Popover — Onboarding") {
    PopoverRootView()
        .environmentObject(UsageStore.previewLoggedOut)
}

// MARK: - Notification name
extension Notification.Name {
    static let openSettings = Notification.Name("CursorMeterFSOpenSettings")
}
