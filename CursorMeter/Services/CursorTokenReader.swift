import Foundation
import SQLite3

// SQLITE_TRANSIENT is a C macro that Swift cannot import directly.
// It tells SQLite to copy the string before bind returns, safe for local variables.
private let _SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Reads Cursor authentication credentials from the local SQLite database
/// that Cursor itself maintains on the user's machine.
///
/// Security contract:
/// - The database is opened READ-ONLY (`SQLITE_OPEN_READONLY`).
/// - No data is written, no schema is modified.
/// - The token string is never written to disk or printed in logs.
/// - The caller (KeychainService) is responsible for secure storage.
final class CursorTokenReader {

    // MARK: - Errors
    enum TokenReaderError: Error, LocalizedError {
        case databaseNotFound(String)
        case databaseOpenFailed(String)
        case queryFailed(String)
        case tokenNotFound
        case jwtDecodingFailed(Error)
        case cursorNotLoggedIn

        var errorDescription: String? {
            switch self {
            case .databaseNotFound(let path):   return "state.vscdb not found at \(path). Is Cursor installed?"
            case .databaseOpenFailed(let msg):  return "Could not open state.vscdb (read-only): \(msg)"
            case .queryFailed(let msg):         return "SQLite query failed: \(msg)"
            case .tokenNotFound:                return "cursorAuth/accessToken not found. Please sign in to Cursor first."
            case .jwtDecodingFailed(let e):     return "JWT decoding failed: \(e.localizedDescription)"
            case .cursorNotLoggedIn:            return "No Cursor session found. Open Cursor and sign in, then try again."
            }
        }
    }

    // MARK: - Database path
    /// Path to Cursor's global state database on macOS.
    static var databasePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }

    // MARK: - Read result
    struct CursorCredentials {
        let sessionToken: String   // WorkosCursorSessionToken value (userId%3A%3AaccessToken)
        let userId: String
        let accessToken: String    // raw JWT — DO NOT LOG
        let refreshToken: String?  // raw JWT — DO NOT LOG
        let email: String?
        let plan: Plan
    }

    // MARK: - Main read method
    /// Opens state.vscdb read-only, reads auth keys, derives the session token.
    /// This is the only entry point — always call on a background queue.
    static func readCredentials() throws -> CursorCredentials {
        let path = databasePath
        guard FileManager.default.fileExists(atPath: path) else {
            throw TokenReaderError.databaseNotFound(path)
        }

        var db: OpaquePointer?
        // Open strictly read-only; `immutable=1` tells SQLite the file won't change
        // under us (safe while Cursor is running — we never write).
        let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(path, &db, openFlags, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw TokenReaderError.databaseOpenFailed(msg)
        }
        defer { sqlite3_close(db) }

        // Set a short busy timeout so we don't hang if Cursor is mid-write
        sqlite3_busy_timeout(db, 500)

        let keys: [String] = [
            "cursorAuth/accessToken",
            "cursorAuth/refreshToken",
            "cursorAuth/cachedEmail",
            "cursorAuth/stripeMembershipType",
            "cursorAuth/stripeSubscriptionStatus",
        ]

        var values: [String: String] = [:]
        for key in keys {
            if let value = try? queryValue(db: db, key: key), !value.isEmpty {
                values[key] = value
            }
        }

        guard let accessToken = values["cursorAuth/accessToken"], !accessToken.isEmpty else {
            throw TokenReaderError.cursorNotLoggedIn
        }

        // Decode JWT payload to extract userId from the `sub` claim.
        // sub format: "auth0|<userId>" or "workos|<userId>" — we take the part after "|".
        let sub: String
        do {
            sub = try JWTDecoder.subject(from: accessToken)
        } catch {
            throw TokenReaderError.jwtDecodingFailed(error)
        }

        // userId is the part after the last "|" pipe
        let userId: String
        if let pipeIdx = sub.lastIndex(of: "|") {
            userId = String(sub[sub.index(after: pipeIdx)...])
        } else {
            userId = sub
        }

        guard !userId.isEmpty else {
            throw TokenReaderError.jwtDecodingFailed(JWTDecoder.JWTError.missingSubClaim)
        }

        // Build WorkosCursorSessionToken: userId%3A%3A<accessToken>
        // %3A%3A is URL-encoded "::"
        let sessionToken = "\(userId)%3A%3A\(accessToken)"

        let plan = Plan.from(rawValue: values["cursorAuth/stripeMembershipType"])

        return CursorCredentials(
            sessionToken: sessionToken,
            userId: userId,
            accessToken: accessToken,     // stored in Keychain only
            refreshToken: values["cursorAuth/refreshToken"],
            email: values["cursorAuth/cachedEmail"],
            plan: plan
        )
    }

    // MARK: - SQLite helpers

    private static func queryValue(db: OpaquePointer, key: String) throws -> String? {
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        var stmt: OpaquePointer?

        let prepRc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepRc == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw TokenReaderError.queryFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, key, -1, _SQLITE_TRANSIENT)

        let stepRc = sqlite3_step(stmt)
        if stepRc == SQLITE_ROW {
            if let raw = sqlite3_column_text(stmt, 0) {
                return String(cString: raw)
            }
        } else if stepRc != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(db))
            throw TokenReaderError.queryFailed(msg)
        }
        return nil
    }

    // MARK: - Quick check (for UI: is Cursor logged in?)
    static func isCursorLoggedIn() -> Bool {
        (try? readCredentials()) != nil
    }
}
