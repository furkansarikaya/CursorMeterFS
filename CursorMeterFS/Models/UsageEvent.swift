import Foundation

/// A single usage event from `get-monthly-invoice` with `includeUsageEvents: true`.
/// Represents one AI request made via Cursor.
struct UsageEvent: Identifiable, Equatable {
    let id: String           // unique identifier from the API or synthesised
    let model: String        // e.g. "claude-3-5-sonnet", "gpt-4o", "gemini-2.0-flash"
    let inputTokens: Int
    let outputTokens: Int
    let costUSD: Double
    let timestamp: Date
    let kind: RequestKind

    var totalTokens: Int { inputTokens + outputTokens }

    /// Friendly model name for display (trims vendor prefixes, version noise).
    var displayModelName: String {
        let known: [(prefix: String, name: String)] = [
            ("claude-opus-4",         "Claude Opus 4"),
            ("claude-sonnet-4",       "Claude Sonnet 4"),
            ("claude-haiku-4",        "Claude Haiku 4"),
            ("claude-3-5-sonnet",     "Claude Sonnet 3.5"),
            ("claude-3-5-haiku",      "Claude Haiku 3.5"),
            ("claude-3-opus",         "Claude Opus 3"),
            ("claude-3-sonnet",       "Claude Sonnet 3"),
            ("gpt-4o-mini",           "GPT-4o mini"),
            ("gpt-4o",                "GPT-4o"),
            ("gpt-4",                 "GPT-4"),
            ("o3-mini",               "o3-mini"),
            ("o3",                    "o3"),
            ("o1-mini",               "o1-mini"),
            ("o1",                    "o1"),
            ("gemini-2.0-flash",      "Gemini 2.0 Flash"),
            ("gemini-2.5-pro",        "Gemini 2.5 Pro"),
            ("gemini-1.5-pro",        "Gemini 1.5 Pro"),
        ]
        let lower = model.lowercased()
        for entry in known where lower.contains(entry.prefix) {
            return entry.name
        }
        // Capitalise first letter as fallback
        return model.prefix(1).uppercased() + model.dropFirst()
    }

    enum RequestKind: String, Codable {
        case agent      = "agent"
        case composer   = "composer"
        case chat       = "chat"
        case completion = "completion"
        case unknown    = "unknown"

        var icon: String {
            switch self {
            case .agent:      return "🤖"
            case .composer:   return "✍️"
            case .chat:       return "💬"
            case .completion: return "⚡"
            case .unknown:    return "•"
            }
        }
    }
}

// MARK: - Codable mapping from raw API shape

extension UsageEvent {
    /// Raw shape returned inside `usageBasedPremiumRequests` or invoice `usageItems`.
    struct RawItem: Decodable {
        let id: String?
        let model: String?
        let inputTokens: Int?
        let outputTokens: Int?
        let totalCost: Double?
        let cents: Int?        // some endpoints return cents
        let timestamp: String?
        let type: String?
        let kind: String?

        enum CodingKeys: String, CodingKey {
            case id, model, timestamp, type, kind
            case inputTokens  = "inputTokens"
            case outputTokens = "outputTokens"
            case totalCost    = "totalCost"
            case cents
        }
    }

    static func from(_ raw: RawItem, index: Int) -> UsageEvent? {
        guard let model = raw.model, !model.isEmpty else { return nil }

        let costUSD: Double
        if let tc = raw.totalCost { costUSD = tc }
        else if let c = raw.cents { costUSD = Double(c) / 100.0 }
        else { costUSD = 0 }

        let ts: Date
        if let tsStr = raw.timestamp {
            ts = ISO8601DateFormatter().date(from: tsStr) ?? Date()
        } else {
            ts = Date()
        }

        let kindRaw = raw.kind ?? raw.type ?? "unknown"
        let kind = RequestKind(rawValue: kindRaw.lowercased()) ?? .unknown

        return UsageEvent(
            id: raw.id ?? "event-\(index)",
            model: model,
            inputTokens: raw.inputTokens ?? 0,
            outputTokens: raw.outputTokens ?? 0,
            costUSD: costUSD,
            timestamp: ts,
            kind: kind
        )
    }
}
