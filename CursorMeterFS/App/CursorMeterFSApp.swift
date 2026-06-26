import SwiftUI

@main
struct CursorMeterFSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // No main window — we're a menu bar only app (LSUIElement=YES in Info.plist).
        // Settings is opened programmatically by AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
