import SwiftUI

/// Renders the selected provider's full detail: plan badge + updated time, quota lanes
/// (fully dynamic — whatever the provider's API returned), estimated cost, and Cursor's
/// on-demand / recent-request extras.
struct ProviderDetailView: View {
    @EnvironmentObject var store: UsageStore
    let provider: Provider

    private var state: ProviderUIState { store.state(for: provider) }

    var body: some View {
        VStack(spacing: 12) {
            providerHeader

            switch state.phase {
            case .loading where state.snapshot == nil:
                loadingView
            case .loggedOut:
                loggedOutView
            default:
                if case .error(let message) = state.phase {
                    errorBanner(message)
                }
                if let snapshot = state.snapshot {
                    snapshotContent(snapshot)
                }
            }
        }
    }

    // MARK: - Header (provider name · plan · updated)

    private var providerHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(provider.displayName)
                    .font(.title3.weight(.bold))
                Spacer()
                if let plan = state.snapshot?.planLabel {
                    Text(plan)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(provider.brandColor.opacity(0.15))
                        .foregroundColor(provider.brandColor)
                        .cornerRadius(6)
                }
            }
            if let updatedAt = state.snapshot?.updatedAt {
                Text("Updated \(updatedAt.shortRelativeDescription())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Content

    @ViewBuilder
    private func snapshotContent(_ snapshot: ProviderSnapshot) -> some View {
        // Quota lanes — dynamic: render exactly what the API returned.
        ForEach(snapshot.windows) { lane in
            RateWindowRow(
                title: lane.title,
                window: lane.window,
                pace: lane.pace,
                warningThreshold: store.warningThreshold,
                criticalThreshold: store.criticalThreshold
            )
        }

        // Cursor extras: on-demand spend card (kept from the single-provider app).
        if let details = snapshot.cursorDetails,
           details.usageBasedEnabled || details.onDemandSpendUSD > 0 {
            OnDemandCardView(usage: details)
        } else if let cost = snapshot.costUSD, cost > 0 {
            CostCardView(costUSD: cost, label: snapshot.costLabel)
        }

        // Recent requests (Cursor) or model breakdown fallback.
        if store.showRecentRequests {
            if !snapshot.recentEvents.isEmpty {
                RecentRequestsView(events: Array(snapshot.recentEvents.prefix(store.recentRequestCount)))
            } else if !snapshot.modelBreakdown.isEmpty,
                      let used = snapshot.cursorDetails?.used {
                ModelBreakdownView(breakdown: snapshot.modelBreakdown, total: used)
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading \(provider.displayName) usage…")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    @ViewBuilder
    private var loggedOutView: some View {
        if provider == .cursor {
            OnboardingView()
        } else {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(provider.brandColor.opacity(0.12))
                        .frame(width: 52, height: 52)
                    if let image = ProviderBrandIcon.image(for: provider) {
                        Image(nsImage: image)
                            .renderingMode(.template)
                            .foregroundColor(provider.brandColor)
                    }
                }
                Text("\(provider.displayName) not signed in")
                    .font(.headline)
                Text(provider.loginHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await store.refresh() }
                } label: {
                    Text(store.isRefreshing ? "Checking…" : "Retry Detection")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isRefreshing)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 4)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.usageWarning)
                .font(.caption)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.usageWarning.opacity(0.12))
        .cornerRadius(8)
    }
}

// MARK: - Estimated cost card (Codex / Claude — local token counts × price table)

struct CostCardView: View {
    let costUSD: Double
    let label: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Cost", systemImage: "dollarsign.circle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("estimate")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("$\(costUSD, specifier: "%.2f")")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                if let label {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - On-demand spend card (Cursor)

struct OnDemandCardView: View {
    let usage: UsageData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("On-Demand", systemImage: "creditcard")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let limit = usage.hardLimitUSD {
                    Text("Limit: $\(limit, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("$\(usage.onDemandSpendUSD, specifier: "%.2f")")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(usage.onDemandSpendUSD > 0 ? .usageWarning : .primary)
                Text("this month")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Model breakdown card (shown when invoice has no per-request events)

struct ModelBreakdownView: View {
    let breakdown: [String: Int]
    let total: Int

    private var sorted: [(model: String, count: Int)] {
        breakdown
            .map { (model: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Usage by Model", systemImage: "chart.bar.fill")
                .font(.subheadline.weight(.semibold))

            ForEach(sorted, id: \.model) { entry in
                HStack(spacing: 8) {
                    Text(displayName(entry.model))
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(entry.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    GeometryReader { geo in
                        let fraction = total > 0 ? Double(entry.count) / Double(total) : 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.25))
                            .frame(width: geo.size.width)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor)
                                    .frame(width: geo.size.width * fraction)
                            }
                    }
                    .frame(width: 60, height: 6)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func displayName(_ model: String) -> String {
        let known: [(prefix: String, name: String)] = [
            ("claude-opus-4",     "Claude Opus 4"),
            ("claude-sonnet-4",   "Claude Sonnet 4"),
            ("claude-haiku-4",    "Claude Haiku 4"),
            ("claude-3-5-sonnet", "Claude Sonnet 3.5"),
            ("gpt-4o-mini",       "GPT-4o mini"),
            ("gpt-4o",            "GPT-4o"),
            ("gpt-4",             "GPT-4"),
            ("gemini-2.5-pro",    "Gemini 2.5 Pro"),
        ]
        let lower = model.lowercased()
        for entry in known where lower.contains(entry.prefix) { return entry.name }
        return model.prefix(1).uppercased() + model.dropFirst()
    }
}

#if DEBUG
#Preview("Provider Detail — Claude") {
    ScrollView {
        ProviderDetailView(provider: .claude)
            .environmentObject(UsageStore.preview)
            .padding(14)
    }
    .frame(width: 300, height: 480)
}
#endif
