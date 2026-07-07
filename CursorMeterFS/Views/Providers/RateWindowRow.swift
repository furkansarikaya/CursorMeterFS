import SwiftUI

/// One quota lane: title, progress bar, "% used" + "Resets in …", optional pace line.
/// Everything is plain and readable — values come straight from the provider's API.
struct RateWindowRow: View {
    let title: String
    let window: RateWindow
    var pace: UsagePace?
    let warningThreshold: Double
    let criticalThreshold: Double

    private var status: UsageStatus {
        window.status(warningThreshold: warningThreshold, criticalThreshold: criticalThreshold)
    }
    private var statusColor: Color { .usage(for: status) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if status != .safe {
                    StatusBadge(status: status)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(NSColor.separatorColor).opacity(0.3))
                        .frame(height: 8)
                    Capsule()
                        .fill(statusColor)
                        // Minimum visible sliver so "1% used" doesn't look like zero.
                        .frame(width: max(geo.size.width * CGFloat(window.fraction), window.usedPercent > 0 ? 8 : 0),
                               height: 8)
                        .animation(.spring(duration: 0.5), value: window.fraction)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(window.percentInt)% used")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.primary)
                Spacer()
                if let reset = window.resetDescription() {
                    Text(reset == "now" ? "Resets now" : "Resets in \(reset)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let pace {
                Text(pace.displayText)
                    .font(.caption)
                    .foregroundColor(paceColor(pace))
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func paceColor(_ pace: UsagePace) -> Color {
        switch pace.stage {
        case .behind:  return .secondary            // consuming slower than the window — fine
        case .onTrack: return .secondary
        case .ahead:   return pace.willLastToReset ? .secondary : .usageWarning
        }
    }
}

#if DEBUG
#Preview("Rate Window Rows") {
    VStack(spacing: 10) {
        RateWindowRow(
            title: "Session",
            window: RateWindow(usedPercent: 2, windowMinutes: 300,
                               resetsAt: Date().addingTimeInterval(3.9 * 3_600)),
            warningThreshold: 0.7, criticalThreshold: 0.9
        )
        RateWindowRow(
            title: "Weekly",
            window: RateWindow(usedPercent: 76, windowMinutes: 10_080,
                               resetsAt: Date().addingTimeInterval(3.8 * 86_400)),
            pace: UsagePace(stage: .ahead, deltaPercent: 31, willLastToReset: false),
            warningThreshold: 0.7, criticalThreshold: 0.9
        )
    }
    .padding()
    .frame(width: 300)
}
#endif
