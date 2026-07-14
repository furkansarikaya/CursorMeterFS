import Foundation

/// Claude provider: credentials from `~/.claude/.credentials.json` (login-Keychain
/// fallback), quota from the OAuth usage endpoint. Model lanes are DYNAMIC — whatever
/// scoped limits the API returns are rendered (Max exposes a Sonnet-scoped weekly lane
/// that Pro doesn't; promotional models like Fable appear and disappear).
final class ClaudeProviderClient: ProviderClient, Sendable {
    let id: Provider = .claude

    private let apiClient = ClaudeAPIClient()

    func fetch() async throws -> ProviderSnapshot {
        let credentials = try ClaudeCredentialsReader.read()   // throws .notLoggedIn

        let usage: ClaudeAPIClient.UsageResponse
        do {
            usage = try await apiClient.fetchUsage(accessToken: credentials.accessToken)
        } catch ClaudeAPIClient.APIError.tokenInvalid {
            // The Claude CLI rotates this token itself; drop our cached copy so the
            // next tick re-reads the file/Keychain instead of retrying the stale value.
            ClaudeCredentialsReader.invalidate()
            throw ProviderError.api("Claude session expired — run `claude` once to refresh, will retry")
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.api(error.localizedDescription)
        }

        var windows: [NamedRateWindow] = []

        if let fiveHour = usage.fiveHour, let window = rateWindow(from: fiveHour, windowMinutes: 300) {
            windows.append(NamedRateWindow(id: "claude-session", title: "Session", window: window))
        }
        if let sevenDay = usage.sevenDay, let window = rateWindow(from: sevenDay, windowMinutes: 7 * 24 * 60) {
            windows.append(NamedRateWindow(
                id: "claude-weekly",
                title: "Weekly",
                window: window,
                pace: UsagePace.compute(window: window)
            ))
        }

        // Dynamic model-scoped weekly lanes — newer `limits[]` shape first,
        // legacy flat seven_day_sonnet/opus fields as fallback.
        let scopedLanes = Self.modelScopedLanes(from: usage.limits)
        if !scopedLanes.isEmpty {
            windows.append(contentsOf: scopedLanes)
        } else {
            if let sonnet = usage.sevenDaySonnet, let window = rateWindow(from: sonnet, windowMinutes: 7 * 24 * 60) {
                windows.append(NamedRateWindow(id: "claude-weekly-sonnet", title: "Sonnet", window: window))
            }
            if let opus = usage.sevenDayOpus, let window = rateWindow(from: opus, windowMinutes: 7 * 24 * 60) {
                windows.append(NamedRateWindow(id: "claude-weekly-opus", title: "Opus", window: window))
            }
        }

        guard !windows.isEmpty else {
            throw ProviderError.api("Claude usage response contained no quota windows")
        }

        let cost = await CostScanner.shared.claudeCostUSD()

        return ProviderSnapshot(
            windows: windows,
            planLabel: planDisplayName(credentials.subscriptionType ?? credentials.rateLimitTier),
            accountLabel: ClaudeCredentialsReader.accountEmail(),
            costUSD: cost,
            costLabel: "est. last \(CostScanner.lookbackDays) days"
        )
    }

    // MARK: - Mapping

    private func rateWindow(from window: ClaudeAPIClient.Window, windowMinutes: Int) -> RateWindow? {
        guard let utilization = window.utilization else { return nil }
        return RateWindow(
            usedPercent: utilization,
            windowMinutes: windowMinutes,
            resetsAt: window.resetsAt.flatMap(Self.parseISO8601)
        )
    }

    /// `limits[]` entries with `group == "weekly"` and `kind == "weekly_scoped"` are
    /// model-scoped weekly limits; the title comes from `scope.model.display_name`.
    /// Static and pure for unit testing.
    static func modelScopedLanes(from limits: [ClaudeAPIClient.LimitEntry]?) -> [NamedRateWindow] {
        guard let limits else { return [] }
        return limits.compactMap { limit in
            guard limit.group == "weekly", limit.kind == "weekly_scoped" else { return nil }
            guard limit.isActive != false else { return nil }
            guard let modelName = Self.nonEmptyStatic(limit.scope?.model?.displayName) else { return nil }
            guard let percent = limit.percent else { return nil }

            let identity = Self.nonEmptyStatic(limit.scope?.model?.id) ?? modelName
            let slug = identity.lowercased().replacingOccurrences(
                of: "[^a-z0-9]+", with: "-", options: .regularExpression)

            return NamedRateWindow(
                id: "claude-weekly-scoped-\(slug)",
                title: "\(modelName) only",
                window: RateWindow(
                    usedPercent: percent,
                    windowMinutes: 7 * 24 * 60,
                    resetsAt: limit.resetsAt.flatMap(Self.parseISO8601)
                )
            )
        }
    }

    private func planDisplayName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "max", "max_20x", "max_5x": return "Max"
        case "pro":                      return "Pro"
        case "team":                     return "Team"
        case "enterprise":               return "Enterprise"
        case "free":                     return "Free"
        default:                         return raw.capitalized
        }
    }

    private static func nonEmptyStatic(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func parseISO8601(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
