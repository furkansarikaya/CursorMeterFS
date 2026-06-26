import Foundation

/// Cursor subscription plan tier.
/// Detected automatically from `cursorAuth/stripeMembershipType` in the local SQLite DB.
/// Can be overridden by the user in Settings.
enum Plan: String, Codable, CaseIterable, Identifiable {
    case free     = "free"
    case pro      = "pro"
    case proPlus  = "pro_plus"   // sometimes returned as "pro_plus"
    case ultra    = "ultra"
    case business = "business"
    case team     = "team"

    var id: String { rawValue }

    /// Human-readable label shown in Settings
    var displayName: String {
        switch self {
        case .free:     return "Free"
        case .pro:      return "Pro"
        case .proPlus:  return "Pro+"
        case .ultra:    return "Ultra"
        case .business: return "Business"
        case .team:     return "Team"
        }
    }

    /// Monthly included usage budget in USD (approximate, used for display only).
    /// Actual quota (maxRequestUsage) always comes from the API — never hardcoded.
    var includedBudgetUSD: Double {
        switch self {
        case .free:     return 0
        case .pro:      return 20
        case .proPlus:  return 70
        case .ultra:    return 400
        case .business: return 40   // per seat
        case .team:     return 40   // per seat
        }
    }

    /// Parse from the string stored in `cursorAuth/stripeMembershipType`.
    /// Returns `.pro` as safe default when the raw string is unrecognised.
    static func from(rawValue: String?) -> Plan {
        guard let raw = rawValue?.lowercased().trimmingCharacters(in: .whitespaces) else {
            return .free  // unknown → safest assumption is free, not pro
        }
        // Handle known aliases
        switch raw {
        case "free", "hobby":       return .free
        case "pro":                 return .pro
        case "pro_plus", "proplus": return .proPlus
        case "ultra":               return .ultra
        case "business":            return .business
        case "team":                return .team
        default:
            // Try direct match first
            if let matched = Plan(rawValue: raw) { return matched }
            // Fallback: check prefix
            if raw.hasPrefix("ultra") { return .ultra }
            if raw.hasPrefix("business") { return .business }
            if raw.hasPrefix("pro_plus") { return .proPlus }
            if raw.hasPrefix("pro") { return .pro }
            return .pro
        }
    }
}
