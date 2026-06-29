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

private struct MenuBarIconLabel: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        let fraction = store.appState == .loading ? 0.0 : store.usage.fraction
        let status = store.usage.status(
            warningThreshold: store.warningThreshold,
            criticalThreshold: store.criticalThreshold
        )
        Image(nsImage: MenuBarIconRenderer.image(
            fraction: fraction,
            used: store.usage.used,
            total: store.usage.total,
            status: status,
            style: store.iconStyle,
            colorMode: store.iconColorMode
        ))
        .help("Cursor Usage: \(store.usage.percentageInt)% — click to open")
    }
}
