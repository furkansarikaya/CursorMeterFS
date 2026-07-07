import SwiftUI

@main
struct CursorMeterFSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // MenuBarExtra is the macOS 13+ native API for menu bar apps.
        // It is more reliable than NSStatusItem + NSPopover on modern macOS.
        MenuBarExtra {
            PopoverRootView()
                .environmentObject(appDelegate.store)
                .frame(width: 300, height: 480)
        } label: {
            MenuBarIconLabel()
                .environmentObject(appDelegate.store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.store)
        }
    }
}

// MARK: - Menu bar icon label (re-renders on every store update)
// Follows the SELECTED provider tab: switching tabs switches what the icon shows.

private struct MenuBarIconLabel: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        let provider = store.selectedProvider
        let primary = store.state(for: provider).snapshot?.primary
        let fraction = primary?.fraction ?? 0
        let status = UsageStatus.from(
            fraction: fraction,
            warningThreshold: store.warningThreshold,
            criticalThreshold: store.criticalThreshold
        )
        // Count-based icon styles need used/total; Cursor has real request counts,
        // other providers show percent-of-100.
        let details = store.state(for: provider).snapshot?.cursorDetails
        Image(nsImage: MenuBarIconRenderer.image(
            fraction: fraction,
            used: details?.used ?? (primary?.percentInt ?? 0),
            total: details?.total ?? 100,
            status: status,
            style: store.iconStyle,
            colorMode: store.iconColorMode
        ))
        .help("\(provider.displayName) usage: \(primary?.percentInt ?? 0)% — click to open")
    }
}
