import SwiftUI

/// Shown when no Cursor session is found on the local machine.
struct OnboardingView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 60, height: 60)
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.accentColor)
            }

            // Title
            VStack(spacing: 4) {
                Text("Welcome to CursorMeterFS")
                    .font(.headline)
                Text("Monitor your Cursor plan usage in real-time")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            // Instructions
            VStack(alignment: .leading, spacing: 10) {
                instructionRow(
                    step: "1",
                    text: "Open Cursor and sign in to your account",
                    icon: "person.circle"
                )
                instructionRow(
                    step: "2",
                    text: "Click Retry below — CursorMeterFS will detect your login automatically",
                    icon: "arrow.clockwise.circle"
                )
                instructionRow(
                    step: "3",
                    text: "Your monthly quota will appear in the menu bar",
                    icon: "chart.bar.fill"
                )
            }
            .padding(.horizontal, 4)

            // Retry button
            Button {
                Task { await store.refresh() }
            } label: {
                HStack {
                    if store.isRefreshing {
                        ProgressView().scaleEffect(0.7)
                    }
                    Text(store.isRefreshing ? "Detecting…" : "Retry Detection")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.isRefreshing)

            // Manual fallback note
            VStack(spacing: 4) {
                Text("Need manual setup?")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("View instructions in README") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/furkansarikaya/CursorMeterFS#manual-session")!)
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func instructionRow(step: String, text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 22, height: 22)
                Text(step)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.accentColor)
            }

            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                Text(text)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("Onboarding") {
    OnboardingView()
        .environmentObject(UsageStore.previewLoggedOut)
        .frame(width: 300)
}
