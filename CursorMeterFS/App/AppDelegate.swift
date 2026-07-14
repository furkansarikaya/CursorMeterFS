import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Exposed to CursorMeterFSApp via @NSApplicationDelegateAdaptor
    let store = UsageStore()
    private var settingsWindow: NSWindow?
    private var powerObserverTokens: [NSObjectProtocol] = []

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
        setupPowerObservers()
        Task { await NotificationService.shared.requestAuthorization() }
        store.start()
        SelfSigningService.checkAndOfferFix()
    }

    deinit {
        for token in powerObserverTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
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

    // MARK: - Power / sleep observers
    //
    // Suspends the refresh loop entirely while the system is asleep, the screen is
    // locked, or the session is inactive (fast user switching) — no network work
    // happens in these states regardless of the configured refresh frequency. On
    // wake/unlock the loop resumes and does one immediate refresh.

    private func setupPowerObservers() {
        let center = NSWorkspace.shared.notificationCenter

        let suspendNames: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ]
        let resumeNames: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ]

        for name in suspendNames {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.store.suspend() }
            }
            powerObserverTokens.append(token)
        }
        for name in resumeNames {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.store.resume() }
            }
            powerObserverTokens.append(token)
        }
    }
}
