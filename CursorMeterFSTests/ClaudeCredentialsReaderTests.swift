import XCTest
@testable import CursorMeterFS

/// Covers the in-memory cache decision logic added to stop re-touching the
/// login Keychain on every refresh tick (see ClaudeCredentialsReader.swift).
/// Only the pure `isFresh` decision is tested here — the actual file/Keychain
/// read path is exercised manually (see README "Keychain sürekli soruyor" note).
final class ClaudeCredentialsReaderTests: XCTestCase {

    private func credentials(expiresAt: Date?) -> ClaudeCredentialsReader.ClaudeCredentials {
        ClaudeCredentialsReader.ClaudeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: expiresAt,
            subscriptionType: "pro",
            rateLimitTier: nil
        )
    }

    func test_isFresh_noExpiry_treatedAsFresh() {
        XCTAssertTrue(ClaudeCredentialsReader.isFresh(credentials(expiresAt: nil)))
    }

    func test_isFresh_farInFuture_isFresh() {
        let future = Date().addingTimeInterval(3600)
        XCTAssertTrue(ClaudeCredentialsReader.isFresh(credentials(expiresAt: future)))
    }

    func test_isFresh_alreadyExpired_isNotFresh() {
        let past = Date().addingTimeInterval(-60)
        XCTAssertFalse(ClaudeCredentialsReader.isFresh(credentials(expiresAt: past)))
    }

    func test_isFresh_withinSafetyMargin_isNotFresh() {
        // Expires in 10s — inside the 60s safety margin, should force a re-read
        // rather than serve a token that may expire mid-request.
        let soon = Date().addingTimeInterval(10)
        XCTAssertFalse(ClaudeCredentialsReader.isFresh(credentials(expiresAt: soon)))
    }

    func test_isFresh_justOutsideSafetyMargin_isFresh() {
        let justOutside = Date().addingTimeInterval(90)
        XCTAssertTrue(ClaudeCredentialsReader.isFresh(credentials(expiresAt: justOutside)))
    }

    // Note: read()/invalidate() round-tripping against the real file/Keychain is
    // intentionally NOT unit-tested here — this machine's real login Keychain
    // ("Claude Code-credentials") would be touched by an actual read(), which is
    // exactly the interactive-prompt risk this fix is meant to reduce. That path
    // is verified manually (see README "Keychain sürekli soruyor" section).
}
