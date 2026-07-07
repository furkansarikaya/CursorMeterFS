import Foundation

/// Estimates local spend by scanning session logs (user-home only) and pricing token
/// counts with `CostPricing`. Per-file results are cached by modification time so
/// unchanged files are never re-parsed — repeat refreshes cost near-zero I/O.
actor CostScanner {

    static let shared = CostScanner()

    /// How far back the estimate reaches (by file modification time).
    static let lookbackDays = 30

    private struct CachedFileCost {
        let mtime: Date
        let cost: Double
    }

    private var codexCache: [String: CachedFileCost] = [:]
    private var claudeCache: [String: CachedFileCost] = [:]

    // MARK: - Codex

    /// Sums the final `total_token_usage` of each recent session file × model pricing.
    func codexCostUSD() -> Double? {
        let files = recentFiles(
            under: CodexAuthReader.sessionsDirURL,
            extension: "jsonl"
        )
        guard !files.isEmpty else { return nil }

        var total = 0.0
        var priced = false
        for (url, mtime) in files {
            if let cached = codexCache[url.path], cached.mtime == mtime {
                total += cached.cost
                priced = true
                continue
            }
            let cost = codexFileCost(url) ?? 0
            codexCache[url.path] = CachedFileCost(mtime: mtime, cost: cost)
            total += cost
            if cost > 0 { priced = true }
        }
        return priced ? total : nil
    }

    private func codexFileCost(_ url: URL) -> Double? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let text = String(data: data.suffix(512 * 1024), encoding: .utf8) else { return nil }

        // Last cumulative token_count carries the session's total usage.
        var usage: (input: Int, cached: Int, output: Int)?
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("token_count"), line.contains("total_token_usage") else { continue }
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = json["payload"] as? [String: Any],
                  let info = payload["info"] as? [String: Any],
                  let totals = info["total_token_usage"] as? [String: Any] else { continue }
            usage = (
                input: (totals["input_tokens"] as? Int) ?? 0,
                cached: (totals["cached_input_tokens"] as? Int) ?? 0,
                output: (totals["output_tokens"] as? Int) ?? 0
            )
            break
        }
        guard let usage else { return nil }

        // Best-effort model detection from the log tail; falls back to a current default.
        let model = detectModel(in: text) ?? "gpt-5.1"
        return CostPricing.codexCost(
            model: model,
            inputTokens: usage.input,
            cachedInputTokens: usage.cached,
            outputTokens: usage.output
        )
    }

    private func detectModel(in text: String) -> String? {
        // Match the last `"model":"gpt-…"` occurrence (turn_context carries it).
        guard let regex = try? NSRegularExpression(pattern: #""model"\s*:\s*"(gpt-[^"]+)""#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var last: String?
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            if let match, let r = Range(match.range(at: 1), in: text) {
                last = String(text[r])
            }
        }
        return last
    }

    // MARK: - Claude

    /// Sums per-message `usage` token counts across recent project logs × model pricing.
    /// Messages are deduplicated by message id (streaming can repeat them).
    func claudeCostUSD() -> Double? {
        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        let files = recentFiles(under: projectsDir, extension: "jsonl")
        guard !files.isEmpty else { return nil }

        var total = 0.0
        var priced = false
        for (url, mtime) in files {
            if let cached = claudeCache[url.path], cached.mtime == mtime {
                total += cached.cost
                priced = true
                continue
            }
            let cost = claudeFileCost(url) ?? 0
            claudeCache[url.path] = CachedFileCost(mtime: mtime, cost: cost)
            total += cost
            if cost > 0 { priced = true }
        }
        return priced ? total : nil
    }

    private func claudeFileCost(_ url: URL) -> Double? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let text = String(data: data, encoding: .utf8) else { return nil }

        var total = 0.0
        var seenMessageIds = Set<String>()

        for line in text.split(separator: "\n") {
            // Cheap pre-filter before JSON parsing.
            guard line.contains("\"assistant\""), line.contains("\"usage\"") else { continue }
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let model = message["model"] as? String,
                  !model.hasPrefix("<") else { continue }   // skip "<synthetic>"

            if let messageId = message["id"] as? String {
                guard seenMessageIds.insert(messageId).inserted else { continue }
            }

            let cost = CostPricing.claudeCost(
                model: model,
                inputTokens: (usage["input_tokens"] as? Int) ?? 0,
                outputTokens: (usage["output_tokens"] as? Int) ?? 0,
                cacheCreationTokens: (usage["cache_creation_input_tokens"] as? Int) ?? 0,
                cacheReadTokens: (usage["cache_read_input_tokens"] as? Int) ?? 0
            )
            total += cost ?? 0
        }
        return total
    }

    // MARK: - Shared helpers

    private func recentFiles(under root: URL, extension ext: String) -> [(url: URL, mtime: Date)] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = Date().addingTimeInterval(-TimeInterval(Self.lookbackDays) * 86_400)
        var result: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == ext {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let mtime = values.contentModificationDate,
                  mtime > cutoff else { continue }
            result.append((url, mtime))
        }
        return result
    }
}
