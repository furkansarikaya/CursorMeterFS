import Foundation

/// Offline fallback for Codex quota: the Codex CLI writes a `token_count` event with the
/// server-reported `rate_limits` into every session log. Reading the newest session file
/// gives Session/Weekly percentages, reset instants, and plan tier with ZERO network —
/// pure user-home file reads (verified structure on-disk).
enum CodexSessionLogReader {

    struct LoggedWindow {
        let usedPercent: Double
        let windowMinutes: Int?
        let resetsAt: Date?
    }

    struct LoggedRateLimits {
        let primary: LoggedWindow?
        let secondary: LoggedWindow?
        let planType: String?
        let loggedAt: Date?     // file mtime — staleness indicator
    }

    /// Returns the most recent `rate_limits` found in `$CODEX_HOME/sessions/**/*.jsonl`.
    static func latestRateLimits() -> LoggedRateLimits? {
        guard let newest = newestSessionFile() else { return nil }
        guard let payload = lastTokenCountPayload(in: newest.url) else { return nil }
        guard let rateLimits = payload["rate_limits"] as? [String: Any] else { return nil }

        return LoggedRateLimits(
            primary: parseWindow(rateLimits["primary"]),
            secondary: parseWindow(rateLimits["secondary"]),
            planType: rateLimits["plan_type"] as? String,
            loggedAt: newest.mtime
        )
    }

    // MARK: - Private

    private static func newestSessionFile() -> (url: URL, mtime: Date)? {
        let root = CodexAuthReader.sessionsDirURL
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (url: URL, mtime: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let mtime = values.contentModificationDate else { continue }
            if newest == nil || mtime > newest!.mtime {
                newest = (url, mtime)
            }
        }
        return newest
    }

    /// Scans the tail of the file backwards for the last `token_count` event payload.
    private static func lastTokenCountPayload(in url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        // Only the tail matters — rate limits arrive with every turn.
        let tail = data.suffix(512 * 1024)
        guard let text = String(data: tail, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n").reversed() {
            guard line.contains("token_count"), line.contains("rate_limits") else { continue }
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = json["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count" else { continue }
            return payload
        }
        return nil
    }

    private static func parseWindow(_ value: Any?) -> LoggedWindow? {
        guard let dict = value as? [String: Any] else { return nil }
        guard let used = asDouble(dict["used_percent"]) else { return nil }

        var resetsAt: Date?
        if let epoch = asDouble(dict["resets_at"]) {
            resetsAt = Date(timeIntervalSince1970: epoch)
        }
        var windowMinutes: Int?
        if let minutes = asDouble(dict["window_minutes"]) {
            windowMinutes = Int(minutes)
        }
        return LoggedWindow(usedPercent: used, windowMinutes: windowMinutes, resetsAt: resetsAt)
    }

    private static func asDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
}
