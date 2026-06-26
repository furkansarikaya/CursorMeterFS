import SwiftUI

struct RecentRequestsView: View {
    let events: [UsageEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Recent Requests", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(events.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            if events.isEmpty {
                Text("No recent requests")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(events) { event in
                        RequestRowView(event: event)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Single request row
private struct RequestRowView: View {
    let event: UsageEvent

    var body: some View {
        HStack(spacing: 8) {
            // Model name
            Text(event.displayModelName)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .leading)

            Spacer()

            // Tokens
            HStack(spacing: 2) {
                Image(systemName: "text.word.spacing")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(tokenString(event.totalTokens))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            // Cost
            if event.costUSD > 0 {
                Text("$\(event.costUSD, specifier: "%.4f")")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }

            // Relative time
            Text(event.timestamp, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(Color(NSColor.quaternaryLabelColor).opacity(0.1))
        .cornerRadius(6)
    }

    private func tokenString(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

#Preview {
    RecentRequestsView(events: [
        UsageEvent(
            id: "1", model: "claude-sonnet-4-6",
            inputTokens: 1200, outputTokens: 450, costUSD: 0.0045,
            timestamp: Date().addingTimeInterval(-120), kind: .agent
        ),
        UsageEvent(
            id: "2", model: "gpt-4o",
            inputTokens: 800, outputTokens: 200, costUSD: 0.002,
            timestamp: Date().addingTimeInterval(-600), kind: .chat
        ),
    ])
    .frame(width: 280)
    .padding()
}
