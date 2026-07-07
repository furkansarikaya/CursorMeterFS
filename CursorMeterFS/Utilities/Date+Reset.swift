import Foundation

// MARK: - Static formatter (allocated once; RelativeDateTimeFormatter is expensive to init)
private let _relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated   // "3m ago", "2h ago", "1d ago"
    f.dateTimeStyle = .numeric
    return f
}()

extension Date {
    /// Returns a short human-readable relative description for a **past** date.
    /// e.g. "3 min. ago", "2 hr. ago", "1 day ago"
    /// Uses a shared static formatter — safe to call from any view body without
    /// allocation overhead. Does NOT install a live timer (unlike Text(_, style: .relative)).
    /// Clamped to minute resolution — sub-minute values render as "just now" rather than
    /// a second count, since nothing in this app refreshes faster than that anyway.
    func shortRelativeDescription(to now: Date = Date()) -> String {
        guard now.timeIntervalSince(self) >= 60 else { return "just now" }
        return _relativeFormatter.localizedString(for: self, relativeTo: now)
    }

    /// Returns a human-readable relative description from a reference date.
    /// e.g. "in 3 days", "in 2 hours", "tomorrow", "today"
    func relativeDescription(from now: Date = Date()) -> String {
        let seconds = self.timeIntervalSince(now)
        guard seconds > 0 else { return "now" }

        let minutes = Int(seconds / 60)
        let hours   = Int(seconds / 3600)
        let days    = Int(seconds / 86400)

        switch days {
        case 0 where hours == 0: return "in \(max(minutes, 1)) minute\(minutes == 1 ? "" : "s")"
        case 0:                  return "in \(hours) hour\(hours == 1 ? "" : "s")"
        case 1:                  return "tomorrow"
        default:                 return "in \(days) day\(days == 1 ? "" : "s")"
        }
    }
}

extension Date {
    /// Start of the current billing month at midnight UTC.
    static func startOfCurrentBillingMonth() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }

    /// Next billing cycle reset date (first of next month at midnight UTC).
    static func nextBillingReset(from billingCycleStart: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(byAdding: .month, value: 1, to: billingCycleStart) ?? Date()
    }
}
