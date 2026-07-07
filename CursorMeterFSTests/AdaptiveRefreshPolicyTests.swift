import XCTest
@testable import CursorMeterFS

final class AdaptiveRefreshPolicyTests: XCTestCase {

    private let policy = AdaptiveRefreshPolicy()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func input(
        ageSeconds: TimeInterval?,
        lowPowerMode: Bool = false,
        thermalState: ProcessInfo.ThermalState = .nominal
    ) -> AdaptiveRefreshPolicy.Input {
        let lastOpen = ageSeconds.map { now.addingTimeInterval(-$0) }
        return AdaptiveRefreshPolicy.Input(
            now: now,
            lastPopoverOpenAt: lastOpen,
            lowPowerModeEnabled: lowPowerMode,
            thermalState: thermalState
        )
    }

    // MARK: - Interaction-based cadence

    func test_recentInteraction_atThreshold() {
        let decision = policy.nextDelay(for: input(ageSeconds: 5 * 60))
        XCTAssertEqual(decision.reason, .recentInteraction)
        XCTAssertEqual(decision.delay, 2 * 60)
    }

    func test_recentInteraction_justOpened() {
        let decision = policy.nextDelay(for: input(ageSeconds: 0))
        XCTAssertEqual(decision.reason, .recentInteraction)
    }

    func test_warm_justAboveRecentThreshold() {
        let decision = policy.nextDelay(for: input(ageSeconds: 5 * 60 + 1))
        XCTAssertEqual(decision.reason, .warm)
        XCTAssertEqual(decision.delay, 5 * 60)
    }

    func test_warm_atThreshold() {
        let decision = policy.nextDelay(for: input(ageSeconds: 60 * 60))
        XCTAssertEqual(decision.reason, .warm)
    }

    func test_idle_justAboveWarmThreshold() {
        let decision = policy.nextDelay(for: input(ageSeconds: 60 * 60 + 1))
        XCTAssertEqual(decision.reason, .idle)
        XCTAssertEqual(decision.delay, 15 * 60)
    }

    func test_longIdle_atFourHours() {
        let decision = policy.nextDelay(for: input(ageSeconds: 4 * 60 * 60))
        XCTAssertEqual(decision.reason, .longIdle)
        XCTAssertEqual(decision.delay, 30 * 60)
    }

    func test_longIdle_neverOpened() {
        let decision = policy.nextDelay(for: input(ageSeconds: nil))
        XCTAssertEqual(decision.reason, .longIdle)
        XCTAssertEqual(decision.delay, 30 * 60)
    }

    func test_futureTimestamp_readsAsRecent() {
        // A clock-adjusted or future timestamp yields a negative age.
        let decision = policy.nextDelay(for: input(ageSeconds: -60))
        XCTAssertEqual(decision.reason, .recentInteraction)
    }

    // MARK: - Constrained overrides (win regardless of interaction recency)

    func test_lowPowerMode_overridesRecentInteraction() {
        let decision = policy.nextDelay(for: input(ageSeconds: 0, lowPowerMode: true))
        XCTAssertEqual(decision.reason, .constrained)
        XCTAssertEqual(decision.delay, 30 * 60)
    }

    func test_seriousThermalState_overridesRecentInteraction() {
        let decision = policy.nextDelay(for: input(ageSeconds: 0, thermalState: .serious))
        XCTAssertEqual(decision.reason, .constrained)
    }

    func test_criticalThermalState_overridesRecentInteraction() {
        let decision = policy.nextDelay(for: input(ageSeconds: 0, thermalState: .critical))
        XCTAssertEqual(decision.reason, .constrained)
    }

    func test_fairThermalState_doesNotConstrain() {
        let decision = policy.nextDelay(for: input(ageSeconds: 0, thermalState: .fair))
        XCTAssertEqual(decision.reason, .recentInteraction)
    }

    func test_nominalThermalState_doesNotConstrain() {
        let decision = policy.nextDelay(for: input(ageSeconds: 0, thermalState: .nominal))
        XCTAssertEqual(decision.reason, .recentInteraction)
    }
}

final class RefreshFrequencyTests: XCTestCase {

    func test_secondsMapping() {
        XCTAssertNil(RefreshFrequency.manual.seconds)
        XCTAssertEqual(RefreshFrequency.oneMinute.seconds, 60)
        XCTAssertEqual(RefreshFrequency.twoMinutes.seconds, 120)
        XCTAssertEqual(RefreshFrequency.fiveMinutes.seconds, 300)
        XCTAssertEqual(RefreshFrequency.fifteenMinutes.seconds, 900)
        XCTAssertEqual(RefreshFrequency.thirtyMinutes.seconds, 1_800)
        XCTAssertNil(RefreshFrequency.adaptive.seconds)
    }

    func test_closestFixed_exactMatches() {
        XCTAssertEqual(RefreshFrequency.closestFixed(toMinutes: 1), .oneMinute)
        XCTAssertEqual(RefreshFrequency.closestFixed(toMinutes: 5), .fiveMinutes)
        XCTAssertEqual(RefreshFrequency.closestFixed(toMinutes: 30), .thirtyMinutes)
    }

    func test_closestFixed_roundsToNearest() {
        XCTAssertEqual(RefreshFrequency.closestFixed(toMinutes: 10), .fiveMinutes)
        XCTAssertEqual(RefreshFrequency.closestFixed(toMinutes: 20), .fifteenMinutes)
    }
}
