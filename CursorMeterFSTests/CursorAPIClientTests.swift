import XCTest
@testable import CursorMeterFS

/// Tests the API response parsing layer with mock JSON payloads.
/// No real network calls are made.
final class CursorAPIClientTests: XCTestCase {

    // MARK: - UsageAPIResponse parsing

    func test_usageAPIResponse_parsesNumRequests() throws {
        let json = """
        {
            "claude-opus-4-8": {
                "numRequests": 420,
                "maxRequestUsage": 1000,
                "startOfMonth": "2026-06-01T00:00:00.000Z"
            },
            "claude-sonnet-4-6": {
                "numRequests": 0,
                "maxRequestUsage": 1000
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageAPIResponse.self, from: json)
        XCTAssertEqual(response.totalUsed, 420)
        XCTAssertEqual(response.maxRequestUsage, 1000)
        XCTAssertNotNil(response.startOfMonth)
    }

    func test_usageAPIResponse_aggregatesMultipleModels() throws {
        let json = """
        {
            "model-a": {"numRequests": 300, "maxRequestUsage": 1000},
            "model-b": {"numRequests": 120, "maxRequestUsage": 1000}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageAPIResponse.self, from: json)
        XCTAssertEqual(response.totalUsed, 420)
    }

    func test_usageAPIResponse_dynamicMaxRequestUsage() throws {
        // Quota can change — always take the API value, never hardcode
        let json = """
        {
            "claude-opus-4-8": {
                "numRequests": 100,
                "maxRequestUsage": 2000
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageAPIResponse.self, from: json)
        XCTAssertEqual(response.maxRequestUsage, 2000,
                       "maxRequestUsage must come from API, not hardcoded — supports dynamic quotas")
    }

    func test_usageAPIResponse_missingFields_doesNotCrash() throws {
        // API may evolve — all fields are optional
        let json = """
        {
            "some-model": {}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageAPIResponse.self, from: json)
        XCTAssertEqual(response.totalUsed, 0)
        XCTAssertNil(response.maxRequestUsage)
    }

    func test_usageAPIResponse_emptyDict_doesNotCrash() throws {
        let json = "{}".data(using: .utf8)!
        let response = try JSONDecoder().decode(UsageAPIResponse.self, from: json)
        XCTAssertEqual(response.totalUsed, 0)
    }

    // MARK: - InvoiceResponse parsing

    func test_invoiceResponse_parsesTotalCents() throws {
        let json = """
        {
            "usageBasedCents": 1250,
            "items": [],
            "usageEvents": [
                {
                    "id": "evt1",
                    "model": "claude-opus-4-8",
                    "inputTokens": 1200,
                    "outputTokens": 450,
                    "totalCost": 0.0045,
                    "timestamp": "2026-06-15T10:30:00Z",
                    "kind": "agent"
                }
            ]
        }
        """.data(using: .utf8)!

        let invoice = try JSONDecoder().decode(InvoiceResponse.self, from: json)
        XCTAssertEqual(invoice.totalUSD, 12.50, accuracy: 0.001)
        XCTAssertEqual(invoice.usageEvents?.count, 1)
    }

    func test_invoiceResponse_parsesUsageItemsFallback() throws {
        // Cursor API has historically used "usageItems" — must decode correctly
        let json = """
        {
            "usageBasedCents": 500,
            "usageItems": [
                {
                    "id": "evt2",
                    "model": "gpt-4o",
                    "inputTokens": 800,
                    "outputTokens": 200,
                    "totalCost": 0.002,
                    "timestamp": "2026-06-15T11:00:00Z",
                    "kind": "chat"
                }
            ]
        }
        """.data(using: .utf8)!

        let invoice = try JSONDecoder().decode(InvoiceResponse.self, from: json)
        XCTAssertEqual(invoice.totalUSD, 5.0, accuracy: 0.001)
        XCTAssertEqual(invoice.usageEvents?.count, 1)
    }

    func test_invoiceResponse_missingEvents_doesNotCrash() throws {
        let json = #"{"usageBasedCents": 0}"#.data(using: .utf8)!
        let invoice = try JSONDecoder().decode(InvoiceResponse.self, from: json)
        XCTAssertEqual(invoice.totalUSD, 0)
        XCTAssertNil(invoice.usageEvents)
    }

    // MARK: - UsageEvent.from(_:index:)

    func test_usageEvent_fromRawItem_parsed() {
        let raw = UsageEvent.RawItem(
            id: "evt1",
            model: "claude-sonnet-4-6",
            inputTokens: 800,
            outputTokens: 200,
            totalCost: 0.002,
            cents: nil,
            timestamp: "2026-06-15T10:00:00Z",
            type: nil,
            kind: "chat"
        )
        let event = UsageEvent.from(raw, index: 0)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.totalTokens, 1000)
        XCTAssertEqual(event?.kind, .chat)
        XCTAssertEqual(event?.costUSD ?? 0, 0.002, accuracy: 0.0001)
    }

    func test_usageEvent_missingModel_returnsNil() {
        let raw = UsageEvent.RawItem(
            id: "evt1", model: nil,
            inputTokens: 100, outputTokens: 50,
            totalCost: 0.001, cents: nil,
            timestamp: nil, type: nil, kind: nil
        )
        XCTAssertNil(UsageEvent.from(raw, index: 0))
    }

    func test_usageEvent_centsConvertedToUSD() {
        let raw = UsageEvent.RawItem(
            id: "evt1", model: "gpt-4o",
            inputTokens: 0, outputTokens: 0,
            totalCost: nil, cents: 150,
            timestamp: nil, type: nil, kind: nil
        )
        let event = UsageEvent.from(raw, index: 0)
        XCTAssertEqual(event?.costUSD ?? 0, 1.50, accuracy: 0.001)
    }

    func test_usageEvent_displayModelName_knowsClaudeSonnet() {
        let raw = UsageEvent.RawItem(
            id: "1", model: "claude-sonnet-4-6",
            inputTokens: 0, outputTokens: 0,
            totalCost: 0, cents: nil,
            timestamp: nil, type: nil, kind: nil
        )
        let event = UsageEvent.from(raw, index: 0)
        XCTAssertEqual(event?.displayModelName, "Claude Sonnet 4")
    }

    // MARK: - HardLimitResponse parsing

    func test_hardLimitResponse_parsesLimit() throws {
        let json = #"{"hardLimit": 50.0, "hardLimitEnabled": true}"#.data(using: .utf8)!
        let resp = try JSONDecoder().decode(HardLimitResponse.self, from: json)
        XCTAssertEqual(resp.hardLimit, 50.0)
        XCTAssertTrue(resp.hardLimitEnabled ?? false)
    }

    func test_hardLimitResponse_missingFields_doesNotCrash() throws {
        let json = "{}".data(using: .utf8)!
        let resp = try JSONDecoder().decode(HardLimitResponse.self, from: json)
        XCTAssertNil(resp.hardLimit)
    }
}
