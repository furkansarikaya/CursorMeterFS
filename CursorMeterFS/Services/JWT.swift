import Foundation

/// Minimal JWT payload decoder — reads only the `sub` claim.
/// We do NOT validate the signature; the token already lives on-device
/// inside the user's own Cursor data directory (trusted local source).
enum JWTDecoder {

    enum JWTError: Error, LocalizedError {
        case invalidFormat
        case base64DecodingFailed
        case jsonDecodingFailed(Error)
        case missingSubClaim

        var errorDescription: String? {
            switch self {
            case .invalidFormat:            return "Token has fewer than 3 dot-separated segments."
            case .base64DecodingFailed:     return "Could not base64url-decode the JWT payload."
            case .jsonDecodingFailed(let e): return "JSON decoding failed: \(e.localizedDescription)"
            case .missingSubClaim:          return "JWT payload does not contain a 'sub' claim."
            }
        }
    }

    private struct Payload: Decodable {
        let sub: String?
        // additional claims we might want later
        let email: String?
        let exp: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case sub, email, exp
        }
    }

    /// Decodes the JWT payload (second segment) and extracts the `sub` claim.
    static func subject(from jwt: String) throws -> String {
        let payload = try decodePayload(from: jwt)
        guard let sub = payload.sub, !sub.isEmpty else { throw JWTError.missingSubClaim }
        return sub
    }

    /// Decodes the JWT payload and returns the `email` claim, if present.
    /// Used for display only — the value is never logged or exported.
    static func email(from jwt: String) -> String? {
        guard let payload = try? decodePayload(from: jwt),
              let email = payload.email, !email.isEmpty else { return nil }
        return email
    }

    private static func decodePayload(from jwt: String) throws -> Payload {
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { throw JWTError.invalidFormat }

        let payloadSegment = String(segments[1])

        // base64url → base64: replace URL-safe chars, add padding
        var base64 = payloadSegment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }

        guard let data = Data(base64Encoded: base64) else { throw JWTError.base64DecodingFailed }

        do {
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw JWTError.jsonDecodingFailed(error)
        }
    }

    /// Checks whether the JWT is expired (if `exp` claim is present).
    /// Returns `true` (i.e. "assume valid") when no `exp` claim exists.
    static func isExpired(_ jwt: String) -> Bool {
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return true }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = base64.count % 4
        if rem != 0 { base64 += String(repeating: "=", count: 4 - rem) }
        guard let data = Data(base64Encoded: base64),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = dict["exp"] as? TimeInterval else {
            return false  // no exp → assume valid
        }
        return Date(timeIntervalSince1970: exp) < Date()
    }
}
