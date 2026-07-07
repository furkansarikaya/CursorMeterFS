import Foundation
import Combine

/// Central state machine for all usage data, now multi-provider.
/// Holds one `ProviderUIState` per enabled provider; refresh fans out concurrently.
/// Drives the menu bar icon (selected provider) and popover views via `@Published`.
@MainActor
final class UsageStore: ObservableObject {

    // MARK: - Published state
    @Published var providerStates: [Provider: ProviderUIState] = [:]
    @Published var selectedProvider: Provider {
        didSet { UserDefaults.standard.set(selectedProvider.rawValue, forKey: "selectedProvider") }
    }
    @Published var lastRefreshed: Date?
    @Published var isRefreshing: Bool = false

    // MARK: - Settings (persisted via UserDefaults — no secrets here)
    @Published var refreshFrequency: RefreshFrequency {
        didSet { UserDefaults.standard.set(refreshFrequency.rawValue, forKey: "refreshFrequency")
                 restartTimer() }
    }
    @Published var warningThreshold: Double {
        didSet { UserDefaults.standard.set(warningThreshold, forKey: "warningThreshold") }
    }
    @Published var criticalThreshold: Double {
        didSet { UserDefaults.standard.set(criticalThreshold, forKey: "criticalThreshold") }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    @Published var notifyOnReset: Bool {
        didSet { UserDefaults.standard.set(notifyOnReset, forKey: "notifyOnReset") }
    }
    @Published var showRecentRequests: Bool {
        didSet { UserDefaults.standard.set(showRecentRequests, forKey: "showRecentRequests") }
    }
    @Published var recentRequestCount: Int {
        didSet { UserDefaults.standard.set(recentRequestCount, forKey: "recentRequestCount") }
    }
    @Published var iconStyle: MenuBarIconStyle {
        didSet { UserDefaults.standard.set(iconStyle.rawValue, forKey: "iconStyle") }
    }
    @Published var iconColorMode: IconColorMode {
        didSet { UserDefaults.standard.set(iconColorMode.rawValue, forKey: "iconColorMode") }
    }
    @Published var exportEnabled: Bool {
        didSet { UserDefaults.standard.set(exportEnabled, forKey: "exportEnabled") }
    }
    @Published private(set) var providerEnabled: [Provider: Bool]

    // MARK: - Private
    private let clients: [Provider: any ProviderClient]
    private var timerTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private let adaptiveRefreshPolicy = AdaptiveRefreshPolicy()

    /// When the popover was last opened. Feeds `AdaptiveRefreshPolicy` and never moves
    /// backwards; nil until the user opens the popover for the first time this launch.
    private(set) var lastPopoverOpenAt: Date?

    // MARK: - Init
    init(clients: [Provider: any ProviderClient]? = nil) {
        self.clients = clients ?? [
            .cursor: CursorProviderClient(),
            .codex:  CodexProviderClient(),
            .claude: ClaudeProviderClient(),
        ]

        if let saved = UserDefaults.standard.string(forKey: "refreshFrequency"),
           let frequency = RefreshFrequency(rawValue: saved) {
            self.refreshFrequency = frequency
        } else if UserDefaults.standard.object(forKey: "refreshIntervalMinutes") != nil {
            // Migrate the legacy numeric-minutes setting to the closest fixed cadence.
            let legacyMinutes = UserDefaults.standard.integer(forKey: "refreshIntervalMinutes").nonZeroOr(5)
            self.refreshFrequency = .closestFixed(toMinutes: legacyMinutes)
        } else {
            self.refreshFrequency = .adaptive
        }
        self.warningThreshold       = UserDefaults.standard.double(forKey: "warningThreshold").nonZeroOr(0.70)
        self.criticalThreshold      = UserDefaults.standard.double(forKey: "criticalThreshold").nonZeroOr(0.90)
        self.notificationsEnabled   = UserDefaults.standard.bool(forKey: "notificationsEnabled", default: true)
        self.notifyOnReset          = UserDefaults.standard.bool(forKey: "notifyOnReset", default: true)
        self.showRecentRequests     = UserDefaults.standard.bool(forKey: "showRecentRequests", default: true)
        self.recentRequestCount     = UserDefaults.standard.integer(forKey: "recentRequestCount").nonZeroOr(10)
        self.iconStyle              = MenuBarIconStyle(rawValue: UserDefaults.standard.string(forKey: "iconStyle") ?? "") ?? .dualBar
        self.iconColorMode          = IconColorMode(rawValue: UserDefaults.standard.string(forKey: "iconColorMode") ?? "") ?? .color
        self.exportEnabled = UserDefaults.standard.bool(forKey: "exportEnabled", default: false)

        var enabled: [Provider: Bool] = [:]
        for provider in Provider.allCases {
            enabled[provider] = UserDefaults.standard.bool(
                forKey: "providerEnabled.\(provider.rawValue)", default: true)
        }
        self.providerEnabled = enabled

        let savedSelection = UserDefaults.standard.string(forKey: "selectedProvider")
            .flatMap(Provider.init(rawValue:))
        let initialSelection = savedSelection ?? Provider.allCases.first ?? .cursor
        self.selectedProvider = enabled[initialSelection] == true
            ? initialSelection
            : (Provider.allCases.first { enabled[$0] == true } ?? initialSelection)
    }

    // MARK: - Provider management

    var enabledProviders: [Provider] {
        Provider.allCases.filter { providerEnabled[$0] ?? true }
    }

    func state(for provider: Provider) -> ProviderUIState {
        providerStates[provider] ?? ProviderUIState()
    }

    var selectedState: ProviderUIState { state(for: selectedProvider) }

    func setProviderEnabled(_ provider: Provider, enabled: Bool) {
        // Never allow zero enabled providers.
        if !enabled, enabledProviders == [provider] { return }
        providerEnabled[provider] = enabled
        UserDefaults.standard.set(enabled, forKey: "providerEnabled.\(provider.rawValue)")
        if !enabled {
            providerStates[provider] = nil
            if selectedProvider == provider, let fallback = enabledProviders.first {
                selectedProvider = fallback
            }
        } else {
            Task { await refresh() }
        }
    }

    // MARK: - Lifecycle

    func start() {
        Task { await refresh() }
        startTimer()
    }

    // MARK: - Refresh (concurrent fan-out over enabled providers)

    @discardableResult
    func refresh() async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }

        refreshGeneration += 1
        let generation = refreshGeneration
        let providers = enabledProviders

        // First-ever fetch for a provider shows a loading state (not a blank).
        for provider in providers where providerStates[provider] == nil {
            providerStates[provider] = ProviderUIState()
        }

        await withTaskGroup(of: (Provider, Result<ProviderSnapshot, Error>).self) { group in
            for provider in providers {
                guard let client = clients[provider] else { continue }
                group.addTask {
                    do {
                        return (provider, .success(try await client.fetch()))
                    } catch {
                        return (provider, .failure(error))
                    }
                }
            }
            for await (provider, result) in group {
                // A newer refresh (or a settings change) supersedes this one.
                guard generation == refreshGeneration,
                      providerEnabled[provider] ?? false else { continue }
                apply(result, to: provider)
            }
        }

        lastRefreshed = Date()
        return true
    }

    private func apply(_ result: Result<ProviderSnapshot, Error>, to provider: Provider) {
        var state = providerStates[provider] ?? ProviderUIState()
        switch result {
        case .success(let fresh):
            let snapshot = backfillingResetTimes(fresh, from: state.snapshot)
            if provider == .cursor {
                handleCursorSideEffects(new: snapshot, old: state.snapshot)
            }
            state.snapshot = snapshot
            state.phase = .ready
            notifyThresholds(provider: provider, snapshot: snapshot)

        case .failure(let error):
            if case ProviderError.notLoggedIn = error {
                state.phase = .loggedOut
            } else {
                // Keep the last snapshot visible; the view adds an error badge.
                state.phase = .error(error.localizedDescription)
            }
        }
        providerStates[provider] = state
    }

    /// A momentarily missing `resetsAt` must not flicker the UI — keep the last known
    /// (still future) reset instant for the same window lane.
    private func backfillingResetTimes(
        _ fresh: ProviderSnapshot, from old: ProviderSnapshot?
    ) -> ProviderSnapshot {
        guard let old else { return fresh }
        var snapshot = fresh
        snapshot.windows = fresh.windows.map { lane in
            guard lane.window.resetsAt == nil,
                  let oldLane = old.windows.first(where: { $0.id == lane.id }),
                  let oldReset = oldLane.window.resetsAt,
                  oldReset > Date() else { return lane }
            return NamedRateWindow(
                id: lane.id,
                title: lane.title,
                window: RateWindow(
                    usedPercent: lane.window.usedPercent,
                    windowMinutes: lane.window.windowMinutes ?? oldLane.window.windowMinutes,
                    resetsAt: oldReset
                ),
                pace: lane.pace
            )
        }
        return snapshot
    }

    // MARK: - Side effects

    private func notifyThresholds(provider: Provider, snapshot: ProviderSnapshot) {
        guard let primary = snapshot.primary else { return }
        // One fire per window instance: a new reset instant re-arms the thresholds.
        let windowKey = primary.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "static"
        NotificationService.shared.notifyIfNeeded(
            providerName: provider.displayName,
            fraction: primary.fraction,
            percentInt: primary.percentInt,
            resetDescription: primary.resetDescription(),
            cycleKey: "\(provider.rawValue)-\(windowKey)",
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold,
            enabled: notificationsEnabled
        )
    }

    private func handleCursorSideEffects(new: ProviderSnapshot, old: ProviderSnapshot?) {
        guard let details = new.cursorDetails else { return }
        if notifyOnReset,
           let oldDetails = old?.cursorDetails,
           details.billingCycleStart > oldDetails.billingCycleStart,
           oldDetails.used > 0 {
            NotificationService.shared.notifyReset(plan: details.plan)
            NotificationService.shared.resetFiredThresholds()
        }
        if exportEnabled {
            UsageExporter.shared.export(usage: details)
        }
    }

    // MARK: - Timer
    // A low-priority detached-Task sleep loop instead of `Timer.scheduledTimer`: it doesn't
    // pin a wakeup to the main run loop, coalesces better with the OS's own scheduling, and
    // lets `self` deallocate mid-sleep (weak capture, never held across `Task.sleep`).
    private func startTimer() {
        stopTimer()

        switch refreshFrequency {
        case .manual:
            return

        case .adaptive:
            timerTask = Task.detached(priority: .utility) { [weak self] in
                while !Task.isCancelled {
                    // `self` is only borrowed for the brief decision computation below —
                    // never held across `Task.sleep` — so the store can deallocate mid-sleep.
                    guard let delay = await self?.nextAdaptiveDecision().delay else { return }
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }

        default:
            guard let interval = refreshFrequency.seconds else { return }
            timerTask = Task.detached(priority: .utility) { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func restartTimer() {
        stopTimer()
        startTimer()
    }

    /// Reads live power/thermal signals and computes this tick's sleep duration.
    /// Kept as a short `@MainActor` hop so the caller never holds `self` across the sleep.
    private func nextAdaptiveDecision() async -> AdaptiveRefreshPolicy.Decision {
        let decision = adaptiveRefreshPolicy.nextDelay(for: AdaptiveRefreshPolicy.Input(
            now: Date(),
            lastPopoverOpenAt: lastPopoverOpenAt,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState
        ))
        #if DEBUG
        print("[CursorMeterFS] adaptive refresh: reason=\(decision.reason.rawValue) delay=\(Int(decision.delay))s")
        #endif
        return decision
    }

    // MARK: - Popover interaction

    /// Called when the popover is shown. Feeds the adaptive cadence and, if the last
    /// refresh is stale, kicks off an immediate refresh so the user never opens the
    /// popover to see minutes-old numbers.
    func notePopoverOpened() {
        lastPopoverOpenAt = Date()
        if refreshFrequency == .adaptive {
            restartTimer()
        }
        let staleThreshold: TimeInterval = 60
        let isStale = lastRefreshed.map { Date().timeIntervalSince($0) > staleThreshold } ?? true
        if isStale {
            Task { await refresh() }
        }
    }

    // MARK: - Sleep / wake suspension

    /// Suspends the background refresh loop entirely — called when the system sleeps,
    /// the screen locks, or the session becomes inactive.
    func suspend() {
        stopTimer()
    }

    /// Resumes the background refresh loop (a no-op in `.manual` mode) and performs one
    /// immediate refresh so data isn't stale after a long sleep.
    func resume() {
        startTimer()
        Task { await refresh() }
    }
}

// MARK: - Settings enums

enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case battery      = "battery"
    case circular     = "circular"
    case minimal      = "minimal"
    case minimalCount = "minimalCount"
    case segments     = "segments"
    case dualBar      = "dualBar"
    case countBar     = "countBar"
    case gauge        = "gauge"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .battery:      return "Battery"
        case .circular:     return "Circular"
        case .minimal:      return "Minimal %"
        case .minimalCount: return "Minimal #"
        case .segments:     return "Segments"
        case .dualBar:      return "Dual Bar %"
        case .countBar:     return "Dual Bar #"
        case .gauge:        return "Gauge"
        }
    }
}

enum IconColorMode: String, CaseIterable, Identifiable {
    case mono  = "mono"
    case color = "color"

    var id: String { rawValue }
    var displayName: String { rawValue == "mono" ? "Mono" : "Color" }
}

// MARK: - Preview helpers
extension UsageStore {
    /// Pre-populated store for SwiftUI Canvas previews.
    static var preview: UsageStore {
        let store = UsageStore()
        let cursorDetails = UsageData(
            used: 420,
            total: 1000,
            onDemandSpendUSD: 1.25,
            hardLimitUSD: 50.0,
            usageBasedEnabled: true,
            billingCycleStart: Date().addingTimeInterval(-15 * 86_400),
            plan: .pro
        )
        store.providerStates[.cursor] = ProviderUIState(
            snapshot: ProviderSnapshot(
                windows: [NamedRateWindow(
                    id: "cursor-monthly",
                    title: "Monthly Quota",
                    window: RateWindow(usedPercent: 42, windowMinutes: nil,
                                       resetsAt: Date().addingTimeInterval(15 * 86_400))
                )],
                planLabel: "Pro Plan",
                accountLabel: "furkan@example.com",
                costUSD: 1.25,
                costLabel: "on-demand this month",
                recentEvents: [
                    UsageEvent(id: "1", model: "claude-sonnet-4-6",
                               inputTokens: 1200, outputTokens: 450, costUSD: 0.0045,
                               timestamp: Date().addingTimeInterval(-120), kind: .agent),
                    UsageEvent(id: "2", model: "gpt-4o",
                               inputTokens: 800, outputTokens: 200, costUSD: 0.002,
                               timestamp: Date().addingTimeInterval(-600), kind: .chat),
                ],
                cursorDetails: cursorDetails
            ),
            phase: .ready
        )
        store.providerStates[.claude] = ProviderUIState(
            snapshot: ProviderSnapshot(
                windows: [
                    NamedRateWindow(id: "claude-session", title: "Session",
                                    window: RateWindow(usedPercent: 2, windowMinutes: 300,
                                                       resetsAt: Date().addingTimeInterval(3.9 * 3_600))),
                    NamedRateWindow(id: "claude-weekly", title: "Weekly",
                                    window: RateWindow(usedPercent: 3, windowMinutes: 10_080,
                                                       resetsAt: Date().addingTimeInterval(3.8 * 86_400)),
                                    pace: UsagePace(stage: .behind, deltaPercent: -42, willLastToReset: true)),
                    NamedRateWindow(id: "claude-weekly-scoped-sonnet", title: "Sonnet only",
                                    window: RateWindow(usedPercent: 0, windowMinutes: 10_080,
                                                       resetsAt: Date().addingTimeInterval(3.8 * 86_400))),
                ],
                planLabel: "Max",
                costUSD: 12.40,
                costLabel: "est. last 30 days"
            ),
            phase: .ready
        )
        store.providerStates[.codex] = ProviderUIState(
            snapshot: ProviderSnapshot(
                windows: [
                    NamedRateWindow(id: "codex-session", title: "Session",
                                    window: RateWindow(usedPercent: 2, windowMinutes: 300,
                                                       resetsAt: Date().addingTimeInterval(2 * 3_600))),
                    NamedRateWindow(id: "codex-weekly", title: "Weekly",
                                    window: RateWindow(usedPercent: 1, windowMinutes: 10_080,
                                                       resetsAt: Date().addingTimeInterval(6 * 86_400))),
                ],
                planLabel: "Plus"
            ),
            phase: .ready
        )
        store.selectedProvider = .claude
        store.lastRefreshed = Date()
        return store
    }

    /// Logged-out state for onboarding preview.
    static var previewLoggedOut: UsageStore {
        let store = UsageStore()
        store.providerStates[.cursor] = ProviderUIState(snapshot: nil, phase: .loggedOut)
        store.selectedProvider = .cursor
        return store
    }
}

// MARK: - Helpers
private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}
private extension Double {
    func nonZeroOr(_ fallback: Double) -> Double { self == 0 ? fallback : self }
}
private extension UserDefaults {
    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        object(forKey: key) == nil ? defaultValue : bool(forKey: key)
    }
}
