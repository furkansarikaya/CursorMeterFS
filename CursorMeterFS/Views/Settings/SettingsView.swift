import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            NotificationsSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 480)
    }
}

#Preview("Settings") {
    SettingsView()
        .environmentObject(UsageStore.preview)
}
