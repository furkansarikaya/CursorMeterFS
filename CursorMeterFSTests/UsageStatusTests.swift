import XCTest
@testable import CursorMeterFS

final class UsageStatusTests: XCTestCase {

    // MARK: - UsageStatus.from(fraction:)

    func test_safe_belowWarning() {
        let status = UsageStatus.from(fraction: 0.50)
        XCTAssertEqual(status, .safe)
    }

    func test_safe_atZero() {
        XCTAssertEqual(UsageStatus.from(fraction: 0.0), .safe)
    }

    func test_warning_atWarningThreshold() {
        XCTAssertEqual(UsageStatus.from(fraction: 0.70), .warning)
    }

    func test_warning_betweenThresholds() {
        XCTAssertEqual(UsageStatus.from(fraction: 0.80), .warning)
    }

    func test_critical_atCriticalThreshold() {
        XCTAssertEqual(UsageStatus.from(fraction: 0.90), .critical)
    }

    func test_critical_above() {
        XCTAssertEqual(UsageStatus.from(fraction: 1.0), .critical)
    }

    func test_critical_over100percent() {
        XCTAssertEqual(UsageStatus.from(fraction: 1.5), .critical)
    }

    func test_customThresholds() {
        XCTAssertEqual(UsageStatus.from(fraction: 0.60, warningThreshold: 0.60, criticalThreshold: 0.80), .warning)
        XCTAssertEqual(UsageStatus.from(fraction: 0.79, warningThreshold: 0.60, criticalThreshold: 0.80), .warning)
        XCTAssertEqual(UsageStatus.from(fraction: 0.80, warningThreshold: 0.60, criticalThreshold: 0.80), .critical)
    }

    // MARK: - UsageData.fraction

    func test_fraction_normal() {
        let data = UsageData(used: 500, total: 1000, onDemandSpendUSD: 0, hardLimitUSD: nil,
                             usageBasedEnabled: false, billingCycleStart: Date(), plan: .pro)
        XCTAssertEqual(data.fraction, 0.5, accuracy: 0.001)
    }

    func test_fraction_zeroTotal_doesNotCrash() {
        let data = UsageData(used: 0, total: 0, onDemandSpendUSD: 0, hardLimitUSD: nil,
                             usageBasedEnabled: false, billingCycleStart: Date(), plan: .pro)
        XCTAssertEqual(data.fraction, 0)
    }

    func test_fraction_clampedAt1() {
        let data = UsageData(used: 1500, total: 1000, onDemandSpendUSD: 0, hardLimitUSD: nil,
                             usageBasedEnabled: false, billingCycleStart: Date(), plan: .pro)
        XCTAssertEqual(data.fraction, 1.0)
    }

    func test_percentageInt() {
        let data = UsageData(used: 420, total: 1000, onDemandSpendUSD: 0, hardLimitUSD: nil,
                             usageBasedEnabled: false, billingCycleStart: Date(), plan: .pro)
        XCTAssertEqual(data.percentageInt, 42)
    }

    func test_remainingRequests() {
        let data = UsageData(used: 420, total: 1000, onDemandSpendUSD: 0, hardLimitUSD: nil,
                             usageBasedEnabled: false, billingCycleStart: Date(), plan: .pro)
        XCTAssertEqual(data.remainingRequests, 580)
    }

    // MARK: - Plan.from(rawValue:)

    func test_plan_parsesPro() {
        XCTAssertEqual(Plan.from(rawValue: "pro"), .pro)
    }

    func test_plan_parsesUltra() {
        XCTAssertEqual(Plan.from(rawValue: "ultra"), .ultra)
    }

    func test_plan_parsesProPlus() {
        XCTAssertEqual(Plan.from(rawValue: "pro_plus"), .proPlus)
    }

    func test_plan_unknownFallsBackToPro() {
        XCTAssertEqual(Plan.from(rawValue: "enterprise_x"), .pro)
    }

    func test_plan_nilFallsBackToFree() {
        XCTAssertEqual(Plan.from(rawValue: nil), .free)
    }

    func test_plan_caseInsensitive() {
        XCTAssertEqual(Plan.from(rawValue: "ULTRA"), .ultra)
        XCTAssertEqual(Plan.from(rawValue: "Pro"), .pro)
    }

    // MARK: - Date helpers

    func test_relativeDescription_future() {
        // Use the same `now` for both to avoid ms drift between two Date() calls
        let now = Date()
        let future = now.addingTimeInterval(3 * 86400)
        let desc = future.relativeDescription(from: now)
        XCTAssertTrue(desc.contains("3") && desc.contains("day"), "Expected '3 days', got: \(desc)")
    }

    func test_relativeDescription_tomorrow() {
        let now = Date()
        let tomorrow = now.addingTimeInterval(86400 + 60)
        let desc = tomorrow.relativeDescription(from: now)
        XCTAssertEqual(desc, "tomorrow")
    }

    func test_relativeDescription_hours() {
        let now = Date()
        let later = now.addingTimeInterval(3 * 3600)
        let desc = later.relativeDescription(from: now)
        XCTAssertTrue(desc.contains("3") && desc.contains("hour"), "Expected '3 hours', got: \(desc)")
    }

    func test_relativeDescription_past_returnsNow() {
        let now = Date()
        let past = now.addingTimeInterval(-100)
        XCTAssertEqual(past.relativeDescription(from: now), "now")
    }
}
