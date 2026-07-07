import Foundation
import UserNotifications

/// Sends macOS user notifications when usage thresholds are crossed.
/// Each threshold fires at most once per billing cycle to avoid spam.
final class NotificationService: NSObject {

    static let shared = NotificationService()

    private override init() {
        super.init()
        // Delegate assignment deferred to requestAuthorization() —
        // UNUserNotificationCenter.current() can throw an ObjC exception during
        // cold init on macOS 26 when it tries to deserialize legacy NSCalendarDate state.
    }

    // MARK: - Permission
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self   // safe here: called after app is fully launched
        let current = await center.notificationSettings()
        if current.authorizationStatus == .authorized { return true }

        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Threshold tracking
    private var firedThresholds: Set<String> = []

    func resetFiredThresholds() {
        firedThresholds.removeAll()
    }

    // MARK: - Send notifications

    /// Provider-agnostic threshold notification. `cycleKey` identifies the quota window
    /// instance (provider + reset timestamp) so each threshold fires at most once per window.
    func notifyIfNeeded(
        providerName: String,
        fraction: Double,
        percentInt: Int,
        resetDescription: String?,
        cycleKey: String,
        warningThreshold: Double,
        criticalThreshold: Double,
        enabled: Bool
    ) {
        guard enabled else { return }

        let resetSuffix = resetDescription.map { " Resets in \($0)." } ?? ""

        // Critical threshold
        let criticalKey = "critical-\(cycleKey)"
        if fraction >= criticalThreshold && !firedThresholds.contains(criticalKey) {
            firedThresholds.insert(criticalKey)
            send(
                identifier: criticalKey,
                title: "\(providerName): Critical Usage",
                body: "Critical: \(percentInt)% of your \(providerName) quota used.\(resetSuffix)",
                categoryIdentifier: "CRITICAL"
            )
        }

        // Warning threshold
        let warningKey = "warning-\(cycleKey)"
        if fraction >= warningThreshold && fraction < criticalThreshold && !firedThresholds.contains(warningKey) {
            firedThresholds.insert(warningKey)
            send(
                identifier: warningKey,
                title: "\(providerName): Usage Warning",
                body: "You've used \(percentInt)% of your \(providerName) quota.\(resetSuffix)",
                categoryIdentifier: "WARNING"
            )
        }
    }

    func sendTestNotification() {
        send(
            identifier: "test-\(Date().timeIntervalSince1970)",
            title: "CursorMeterFS",
            body: "Notifications are working correctly!",
            categoryIdentifier: "TEST"
        )
    }

    func notifyReset(plan: Plan) {
        send(
            identifier: "reset-\(Date().timeIntervalSince1970)",
            title: "Usage Reset",
            body: "Your Cursor \(plan.displayName) monthly quota has reset. Fresh start!",
            categoryIdentifier: "RESET"
        )
    }

    // MARK: - Private
    private func send(identifier: String, title: String, body: String, categoryIdentifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show even when app is in foreground
        completionHandler([.banner, .sound])
    }
}
