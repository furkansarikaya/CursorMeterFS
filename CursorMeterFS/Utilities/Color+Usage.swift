import SwiftUI

extension Color {
    static let usageSafe     = Color(red: 0.18, green: 0.78, blue: 0.25)  // #2EC840
    static let usageWarning  = Color(red: 1.00, green: 0.62, blue: 0.03)  // #FF9E08
    static let usageCritical = Color(red: 0.93, green: 0.11, blue: 0.14)  // #ED1C24

    static func usage(for status: UsageStatus) -> Color {
        switch status {
        case .safe:     return .usageSafe
        case .warning:  return .usageWarning
        case .critical: return .usageCritical
        }
    }

    static func usage(fraction: Double,
                      warningThreshold: Double = 0.70,
                      criticalThreshold: Double = 0.90) -> Color {
        usage(for: UsageStatus.from(
            fraction: fraction,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold
        ))
    }
}

// MARK: - NSColor bridge for menu bar icon rendering
#if canImport(AppKit)
import AppKit
extension NSColor {
    static func usageColor(for status: UsageStatus) -> NSColor {
        switch status {
        case .safe:     return NSColor(red: 0.18, green: 0.78, blue: 0.25, alpha: 1)
        case .warning:  return NSColor(red: 1.00, green: 0.62, blue: 0.03, alpha: 1)
        case .critical: return NSColor(red: 0.93, green: 0.11, blue: 0.14, alpha: 1)
        }
    }

    static func usageColor(fraction: Double,
                           warningThreshold: Double = 0.70,
                           criticalThreshold: Double = 0.90) -> NSColor {
        usageColor(for: UsageStatus.from(
            fraction: fraction,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold
        ))
    }
}
#endif
