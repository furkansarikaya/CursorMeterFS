import Foundation

/// Codex provider: credentials from `~/.codex/auth.json`, quota from the ChatGPT wham/usage
/// API, with a fully offline fallback to the Codex CLI's own session logs. All reads are
/// user-home; refreshed tokens live in memory only (auth.json is never written).
actor CodexProviderClient: ProviderClient {
    nonisolated let id: Provider = .codex

    private let apiClient = CodexAPIClient()
    /// In-memory replacement token after a successful refresh; auth.json stays untouched.
    private var refreshedAccessToken: String?

    func fetch() async throws -> ProviderSnapshot {
        let credentials = try CodexAuthReader.read()   // throws .notLoggedIn

        guard let fileToken = credentials.accessToken else {
            // API-key-only install: wham/usage needs OAuth — use the session-log fallback.
            return try snapshotFromSessionLogs()
        }

        let token = refreshedAccessToken ?? fileToken
        do {
            let usage = try await apiClient.fetchUsage(accessToken: token, accountId: credentials.accountId)
            return await snapshot(from: usage)

        } catch CodexAPIClient.APIError.tokenInvalid {
            // One refresh attempt (in-memory), then retry; else fall back to session logs.
            if let refreshToken = credentials.refreshToken, !refreshToken.isEmpty,
               let newToken = try? await apiClient.refreshAccessToken(refreshToken: refreshToken) {
                refreshedAccessToken = newToken
                if let usage = try? await apiClient.fetchUsage(accessToken: newToken, accountId: credentials.accountId) {
                    return await snapshot(from: usage)
                }
            }
            return try snapshotFromSessionLogs()

        } catch {
            // Network failure — the CLI's own logs still carry recent server-reported limits.
            if let offline = try? snapshotFromSessionLogs() {
                return offline
            }
            throw ProviderError.api(error.localizedDescription)
        }
    }

    // MARK: - API mapping

    private func snapshot(from usage: CodexAPIClient.UsageResponse) async -> ProviderSnapshot {
        var windows: [NamedRateWindow] = []

        if let primary = usage.rateLimit?.primaryWindow {
            windows.append(NamedRateWindow(
                id: "codex-session",
                title: "Session",
                window: rateWindow(from: primary)
            ))
        }
        if let secondary = usage.rateLimit?.secondaryWindow {
            let window = rateWindow(from: secondary)
            windows.append(NamedRateWindow(
                id: "codex-weekly",
                title: "Weekly",
                window: window,
                pace: UsagePace.compute(window: window)
            ))
        }

        // Dynamic model-specific limits — render whatever the API returns
        // (e.g. promotional models that appear and disappear).
        for (index, extra) in (usage.additionalRateLimits ?? []).enumerated() {
            guard let extraWindow = extra.rateLimit?.primaryWindow
                ?? extra.rateLimit?.secondaryWindow else { continue }
            let title = extra.limitName ?? "Limit \(index + 1)"
            windows.append(NamedRateWindow(
                id: "codex-extra-\(extra.limitName ?? String(index))",
                title: title,
                window: rateWindow(from: extraWindow)
            ))
        }

        let cost = await CostScanner.shared.codexCostUSD()

        return ProviderSnapshot(
            windows: windows,
            planLabel: usage.planType.map(planDisplayName),
            costUSD: cost,
            costLabel: "est. last \(CostScanner.lookbackDays) days"
        )
    }

    private func rateWindow(from snapshot: CodexAPIClient.WindowSnapshot) -> RateWindow {
        RateWindow(
            usedPercent: snapshot.usedPercent,
            windowMinutes: snapshot.limitWindowSeconds.map { $0 / 60 },
            resetsAt: snapshot.resetAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    // MARK: - Offline fallback (session logs)

    private func snapshotFromSessionLogs() throws -> ProviderSnapshot {
        guard let logged = CodexSessionLogReader.latestRateLimits() else {
            throw ProviderError.api("Codex usage unavailable — no API access and no recent session logs")
        }

        var windows: [NamedRateWindow] = []
        if let primary = logged.primary {
            windows.append(NamedRateWindow(
                id: "codex-session",
                title: "Session",
                window: RateWindow(
                    usedPercent: primary.usedPercent,
                    windowMinutes: primary.windowMinutes,
                    resetsAt: primary.resetsAt
                )
            ))
        }
        if let secondary = logged.secondary {
            let window = RateWindow(
                usedPercent: secondary.usedPercent,
                windowMinutes: secondary.windowMinutes,
                resetsAt: secondary.resetsAt
            )
            windows.append(NamedRateWindow(
                id: "codex-weekly",
                title: "Weekly",
                window: window,
                pace: UsagePace.compute(window: window)
            ))
        }
        guard !windows.isEmpty else {
            throw ProviderError.api("Codex usage unavailable")
        }

        return ProviderSnapshot(
            windows: windows,
            planLabel: logged.planType.map(planDisplayName),
            updatedAt: logged.loggedAt ?? Date()
        )
    }

    private func planDisplayName(_ raw: String) -> String {
        switch raw {
        case "plus":           return "Plus"
        case "pro":            return "Pro"
        case "team":           return "Team"
        case "business":       return "Business"
        case "enterprise":     return "Enterprise"
        case "edu", "education": return "Education"
        case "free":           return "Free"
        default:               return raw.capitalized
        }
    }
}
