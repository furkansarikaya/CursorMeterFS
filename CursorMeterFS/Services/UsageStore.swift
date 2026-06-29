import Foundation
import Combine

/// Central state machine for all usage data.
/// Drives the menu bar icon and popover views via `@Published` properties.
@MainActor
final class UsageStore: ObservableObject {

    // MARK: - App State
    enum AppState: Equatable {
        case loading
        case ready
        case error(String)
        case loggedOut   // Cursor not logged in
    }

    // MARK: - Published state
    @Published var appState: AppState = .loading
    @Published var usage: UsageData = .placeholder
    @Published var recentEvents: [UsageEvent] = []
    @Published var modelBreakdown: [String: Int] = [:]   // model → request count from /api/usage
    @Published var lastRefreshed: Date?
    @Published var isRefreshing: Bool = false

    // MARK: - Settings (persisted via UserDefaults — no secrets here)
    @Published var refreshIntervalMinutes: Int {
        didSet { UserDefaults.standard.set(refreshIntervalMinutes, forKey: "refreshIntervalMinutes")
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
    @Published var accountEmail: String = ""
    @Published var teamName: String = ""
    @Published var isTeamAdmin: Bool = false
    @Published var isEnterpriseUser: Bool = false
    @Published var exportEnabled: Bool {
        didSet { UserDefaults.standard.set(exportEnabled, forKey: "exportEnabled") }
    }

    // MARK: - Private
    private let apiClient = CursorAPIClient()
    private let teamResolver = TeamResolver()
    private var refreshTimer: Timer?
    private var currentSessionToken: String?
    private var currentUserId: String?

    // MARK: - Init
    init() {
        self.refreshIntervalMinutes = UserDefaults.standard.integer(forKey: "refreshIntervalMinutes").nonZeroOr(5)
        self.warningThreshold       = UserDefaults.standard.double(forKey: "warningThreshold").nonZeroOr(0.70)
        self.criticalThreshold      = UserDefaults.standard.double(forKey: "criticalThreshold").nonZeroOr(0.90)
        self.notificationsEnabled   = UserDefaults.standard.bool(forKey: "notificationsEnabled", default: true)
        self.notifyOnReset          = UserDefaults.standard.bool(forKey: "notifyOnReset", default: true)
        self.showRecentRequests     = UserDefaults.standard.bool(forKey: "showRecentRequests", default: true)
        self.recentRequestCount     = UserDefaults.standard.integer(forKey: "recentRequestCount").nonZeroOr(10)
        self.iconStyle              = MenuBarIconStyle(rawValue: UserDefaults.standard.string(forKey: "iconStyle") ?? "") ?? .dualBar
        self.iconColorMode          = IconColorMode(rawValue: UserDefaults.standard.string(forKey: "iconColorMode") ?? "") ?? .color
        self.exportEnabled = UserDefaults.standard.bool(forKey: "exportEnabled", default: false)
    }

    // MARK: - Lifecycle

    func start() {
        Task { await refresh() }
        startTimer()
    }

    func signOut() {
        currentSessionToken = nil
        currentUserId       = nil
        accountEmail        = ""
        teamName            = ""
        isTeamAdmin         = false
        isEnterpriseUser    = false
        usage               = .placeholder
        recentEvents        = []
        modelBreakdown      = [:]
        appState            = .loggedOut
        stopTimer()
    }

    // MARK: - Refresh

    @discardableResult
    func refresh() async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }

        // 1. Resolve credentials
        let (token, userId, plan, email) = await resolveCredentials()
        guard let token, let userId else {
            appState = .loggedOut
            return false
        }

        currentSessionToken = token
        currentUserId       = userId
        if let email { accountEmail = email }

        // 2. Fetch usage
        do {
            let teamId = await teamResolver.resolveTeamId(sessionToken: token, plan: plan)

            async let usageResp  = apiClient.fetchUsage(userId: userId, sessionToken: token)
            async let invoiceResp = apiClient.fetchMonthlyInvoice(
                month: Calendar.current.component(.month, from: Date()),
                year:  Calendar.current.component(.year,  from: Date()),
                sessionToken: token,
                teamId: teamId,
                includeEvents: showRecentRequests
            )
            async let hardLimitResp     = apiClient.fetchHardLimit(sessionToken: token, teamId: teamId)
            async let usageBasedEnabled = apiClient.fetchUsageBasedEnabled(sessionToken: token, teamId: teamId)
            async let meResp            = apiClient.fetchMe(sessionToken: token)

            let (usageData, invoice, hardLimit, ubEnabled, me) = try await (usageResp, invoiceResp, hardLimitResp, usageBasedEnabled, meResp)

            // 3. Parse billing cycle start
            let billingStart: Date
            if let startStr = usageData.startOfMonth {
                billingStart = ISO8601DateFormatter().date(from: startStr) ?? Date.startOfCurrentBillingMonth()
            } else {
                billingStart = Date.startOfCurrentBillingMonth()
            }

            // 4. Detect plan reset
            let detectedPlan = plan
            let previousBillingStart = usage.billingCycleStart
            let cycleReset = billingStart > previousBillingStart && usage.used > 0

            // 5. Build UsageData
            let newUsage = UsageData(
                used: usageData.totalUsed,
                total: usageData.maxRequestUsage ?? 500,  // safe fallback; always prefer API value
                onDemandSpendUSD: invoice.totalUSD,
                hardLimitUSD: hardLimit.hardLimit,
                usageBasedEnabled: ubEnabled,
                billingCycleStart: billingStart,
                plan: detectedPlan
            )

            // 6. Parse recent events
            let events: [UsageEvent] = (invoice.usageEvents ?? [])
                .enumerated()
                .compactMap { UsageEvent.from($0.element, index: $0.offset) }
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(recentRequestCount)
                .map { $0 }

            // Model breakdown from /api/usage.
            // Cursor buckets all quota requests under "gpt-4" regardless of actual model.
            // Only expose the breakdown when there are MULTIPLE distinct models — a single
            // "gpt-4" entry is just the aggregate counter, not a real model label.
            let rawBreakdown = (usageData.models ?? [:])
                .compactMapValues { $0.numRequests }
                .filter { $0.value > 0 }
            let breakdown = rawBreakdown.count > 1 ? rawBreakdown : [:]

            // 7. Update state on main thread (already @MainActor)
            usage = newUsage
            recentEvents = events
            modelBreakdown = breakdown
            if let t = me.teamName,   !t.isEmpty  { teamName       = t }
            if let a = me.isTeamAdmin              { isTeamAdmin    = a }
            if let e = me.isEnterpriseUser         { isEnterpriseUser = e }
            if let em = me.email, !em.isEmpty      { accountEmail   = em }
            lastRefreshed = Date()
            appState = .ready

            // 8. Side effects
            NotificationService.shared.notifyIfNeeded(
                usage: newUsage,
                warningThreshold: warningThreshold,
                criticalThreshold: criticalThreshold,
                notifyOnReset: notifyOnReset,
                enabled: notificationsEnabled
            )

            if cycleReset && notifyOnReset {
                NotificationService.shared.notifyReset(plan: detectedPlan)
                NotificationService.shared.resetFiredThresholds()
            }

            if exportEnabled {
                UsageExporter.shared.export(usage: newUsage)
            }

            return true

        } catch CursorAPIClient.APIError.tokenInvalid {
            currentSessionToken = nil
            appState = .error("Session expired. Refreshing credentials...")
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await refresh()
            }
            return false

        } catch {
            appState = .error(error.localizedDescription)
            return false
        }
    }

    // MARK: - Credential resolution (always reads from Cursor's SQLite)

    private func resolveCredentials() async -> (token: String?, userId: String?, plan: Plan, email: String?) {
        // Always read from Cursor's local SQLite — fast (~1 ms) and avoids Keychain prompts.
        // The token is already in Cursor's readable database, so Keychain caching adds no
        // meaningful security benefit and causes per-binary ACL prompts in development.
        return await Task.detached(priority: .userInitiated) {
            do {
                let creds = try CursorTokenReader.readCredentials()
                return (creds.sessionToken, creds.userId, creds.plan, creds.email)
            } catch {
                print("[CursorMeterFS] Token read failed: \(error.localizedDescription)")
                return (nil, nil, .free, nil)
            }
        }.value
    }

    // MARK: - Timer
    private func startTimer() {
        stopTimer()
        let interval = TimeInterval(refreshIntervalMinutes * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func restartTimer() {
        stopTimer()
        startTimer()
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

// MARK: - Preview helper
extension UsageStore {
    /// Pre-populated store for SwiftUI Canvas previews.
    static var preview: UsageStore {
        let store = UsageStore()
        store.appState = .ready
        store.usage = UsageData(
            used: 420,
            total: 1000,
            onDemandSpendUSD: 1.25,
            hardLimitUSD: 50.0,
            usageBasedEnabled: true,
            billingCycleStart: Date().addingTimeInterval(-15 * 86_400),
            plan: .pro
        )
        store.recentEvents = [
            UsageEvent(id: "1", model: "claude-sonnet-4-6",
                       inputTokens: 1200, outputTokens: 450, costUSD: 0.0045,
                       timestamp: Date().addingTimeInterval(-120), kind: .agent),
            UsageEvent(id: "2", model: "gpt-4o",
                       inputTokens: 800, outputTokens: 200, costUSD: 0.002,
                       timestamp: Date().addingTimeInterval(-600), kind: .chat),
            UsageEvent(id: "3", model: "claude-opus-4-8",
                       inputTokens: 2000, outputTokens: 800, costUSD: 0.018,
                       timestamp: Date().addingTimeInterval(-3_600), kind: .agent),
        ]
        store.accountEmail = "furkan@example.com"
        store.showRecentRequests = true
        store.lastRefreshed = Date()
        return store
    }

    /// Logged-out state for onboarding preview.
    static var previewLoggedOut: UsageStore {
        let store = UsageStore()
        store.appState = .loggedOut
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
