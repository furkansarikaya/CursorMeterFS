import Foundation

/// Traffic-light status derived from current usage percentage vs. thresholds.
enum UsageStatus: String, Codable {
    case safe     /// < warningThreshold
    case warning  /// warningThreshold ..< criticalThreshold
    case critical /// >= criticalThreshold

    /// Determine status from a 0–1 fraction and configurable thresholds.
    static func from(
        fraction: Double,
        warningThreshold: Double = 0.70,
        criticalThreshold: Double = 0.90
    ) -> UsageStatus {
        if fraction >= criticalThreshold { return .critical }
        if fraction >= warningThreshold  { return .warning }
        return .safe
    }

    var displayLabel: String {
        switch self {
        case .safe:     return "Safe"
        case .warning:  return "Warning"
        case .critical: return "Critical"
        }
    }

    var systemImageName: String {
        switch self {
        case .safe:     return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        }
    }
}
