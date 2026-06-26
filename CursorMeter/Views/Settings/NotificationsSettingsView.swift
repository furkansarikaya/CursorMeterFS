import SwiftUI

struct NotificationsSettingsView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        Form {
            Section {
                Toggle("Enable Notifications", isOn: $store.notificationsEnabled)
                    .help("Get notified when usage thresholds are reached")
                    .onChange(of: store.notificationsEnabled) { enabled in
                        if enabled {
                            Task { await NotificationService.shared.requestAuthorization() }
                        }
                    }
            }

            if store.notificationsEnabled {
                Section("Thresholds") {
                    VStack(alignment: .leading, spacing: 16) {
                        ThresholdSlider(
                            label: "Warning Threshold",
                            value: $store.warningThreshold,
                            color: .usageWarning
                        )

                        ThresholdSlider(
                            label: "Critical Threshold",
                            value: $store.criticalThreshold,
                            color: .usageCritical
                        )
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Notify on Billing Cycle Reset", isOn: $store.notifyOnReset)
                        .help("Get notified when your monthly quota resets at the start of a new billing cycle")
                }

                Section {
                    Button("Send Test Notification") {
                        Task {
                            let granted = await NotificationService.shared.requestAuthorization()
                            if granted {
                                NotificationService.shared.sendTestNotification()
                            } else {
                                // Open System Settings so the user can grant permission
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview("Notifications Settings") {
    NotificationsSettingsView()
        .environmentObject(UsageStore.preview)
        .frame(width: 480, height: 400)
}

// MARK: - Threshold slider
private struct ThresholdSlider: View {
    let label: String
    @Binding var value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundColor(color)
            }

            Slider(value: $value, in: 0.1...0.99, step: 0.05)
                .tint(color)

            Text("Get notified when monthly quota reaches this percentage")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
