import Foundation

/// Cursor provider: reads credentials from Cursor's local `state.vscdb` (read-only,
/// user-home, no admin) and fetches quota/invoice data from cursor.com.
/// This is the former `UsageStore.refresh()` body, repackaged behind `ProviderClient`.
final class CursorProviderClient: ProviderClient, Sendable {
    let id: Provider = .cursor

    private let apiClient = CursorAPIClient()
    private let teamResolver = TeamResolver()

    func fetch() async throws -> ProviderSnapshot {
        // 1. Credentials — always read from Cursor's SQLite (fast, ~1 ms, no prompts).
        let credentials: CursorTokenReader.CursorCredentials
        do {
            credentials = try CursorTokenReader.readCredentials()
        } catch {
            throw ProviderError.notLoggedIn
        }
        let token = credentials.sessionToken
        let plan = credentials.plan

        // 2. Parallel API fetches (same burst as before).
        do {
            let teamId = await teamResolver.resolveTeamId(sessionToken: token, plan: plan)

            async let usageResp   = apiClient.fetchUsage(userId: credentials.userId, sessionToken: token)
            async let invoiceResp = apiClient.fetchMonthlyInvoice(
                month: Calendar.current.component(.month, from: Date()),
                year:  Calendar.current.component(.year,  from: Date()),
                sessionToken: token,
                teamId: teamId,
                includeEvents: true
            )
            async let hardLimitResp     = apiClient.fetchHardLimit(sessionToken: token, teamId: teamId)
            async let usageBasedEnabled = apiClient.fetchUsageBasedEnabled(sessionToken: token, teamId: teamId)
            async let meResp            = apiClient.fetchMe(sessionToken: token)

            let (usageData, invoice, hardLimit, ubEnabled, me) =
                try await (usageResp, invoiceResp, hardLimitResp, usageBasedEnabled, meResp)

            // 3. Billing cycle start
            let billingStart: Date
            if let startStr = usageData.startOfMonth {
                billingStart = ISO8601DateFormatter().date(from: startStr) ?? Date.startOfCurrentBillingMonth()
            } else {
                billingStart = Date.startOfCurrentBillingMonth()
            }

            // 4. UsageData (kept for on-demand card, export, and reset notifications)
            let details = UsageData(
                used: usageData.totalUsed,
                total: usageData.maxRequestUsage ?? 500,  // safe fallback; always prefer API value
                onDemandSpendUSD: invoice.totalUSD,
                hardLimitUSD: hardLimit.hardLimit,
                usageBasedEnabled: ubEnabled,
                billingCycleStart: billingStart,
                plan: plan
            )

            // 5. Recent events (view trims to the user's configured count)
            let events: [UsageEvent] = (invoice.usageEvents ?? [])
                .enumerated()
                .compactMap { UsageEvent.from($0.element, index: $0.offset) }
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(20)
                .map { $0 }

            // Model breakdown from /api/usage. Cursor buckets all quota requests under
            // "gpt-4" regardless of actual model — a single entry is just the aggregate
            // counter, so only expose the breakdown when multiple distinct models exist.
            let rawBreakdown = (usageData.models ?? [:])
                .compactMapValues { $0.numRequests }
                .filter { $0.value > 0 }
            let breakdown = rawBreakdown.count > 1 ? rawBreakdown : [:]

            // 6. Common snapshot shape
            let monthlyWindow = RateWindow(
                usedPercent: details.fraction * 100,
                windowMinutes: nil,   // calendar month; reset date carries the info
                resetsAt: Date.nextBillingReset(from: billingStart)
            )

            var accountLabel = credentials.email
            if let email = me.email, !email.isEmpty { accountLabel = email }

            var planLabel = "\(plan.displayName) Plan"
            if let team = me.teamName, !team.isEmpty { planLabel += " · \(team)" }

            return ProviderSnapshot(
                windows: [NamedRateWindow(id: "cursor-monthly", title: "Monthly Quota", window: monthlyWindow)],
                planLabel: planLabel,
                accountLabel: accountLabel,
                costUSD: details.onDemandSpendUSD > 0 ? details.onDemandSpendUSD : nil,
                costLabel: "on-demand this month",
                recentEvents: events,
                modelBreakdown: breakdown,
                cursorDetails: details
            )

        } catch CursorAPIClient.APIError.tokenInvalid {
            // Token in the DB went stale; Cursor itself refreshes it periodically, so keep
            // the last snapshot visible with an error badge — the next tick re-reads fresh.
            throw ProviderError.api("Session expired — retrying on next refresh")
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.api(error.localizedDescription)
        }
    }
}
