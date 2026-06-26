import Foundation

/// Resolves the Cursor team ID for team/business plan users.
/// Results are cached for the session to avoid repeated API calls.
actor TeamResolver {

    private var cachedTeamId: Int?
    private var lastFetchDate: Date?
    private let cacheDuration: TimeInterval = 3600  // 1 hour

    /// Returns the teamId if the account is on a team/business plan, nil otherwise.
    /// Uses the hard-limit endpoint as a signal — team accounts pass a teamId.
    func resolveTeamId(sessionToken: String, plan: Plan) async -> Int? {
        // Only team/business plans have a teamId
        guard plan == .team || plan == .business else { return nil }

        // Return cached value if fresh
        if let cached = cachedTeamId,
           let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < cacheDuration {
            return cached
        }

        // Fetch from the dashboard settings endpoint
        let teamId = await fetchTeamId(sessionToken: sessionToken)
        cachedTeamId = teamId
        lastFetchDate = Date()
        return teamId
    }

    func invalidateCache() {
        cachedTeamId = nil
        lastFetchDate = nil
    }

    // MARK: - Private

    private func fetchTeamId(sessionToken: String) async -> Int? {
        guard let url = URL(string: "https://cursor.com/api/auth/full_stripe_profile") else {
            return nil
        }

        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "GET"
        req.setValue("WorkosCursorSessionToken=\(sessionToken)", forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        struct StripeProfile: Decodable {
            let teamId: Int?
            let membershipType: String?
        }

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let profile = try? JSONDecoder().decode(StripeProfile.self, from: data) else {
            return nil
        }

        return profile.teamId
    }
}
