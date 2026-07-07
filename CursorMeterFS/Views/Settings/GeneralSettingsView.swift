import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        Form {
            // ── Providers ───────────────────────────────────────────
            Section("Providers") {
                ForEach(Provider.allCases) { provider in
                    providerRow(provider)
                }
                Text("Credentials are read from each tool's local sign-in — nothing to configure, no admin rights needed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // ── Refresh interval ─────────────────────────────────────
            Section {
                Picker("Refresh Interval", selection: $store.refreshFrequency) {
                    ForEach(RefreshFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .help("Adaptive automatically backs off when idle, on Low Power Mode, or under thermal pressure — best for battery life. Fixed intervals poll at a constant rate regardless of activity.")
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

                // Style grid — previews use the selected provider's live numbers.
                let primary = store.selectedState.snapshot?.primary
                let details = store.selectedState.snapshot?.cursorDetails
                let fraction = primary?.fraction ?? 0.42
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        IconStyleCell(
                            style: style,
                            selected: store.iconStyle == style,
                            fraction: fraction,
                            used: details?.used ?? (primary?.percentInt ?? 42),
                            total: details?.total ?? 100,
                            status: UsageStatus.from(
                                fraction: fraction,
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
                Toggle("Export usage to ~/.cursormeterfs/usage.json", isOn: $store.exportEnabled)
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

    // MARK: - Provider row

    @ViewBuilder
    private func providerRow(_ provider: Provider) -> some View {
        HStack(spacing: 8) {
            if let image = ProviderBrandIcon.image(for: provider) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .foregroundColor(.primary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(.subheadline.weight(.medium))
                if let account = store.state(for: provider).snapshot?.accountLabel,
                   !account.isEmpty {
                    Text(account)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            statusBadge(for: provider)

            Toggle("", isOn: Binding(
                get: { store.providerEnabled[provider] ?? true },
                set: { store.setProviderEnabled(provider, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private func statusBadge(for provider: Provider) -> some View {
        if store.providerEnabled[provider] ?? true {
            switch store.state(for: provider).phase {
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
}

#if DEBUG
#Preview("General Settings") {
    GeneralSettingsView()
        .environmentObject(UsageStore.preview)
        .frame(width: 480, height: 520)
}
#endif

// MARK: - Icon Style Preview Cell
private struct IconStyleCell: View {
    let style: MenuBarIconStyle
    let selected: Bool
    let fraction: Double
    var used: Int = 0
    var total: Int = 0
    let status: UsageStatus
    let colorMode: IconColorMode

    private var previewImage: NSImage {
        MenuBarIconRenderer.image(
            fraction: fraction,
            used: used,
            total: total,
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
