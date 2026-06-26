import Foundation
import ServiceManagement

/// Manages the "Start at Login" behavior using the modern SMAppService API (macOS 13+).
final class LoginItemService {

    static let shared = LoginItemService()
    private init() {}

    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Not fatal — user can still manually add to Login Items
                print("[LoginItemService] \(enabled ? "Register" : "Unregister") failed: \(error.localizedDescription)")
            }
        }
    }
}
