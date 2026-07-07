import Foundation

/// How often `UsageStore` polls cursor.com for fresh usage data.
///
/// `.adaptive` is the recommended default: cadence is computed live by
/// `AdaptiveRefreshPolicy` from user interaction, Low Power Mode, and thermal state,
/// rather than a fixed interval. The fixed cases exist for users who want predictable,
/// explicit control; `.manual` disables the background timer entirely.
enum RefreshFrequency: String, CaseIterable, Identifiable {
    case manual
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    /// Newest/most advanced option; kept last so the picker still lists the fixed
    /// intervals in ascending cadence order before it.
    case adaptive

    var id: String { rawValue }

    /// nil for `.manual` (no timer) and `.adaptive` (delay is computed per tick by
    /// `AdaptiveRefreshPolicy`, not a fixed interval).
    var seconds: TimeInterval? {
        switch self {
        case .manual:         return nil
        case .oneMinute:      return 60
        case .twoMinutes:     return 120
        case .fiveMinutes:    return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes:  return 1_800
        case .adaptive:       return nil
        }
    }

    var displayName: String {
        switch self {
        case .manual:         return "Manual"
        case .oneMinute:      return "1 minute"
        case .twoMinutes:     return "2 minutes"
        case .fiveMinutes:    return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes:  return "30 minutes"
        case .adaptive:       return "Adaptive (Recommended)"
        }
    }

    /// Best-effort mapping from the legacy numeric-minutes setting, used once during
    /// migration so existing users keep an equivalent fixed cadence instead of being
    /// silently switched to adaptive. New installs default to `.adaptive` directly.
    static func closestFixed(toMinutes minutes: Int) -> RefreshFrequency {
        let candidates: [(RefreshFrequency, Int)] = [
            (.oneMinute, 1), (.twoMinutes, 2), (.fiveMinutes, 5),
            (.fifteenMinutes, 15), (.thirtyMinutes, 30)
        ]
        return candidates.min { abs($0.1 - minutes) < abs($1.1 - minutes) }?.0 ?? .adaptive
    }
}
