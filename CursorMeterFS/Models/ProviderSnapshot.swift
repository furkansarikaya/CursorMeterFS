import Foundation

// MARK: - RateWindow

/// One quota window rendered as a progress lane: "Session", "Weekly", "Sonnet only"…
/// Percentages and reset instants come straight from each provider's API — never computed
/// locally from token counts.
struct RateWindow: Equatable {
    /// 0–100. Values outside the range are clamped by the computed properties.
    let usedPercent: Double
    /// Window length in minutes (300 = 5h session, 10 080 = weekly). nil when unknown.
    let windowMinutes: Int?
    /// When this window resets. nil when the API omits it.
    let resetsAt: Date?

    var fraction: Double { min(max(usedPercent / 100.0, 0), 1) }
    var percentInt: Int { Int(fraction * 100) }
    var remainingPercent: Double { max(0, 100 - usedPercent) }

    /// Compact remaining-time text: "3h 53m", "3d 20h", "42m"; nil when resetsAt is unknown.
    func resetDescription(now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return "now" }
        let minutes = Int(seconds / 60) % 60
        let hours   = Int(seconds / 3_600) % 24
        let days    = Int(seconds / 86_400)
        if days > 0  { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }

    func status(warningThreshold: Double, criticalThreshold: Double) -> UsageStatus {
        UsageStatus.from(
            fraction: fraction,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold
        )
    }
}

// MARK: - NamedRateWindow

/// A titled window lane. The set of lanes is fully dynamic — whatever the provider's API
/// returns is rendered (e.g. Claude Max exposes a scoped "Sonnet only" weekly limit that
/// Pro accounts don't have; promotional models like Fable appear and disappear).
struct NamedRateWindow: Equatable, Identifiable {
    let id: String
    let title: String
    let window: RateWindow
    /// Consumption pace vs. a linear burn-down of the window; computed locally, optional.
    var pace: UsagePace?

    init(id: String, title: String, window: RateWindow, pace: UsagePace? = nil) {
        self.id = id
        self.title = title
        self.window = window
        self.pace = pace
    }
}

// MARK: - UsagePace

/// How actual consumption compares to a linear burn-down of the window.
/// "Behind (-42%)" = using slower than the window allows (good).
struct UsagePace: Equatable {
    enum Stage: String {
        case onTrack = "On track"
        case ahead   = "Ahead"
        case behind  = "Behind"
    }

    let stage: Stage
    /// actualUsedPercent − expectedUsedPercent (positive = consuming faster than linear).
    let deltaPercent: Double
    /// Whether the current rate projects to last until the window resets.
    let willLastToReset: Bool

    var displayText: String {
        let sign = deltaPercent >= 0 ? "+" : ""
        let tail = willLastToReset ? "Lasts to reset" : "May run out"
        return "Pace: \(stage.rawValue) (\(sign)\(Int(deltaPercent.rounded()))%) · \(tail)"
    }

    /// Pure computation from window geometry — no history file needed.
    /// Returns nil when the window is too young (< 5% elapsed) for a meaningful signal.
    static func compute(window: RateWindow, now: Date = Date()) -> UsagePace? {
        guard let resetsAt = window.resetsAt,
              let minutes = window.windowMinutes, minutes > 0 else { return nil }
        let windowSeconds = TimeInterval(minutes * 60)
        let windowStart = resetsAt.addingTimeInterval(-windowSeconds)
        let elapsed = now.timeIntervalSince(windowStart)
        guard elapsed > 0, elapsed <= windowSeconds else { return nil }

        let elapsedFraction = elapsed / windowSeconds
        guard elapsedFraction >= 0.05 else { return nil }

        let expected = elapsedFraction * 100
        let delta = window.usedPercent - expected

        let stage: Stage
        switch delta {
        case ..<(-10): stage = .behind
        case 10...:    stage = .ahead
        default:       stage = .onTrack
        }

        // Linear projection: at the current rate, where does usage land at reset?
        let projectedAtReset = window.usedPercent / elapsedFraction
        return UsagePace(
            stage: stage,
            deltaPercent: delta,
            willLastToReset: projectedAtReset <= 100
        )
    }
}

// MARK: - ProviderSnapshot

/// The common UI shape every provider produces. Providers return data; the app owns UI.
struct ProviderSnapshot: Equatable {
    /// Ordered lanes: Session, Weekly, then any dynamic per-model windows.
    var windows: [NamedRateWindow]
    /// Plan tier badge: "Max", "Plus", "Pro Plan"…
    var planLabel: String?
    /// Account e-mail shown in Settings (displayed in UI, never logged or exported).
    var accountLabel: String?
    /// Locally estimated spend (token counts from local logs × price table).
    var costUSD: Double?
    /// What the cost figure covers, e.g. "est. last 30 days".
    var costLabel: String?
    /// Per-request feed (Cursor invoice events; empty for providers without one).
    var recentEvents: [UsageEvent]
    /// Model → request count fallback shown when no per-request events exist.
    var modelBreakdown: [String: Int]
    /// Cursor-only extras (on-demand spend card, JSON export). nil for other providers.
    var cursorDetails: UsageData?
    var updatedAt: Date

    init(
        windows: [NamedRateWindow],
        planLabel: String? = nil,
        accountLabel: String? = nil,
        costUSD: Double? = nil,
        costLabel: String? = nil,
        recentEvents: [UsageEvent] = [],
        modelBreakdown: [String: Int] = [:],
        cursorDetails: UsageData? = nil,
        updatedAt: Date = Date()
    ) {
        self.windows = windows
        self.planLabel = planLabel
        self.accountLabel = accountLabel
        self.costUSD = costUSD
        self.costLabel = costLabel
        self.recentEvents = recentEvents
        self.modelBreakdown = modelBreakdown
        self.cursorDetails = cursorDetails
        self.updatedAt = updatedAt
    }

    /// The headline window (first lane) — drives the menu bar icon and tab underline.
    var primary: RateWindow? { windows.first?.window }
}

// MARK: - ProviderUIState

/// Per-provider UI state. Keeps the last good snapshot on error so the popover can show
/// stale data with an error badge instead of going blank (graceful degradation).
struct ProviderUIState: Equatable {
    var snapshot: ProviderSnapshot?
    var phase: Phase = .loading

    enum Phase: Equatable {
        case loading
        case ready
        case loggedOut
        case error(String)
    }
}
