import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        Form {
            // ── Account ─────────────────────────────────────────────
            Section {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !store.accountEmail.isEmpty {
                            Text(store.accountEmail)
                                .font(.subheadline.weight(.medium))
                        }
                        HStack(spacing: 6) {
                            Text("Automatically read from local Cursor installation")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        authBadge
                        planBadge
                    }
                }

                if store.appState == .loggedOut {
                    Button("Retry Detection") {
                        Task { await store.refresh() }
                    }
                } else {
                    Button("Sign Out", role: .destructive) {
                        store.signOut()
                    }
                }
            }

            // ── Refresh interval ─────────────────────────────────────
            Section {
                Picker("Refresh Interval", selection: $store.refreshIntervalMinutes) {
                    Text("1 minute").tag(1)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                }
                .help("How often to fetch usage data from cursor.com")
            }

            // ── Recent requests ──────────────────────────────────────
            Section {
                Toggle("Show Recent Requests", isOn: $store.showRecentRequests)
                    .help("Display the last N requests with model name and token count in the popover")

                if store.showRecentRequests {
                    Picker("Show last", selection: $store.recentRequestCount) {
                        Text("5 requests").tag(5)
                        Text("10 requests").tag(10)
                        Text("20 requests").tag(20)
                    }
                }
            }

            // ── Icon style ───────────────────────────────────────────
            Section("Menu Bar Icon") {
                // Color mode toggle
                Picker("Color Mode", selection: $store.iconColorMode) {
                    ForEach(IconColorMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                // Style grid
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        IconStyleCell(
                            style: style,
                            selected: store.iconStyle == style,
                            fraction: store.usage.fraction,
                            status: store.usage.status(
                                warningThreshold: store.warningThreshold,
                                criticalThreshold: store.criticalThreshold
                            ),
                            colorMode: store.iconColorMode
                        )
                        .onTapGesture { store.iconStyle = style }
                    }
                }
                .padding(.top, 4)
            }

            // ── Export ───────────────────────────────────────────────
            Section {
                Toggle("Export usage to ~/.cursormeter/usage.json", isOn: $store.exportEnabled)
                    .help("Exports only aggregate percentages and counts — no credentials are written.")
            }

            // ── Start at login ───────────────────────────────────────
            Section {
                Toggle("Start at Login", isOn: Binding(
                    get: { LoginItemService.shared.isEnabled },
                    set: { LoginItemService.shared.setEnabled($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var planBadge: some View {
        switch store.appState {
        case .ready, .error:
            Text(store.usage.plan.displayName)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15))
                .foregroundColor(.accentColor)
                .cornerRadius(4)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var authBadge: some View {
        switch store.appState {
        case .ready:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundColor(.usageSafe)
                .font(.caption.weight(.semibold))
        case .loading:
            Label("Connecting…", systemImage: "circle.dotted")
                .foregroundColor(.secondary)
                .font(.caption)
        case .loggedOut:
            Label("Not signed in", systemImage: "xmark.circle.fill")
                .foregroundColor(.usageCritical)
                .font(.caption.weight(.semibold))
        case .error:
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.usageWarning)
                .font(.caption.weight(.semibold))
        }
    }
}

#Preview("General Settings") {
    GeneralSettingsView()
        .environmentObject(UsageStore.preview)
        .frame(width: 480, height: 520)
}

// MARK: - Icon Style Preview Cell
private struct IconStyleCell: View {
    let style: MenuBarIconStyle
    let selected: Bool
    let fraction: Double
    let status: UsageStatus
    let colorMode: IconColorMode

    private var previewImage: NSImage {
        MenuBarIconRenderer.image(
            fraction: fraction,
            status: status,
            style: style,
            colorMode: colorMode
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: previewImage)
                .interpolation(.high)
                .frame(height: 20)

            Text(style.displayName)
                .font(.caption2)
                .foregroundColor(selected ? .accentColor : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(selected ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}
