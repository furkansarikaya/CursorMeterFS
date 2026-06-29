import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Exposed to CursorMeterFSApp via @NSApplicationDelegateAdaptor
    let store = UsageStore()
    private var settingsWindow: NSWindow?

    // MARK: - App lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        // New-instance wins: terminate older copies so updates take effect immediately.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.furkansarikaya.CursorMeterFS"
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
            .forEach { $0.terminate() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = ProcessInfo.processInfo.environment
        guard env["XCTestConfigurationFilePath"] == nil,
              env["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

        setupNotifications()
        Task { await NotificationService.shared.requestAuthorization() }
        store.start()
    }

    // MARK: - Settings window

    @objc func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host   = NSHostingController(rootView: SettingsView().environmentObject(store))
        let window = NSWindow(contentViewController: host)
        window.title = "CursorMeterFS Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc func refreshNow() {
        Task { await store.refresh() }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .openSettings,
            object: nil
        )
    }
}
