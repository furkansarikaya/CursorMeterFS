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

    func notifyIfNeeded(
        usage: UsageData,
        warningThreshold: Double,
        criticalThreshold: Double,
        notifyOnReset: Bool,
        enabled: Bool
    ) {
        guard enabled else { return }

        let fraction = usage.fraction
        let status = usage.status(
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold
        )

        let cycleKey = billingCycleKey(from: usage.billingCycleStart)

        // Critical threshold
        let criticalKey = "critical-\(cycleKey)"
        if status == .critical && !firedThresholds.contains(criticalKey) {
            firedThresholds.insert(criticalKey)
            send(
                identifier: criticalKey,
                title: "Critical Usage",
                body: "Critical: \(usage.percentageInt)% of monthly quota used. Resets \(usage.resetDateDescription).",
                categoryIdentifier: "CRITICAL"
            )
        }

        // Warning threshold
        let warningKey = "warning-\(cycleKey)"
        if fraction >= warningThreshold && status != .critical && !firedThresholds.contains(warningKey) {
            firedThresholds.insert(warningKey)
            send(
                identifier: warningKey,
                title: "Usage Warning",
                body: "You've used \(usage.percentageInt)% of your monthly quota. Resets \(usage.resetDateDescription).",
                categoryIdentifier: "WARNING"
            )
        }
    }

    func sendTestNotification() {
        send(
            identifier: "test-\(Date().timeIntervalSince1970)",
            title: "CursorMeter",
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

    private func billingCycleKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
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
