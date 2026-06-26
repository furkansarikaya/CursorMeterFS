import Foundation

/// Monthly request-quota usage data fetched from `cursor.com/api/usage`.
struct UsageData: Equatable {
    /// Number of requests consumed so far this month.
    let used: Int
    /// Maximum requests allowed this month — dynamic, comes from the API (`maxRequestUsage`).
    let total: Int
    /// On-demand (usage-based) spend in USD this month.
    let onDemandSpendUSD: Double
    /// Hard limit set on the account (nil if not configured).
    let hardLimitUSD: Double?
    /// Whether usage-based (on-demand) charging is enabled.
    let usageBasedEnabled: Bool
    /// Start of the current billing cycle (from `startOfMonth` in the API).
    let billingCycleStart: Date
    /// Subscription plan (auto-detected, may be overridden in Settings).
    let plan: Plan

    /// 0.0 – 1.0 fraction consumed.
    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(Double(used) / Double(total), 1.0)
    }

    var percentageInt: Int { Int(fraction * 100) }

    func status(warningThreshold: Double, criticalThreshold: Double) -> UsageStatus {
        UsageStatus.from(
            fraction: fraction,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold
        )
    }

    /// Human-readable reset date: "in N days", "in N hours", "tomorrow", etc.
    var resetDateDescription: String {
        let calendar = Calendar.current
        // Reset is the first day of the next month at billing cycle time
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: billingCycleStart) else {
            return "Unknown"
        }
        return nextMonth.relativeDescription(from: Date())
    }

    var remainingRequests: Int { max(total - used, 0) }
}

// MARK: - Placeholder (loading state)
extension UsageData {
    static let placeholder = UsageData(
        used: 0,
        total: 1,
        onDemandSpendUSD: 0,
        hardLimitUSD: nil,
        usageBasedEnabled: false,
        billingCycleStart: Date(),
        plan: .pro
    )
}
