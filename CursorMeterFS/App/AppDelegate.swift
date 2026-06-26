import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private let store = UsageStore()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - App lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Single-instance enforcement: if another copy is already running, activate it and quit.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.furkansarikaya.CursorMeter"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty {
            others.first?.activate(options: .activateIgnoringOtherApps)
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Skip UI setup when running under XCTest to avoid NSStatusBar crash
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
        setupNotifications()

        Task { await NotificationService.shared.requestAuthorization() }

        store.start()

        // Re-draw menu bar icon whenever relevant state changes
        store.$usage.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        store.$appState.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        store.$iconStyle.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        store.$iconColorMode.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancellables.removeAll()
    }

    // MARK: - Status Item
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeft
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        let fraction = store.appState == .loading ? 0.0 : store.usage.fraction
        let status   = store.usage.status(
            warningThreshold: store.warningThreshold,
            criticalThreshold: store.criticalThreshold
        )

        button.image = MenuBarIconRenderer.image(
            fraction: fraction,
            status: status,
            style: store.iconStyle,
            colorMode: store.iconColorMode
        )
        button.toolTip = "Cursor Usage: \(store.usage.percentageInt)% — click to open"
    }

    // MARK: - Popover
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 480)
        popover.behavior = .transient
        popover.animates = false  // instant open — animation adds ~200 ms perceived lag

        let hostingVC = NSHostingController(
            rootView: PopoverRootView().environmentObject(store)
        )
        popover.contentViewController = hostingVC

        // Pre-warm: trigger SwiftUI view loading at startup so the first click is instant.
        _ = hostingVC.view
    }

    @objc private func togglePopover(_ sender: NSButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu(sender)
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Make popover window key for keyboard input — async to avoid racing
            // with the transient dismissal logic that NSApp.activate() can trigger.
            DispatchQueue.main.async {
                self.popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func showContextMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit CursorMeter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // must clear so left-click works next time
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
        window.title = "CursorMeter Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func refreshNow() {
        Task { await store.refresh() }
    }

    // MARK: - Internal notification observers
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .openSettings,
            object: nil
        )
    }
}
