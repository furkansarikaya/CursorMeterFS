import XCTest
@testable import CursorMeterFS

// MARK: - RateWindow

final class RateWindowTests: XCTestCase {

    func test_fraction_clampsOutOfRange() {
        XCTAssertEqual(RateWindow(usedPercent: 150, windowMinutes: nil, resetsAt: nil).fraction, 1.0)
        XCTAssertEqual(RateWindow(usedPercent: -5, windowMinutes: nil, resetsAt: nil).fraction, 0.0)
        XCTAssertEqual(RateWindow(usedPercent: 42, windowMinutes: nil, resetsAt: nil).percentInt, 42)
    }

    func test_remainingPercent() {
        XCTAssertEqual(RateWindow(usedPercent: 30, windowMinutes: nil, resetsAt: nil).remainingPercent, 70)
        XCTAssertEqual(RateWindow(usedPercent: 120, windowMinutes: nil, resetsAt: nil).remainingPercent, 0)
    }

    func test_resetDescription_formats() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func window(_ seconds: TimeInterval) -> RateWindow {
            RateWindow(usedPercent: 0, windowMinutes: nil, resetsAt: now.addingTimeInterval(seconds))
        }
        XCTAssertEqual(window(42 * 60).resetDescription(now: now), "42m")
        XCTAssertEqual(window(3 * 3_600 + 53 * 60).resetDescription(now: now), "3h 53m")
        XCTAssertEqual(window(3 * 86_400 + 20 * 3_600).resetDescription(now: now), "3d 20h")
        XCTAssertEqual(window(-60).resetDescription(now: now), "now")
        XCTAssertNil(RateWindow(usedPercent: 0, windowMinutes: nil, resetsAt: nil).resetDescription(now: now))
    }
}

// MARK: - UsagePace

final class UsagePaceTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Window: 7 days; half elapsed (resets in 3.5 days).
    private func weeklyWindow(usedPercent: Double) -> RateWindow {
        RateWindow(
            usedPercent: usedPercent,
            windowMinutes: 7 * 24 * 60,
            resetsAt: now.addingTimeInterval(3.5 * 86_400)
        )
    }

    func test_behind_whenUsingSlowerThanLinear() {
        let pace = UsagePace.compute(window: weeklyWindow(usedPercent: 8), now: now)
        XCTAssertEqual(pace?.stage, .behind)           // expected 50%, actual 8% → −42
        XCTAssertEqual(pace!.deltaPercent, -42, accuracy: 0.5)
        XCTAssertTrue(pace!.willLastToReset)
    }

    func test_ahead_whenBurningTooFast() {
        let pace = UsagePace.compute(window: weeklyWindow(usedPercent: 80), now: now)
        XCTAssertEqual(pace?.stage, .ahead)            // expected 50%, actual 80% → +30
        XCTAssertFalse(pace!.willLastToReset)          // projects to 160% at reset
    }

    func test_onTrack_withinTolerance() {
        let pace = UsagePace.compute(window: weeklyWindow(usedPercent: 55), now: now)
        XCTAssertEqual(pace?.stage, .onTrack)
        XCTAssertFalse(pace!.willLastToReset)          // 110% projected
    }

    func test_nil_whenWindowGeometryMissing() {
        XCTAssertNil(UsagePace.compute(
            window: RateWindow(usedPercent: 50, windowMinutes: nil, resetsAt: now), now: now))
        XCTAssertNil(UsagePace.compute(
            window: RateWindow(usedPercent: 50, windowMinutes: 300, resetsAt: nil), now: now))
    }

    func test_nil_whenWindowTooYoung() {
        // Window just started: only 1% elapsed — no meaningful signal yet.
        let window = RateWindow(
            usedPercent: 1,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(297 * 60)
        )
        XCTAssertNil(UsagePace.compute(window: window, now: now))
    }
}

// MARK: - Codex API response decoding

final class CodexUsageResponseTests: XCTestCase {

    func test_decode_fullResponse() throws {
        let json = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window":   {"used_percent": 2,  "reset_at": 1774362997, "limit_window_seconds": 18000},
            "secondary_window": {"used_percent": 1.5, "reset_at": 1774949797, "limit_window_seconds": 604800}
          },
          "additional_rate_limits": [
            {"limit_name": "GPT-5.3-Codex-Spark",
             "rate_limit": {"primary_window": {"used_percent": 0, "reset_at": 1774949797, "limit_window_seconds": 604800}}}
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CodexAPIClient.UsageResponse.self, from: json)
        XCTAssertEqual(response.planType, "plus")
        XCTAssertEqual(response.rateLimit?.primaryWindow?.usedPercent, 2)
        XCTAssertEqual(response.rateLimit?.primaryWindow?.limitWindowSeconds, 18_000)
        XCTAssertEqual(response.rateLimit?.secondaryWindow?.usedPercent, 1.5)
        XCTAssertEqual(response.additionalRateLimits?.count, 1)
        XCTAssertEqual(response.additionalRateLimits?.first?.limitName, "GPT-5.3-Codex-Spark")
    }

    func test_decode_survivesMissingAndMalformedFields() throws {
        let json = """
        {"rate_limit": {"primary_window": {"used_percent": 7}},
         "additional_rate_limits": [{"limit_name": 42}, {"limit_name": "OK",
           "rate_limit": {"primary_window": {"used_percent": 3}}}]}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CodexAPIClient.UsageResponse.self, from: json)
        XCTAssertNil(response.planType)
        XCTAssertEqual(response.rateLimit?.primaryWindow?.usedPercent, 7)
        XCTAssertNil(response.rateLimit?.primaryWindow?.resetAt)
        // Malformed sibling must not discard the valid one.
        let names = response.additionalRateLimits?.compactMap(\.limitName)
        XCTAssertEqual(names, ["OK"])
    }
}

// MARK: - Claude API response decoding + dynamic model lanes

final class ClaudeUsageResponseTests: XCTestCase {

    func test_decode_flatWindows() throws {
        let json = """
        {"five_hour": {"utilization": 2, "resets_at": "2026-07-08T21:00:00Z"},
         "seven_day": {"utilization": 3, "resets_at": "2026-07-11T13:00:00.000Z"}}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ClaudeAPIClient.UsageResponse.self, from: json)
        XCTAssertEqual(response.fiveHour?.utilization, 2)
        XCTAssertEqual(response.sevenDay?.utilization, 3)
        XCTAssertNotNil(ClaudeProviderClient.parseISO8601(response.fiveHour!.resetsAt!))
        XCTAssertNotNil(ClaudeProviderClient.parseISO8601(response.sevenDay!.resetsAt!))
    }

    func test_dynamicScopedLanes_renderWhatAPIReturns() throws {
        // Max-style account: a Sonnet-scoped weekly lane plus a promotional model (Fable).
        let json = """
        {"seven_day": {"utilization": 3, "resets_at": "2026-07-11T13:00:00Z"},
         "limits": [
           {"kind": "weekly_scoped", "group": "weekly", "percent": 0,
            "resets_at": "2026-07-11T13:00:00Z",
            "scope": {"model": {"id": "sonnet", "display_name": "Sonnet"}}},
           {"kind": "weekly_scoped", "group": "weekly", "percent": 12,
            "scope": {"model": {"display_name": "Fable"}}},
           {"kind": "session", "group": "five_hour", "percent": 4},
           {"kind": "weekly_scoped", "group": "weekly", "percent": 9, "is_active": false,
            "scope": {"model": {"display_name": "Retired"}}}
         ]}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ClaudeAPIClient.UsageResponse.self, from: json)
        let lanes = ClaudeProviderClient.modelScopedLanes(from: response.limits)

        // Only active weekly_scoped entries with a model name become lanes — nothing hardcoded.
        XCTAssertEqual(lanes.map(\.title), ["Sonnet only", "Fable only"])
        XCTAssertEqual(lanes[0].window.usedPercent, 0)
        XCTAssertEqual(lanes[1].window.usedPercent, 12)
        XCTAssertEqual(lanes[0].id, "claude-weekly-scoped-sonnet")
    }

    func test_scopedLanes_emptyForProStyleResponse() throws {
        // Pro account: no scoped limits — no model lanes appear.
        let json = """
        {"five_hour": {"utilization": 10}, "seven_day": {"utilization": 20}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaudeAPIClient.UsageResponse.self, from: json)
        XCTAssertTrue(ClaudeProviderClient.modelScopedLanes(from: response.limits).isEmpty)
    }
}

// MARK: - Cost pricing

final class CostPricingTests: XCTestCase {

    func test_longestPrefixWins() {
        // "gpt-5.1-codex-mini-2026" must match the mini entry, not "gpt-5.1" or "gpt-5".
        let mini = CostPricing.pricing(forModel: "gpt-5.1-codex-mini-2026", in: CostPricing.codex)
        XCTAssertEqual(mini?.input, 2.5e-7)
        let base = CostPricing.pricing(forModel: "gpt-5", in: CostPricing.codex)
        XCTAssertEqual(base?.input, 1.25e-6)
        XCTAssertNil(CostPricing.pricing(forModel: "unknown-model", in: CostPricing.codex))
    }

    func test_codexCost_cachedInputIsSubset() {
        // 1M input of which 600k cached, 100k output on gpt-5.1:
        // 400k×1.25e-6 + 600k×1.25e-7 + 100k×1e-5 = 0.5 + 0.075 + 1.0
        let cost = CostPricing.codexCost(
            model: "gpt-5.1", inputTokens: 1_000_000, cachedInputTokens: 600_000, outputTokens: 100_000)
        XCTAssertEqual(cost!, 1.575, accuracy: 0.0001)
    }

    func test_claudeCost_allBuckets() {
        // opus-4-8: 100k×5e-6 + 50k×2.5e-5 + 200k×6.25e-6 + 1M×5e-7 = 0.5+1.25+1.25+0.5
        let cost = CostPricing.claudeCost(
            model: "claude-opus-4-8-20260115",
            inputTokens: 100_000, outputTokens: 50_000,
            cacheCreationTokens: 200_000, cacheReadTokens: 1_000_000)
        XCTAssertEqual(cost!, 3.5, accuracy: 0.0001)
    }
}
