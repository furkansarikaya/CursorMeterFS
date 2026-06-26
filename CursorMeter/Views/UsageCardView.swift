import SwiftUI

struct UsageCardView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let usage: UsageData
    let warningThreshold: Double
    let criticalThreshold: Double

    private var status: UsageStatus {
        usage.status(warningThreshold: warningThreshold, criticalThreshold: criticalThreshold)
    }
    private var statusColor: Color { .usage(for: status) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: title + badge
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                StatusBadge(status: status)
            }

            // Row 2: big percentage
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(usage.percentageInt)%")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(statusColor)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.4), value: usage.percentageInt)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(usage.used) / \(usage.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    Text("requests")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Row 3: progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(NSColor.separatorColor).opacity(0.3))
                        .frame(height: 8)

                    Capsule()
                        .fill(statusColor)
                        .frame(width: geo.size.width * CGFloat(usage.fraction), height: 8)
                        .animation(.spring(duration: 0.5), value: usage.fraction)
                }
            }
            .frame(height: 8)

            // Row 4: reset info + flame icon
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Resets \(usage.resetDateDescription)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Flame = nearing limit
                if status != .safe {
                    Text("🔥")
                        .font(.caption)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let status: UsageStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImageName)
                .font(.caption2)
            Text(status.displayLabel)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.usage(for: status).opacity(0.15))
        .foregroundColor(Color.usage(for: status))
        .cornerRadius(20)
    }
}

#Preview {
    UsageCardView(
        title: "Monthly Quota",
        subtitle: "Pro Plan",
        systemImage: "calendar",
        usage: UsageData(
            used: 420,
            total: 1000,
            onDemandSpendUSD: 0,
            hardLimitUSD: nil,
            usageBasedEnabled: false,
            billingCycleStart: Date(),
            plan: .pro
        ),
        warningThreshold: 0.70,
        criticalThreshold: 0.90
    )
    .frame(width: 280)
    .padding()
}
