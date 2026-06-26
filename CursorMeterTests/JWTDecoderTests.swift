import XCTest
@testable import CursorMeter

final class JWTDecoderTests: XCTestCase {

    // A fake (unsigned) JWT with a known sub claim for testing.
    // header.payload.signature — only the payload segment matters.
    // payload = {"sub":"auth0|abc123user","email":"test@example.com","exp":9999999999}
    private let fakeJWT: String = {
        let header  = #"{"alg":"RS256","typ":"JWT"}"#.base64URLEncoded()
        let payload = #"{"sub":"auth0|abc123user","email":"test@example.com","exp":9999999999}"#.base64URLEncoded()
        return "\(header).\(payload).fakesig"
    }()

    // MARK: - subject(from:)

    func test_subject_returnsSubClaim() throws {
        let sub = try JWTDecoder.subject(from: fakeJWT)
        XCTAssertEqual(sub, "auth0|abc123user")
    }

    func test_subject_invalidFormat_throwsError() {
        XCTAssertThrowsError(try JWTDecoder.subject(from: "notavalidjwt")) { error in
            guard case JWTDecoder.JWTError.invalidFormat = error else {
                return XCTFail("Expected invalidFormat, got \(error)")
            }
        }
    }

    func test_subject_missingSubClaim_throwsError() throws {
        let payload = #"{"email":"test@example.com"}"#.base64URLEncoded()
        let jwt = "header.\(payload).sig"
        XCTAssertThrowsError(try JWTDecoder.subject(from: jwt)) { error in
            guard case JWTDecoder.JWTError.missingSubClaim = error else {
                return XCTFail("Expected missingSubClaim, got \(error)")
            }
        }
    }

    func test_subject_base64PaddingVariants() throws {
        // Payloads of different lengths trigger different padding requirements
        for extra in ["", "x", "xx", "xxx"] {
            let raw = #"{"sub":"auth0|user\#(extra)","exp":9999999999}"#
            let payload = raw.base64URLEncoded()
            let jwt = "h.\(payload).s"
            let sub = try JWTDecoder.subject(from: jwt)
            XCTAssertTrue(sub.contains("user"), "sub should contain 'user', got: \(sub)")
        }
    }

    // MARK: - isExpired

    func test_isExpired_futureExp_returnsFalse() {
        XCTAssertFalse(JWTDecoder.isExpired(fakeJWT))
    }

    func test_isExpired_pastExp_returnsTrue() {
        let payload = #"{"sub":"auth0|x","exp":1}"#.base64URLEncoded()
        let jwt = "h.\(payload).s"
        XCTAssertTrue(JWTDecoder.isExpired(jwt))
    }

    func test_isExpired_noExpClaim_returnsFalse() {
        let payload = #"{"sub":"auth0|x"}"#.base64URLEncoded()
        let jwt = "h.\(payload).s"
        XCTAssertFalse(JWTDecoder.isExpired(jwt))
    }

    // MARK: - userId extraction (the derived session token logic)

    func test_userId_extractedAfterPipe() throws {
        let sub = try JWTDecoder.subject(from: fakeJWT)
        // sub = "auth0|abc123user" — userId is the part after "|"
        let userId: String
        if let pipeIdx = sub.lastIndex(of: "|") {
            userId = String(sub[sub.index(after: pipeIdx)...])
        } else {
            userId = sub
        }
        XCTAssertEqual(userId, "abc123user")
    }

    func test_sessionToken_format() throws {
        let sub = try JWTDecoder.subject(from: fakeJWT)
        guard let pipeIdx = sub.lastIndex(of: "|") else {
            return XCTFail("Expected pipe in sub")
        }
        let userId = String(sub[sub.index(after: pipeIdx)...])
        let accessToken = "some.fake.accesstoken"
        let sessionToken = "\(userId)%3A%3A\(accessToken)"

        XCTAssertTrue(sessionToken.hasPrefix("abc123user%3A%3A"))
        XCTAssertTrue(sessionToken.hasSuffix(accessToken))
        // %3A%3A must appear exactly once
        XCTAssertEqual(sessionToken.components(separatedBy: "%3A%3A").count, 2)
    }
}

// MARK: - Helpers
private extension String {
    func base64URLEncoded() -> String {
        Data(utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
