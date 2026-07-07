import AppKit

/// Renders the dynamic menu bar icon in various styles.
/// All drawing is done with Core Graphics — no external assets required.
/// Template images (mono) respect macOS dark/light mode automatically.
enum MenuBarIconRenderer {

    /// Size of the status item button — standard macOS height is 18pt.
    static let iconSize = NSSize(width: 32, height: 18)

    // MARK: - Small keyed cache
    // Keyed on (style, colorMode, percentInt, used, total, status). fraction is rounded
    // to integer percent so sub-percent floating-point noise never causes spurious misses.
    // A small dictionary (not a single entry) so switching provider tabs — which
    // alternates the inputs — doesn't thrash the cache.
    private struct CacheKey: Hashable {
        let style: MenuBarIconStyle
        let colorMode: IconColorMode
        let percentInt: Int          // Int(fraction * 100)
        let used: Int
        let total: Int
        let status: UsageStatus
    }
    private static var cache: [CacheKey: NSImage] = [:]
    private static let cacheLimit = 24

    // MARK: - Main entry point

    static func image(
        fraction: Double,
        used: Int = 0,
        total: Int = 0,
        status: UsageStatus,
        style: MenuBarIconStyle,
        colorMode: IconColorMode
    ) -> NSImage {
        let key = CacheKey(
            style: style,
            colorMode: colorMode,
            percentInt: Int(fraction * 100),
            used: used,
            total: total,
            status: status
        )
        if let cached = cache[key] {
            return cached
        }

        let isColor = colorMode == .color
        let color: NSColor = isColor
            ? .usageColor(for: status)
            : .secondaryLabelColor

        let img: NSImage
        switch style {
        case .battery:      img = batteryImage(fraction: fraction, color: color, isTemplate: !isColor)
        case .circular:     img = circularImage(fraction: fraction, color: color, isTemplate: !isColor)
        case .minimal:      img = minimalPctImage(fraction: fraction, color: color, isTemplate: !isColor)
        case .minimalCount: img = minimalCountImage(used: used, total: total, color: color, isTemplate: !isColor)
        case .segments:     img = segmentsImage(fraction: fraction, color: color, isTemplate: !isColor)
        case .dualBar:      img = dualBarImage(fraction: fraction, color: color, isTemplate: !isColor)
        case .countBar:     img = countBarImage(used: used, total: total, fraction: fraction, color: color, isTemplate: !isColor)
        case .gauge:        img = gaugeImage(fraction: fraction, color: color, isTemplate: !isColor)
        }

        if cache.count >= cacheLimit {
            cache.removeAll(keepingCapacity: true)   // rare; cheap full reset beats LRU bookkeeping
        }
        cache[key] = img
        return img
    }

    // MARK: - Battery style (≈ MacBook battery indicator)

    static func batteryImage(fraction: Double, color: NSColor, isTemplate: Bool) -> NSImage {
        let size = iconSize
        return NSImage(size: size, flipped: false) { rect in
            let bodyW: CGFloat = 24
            let bodyH: CGFloat = 12
            let tipW:  CGFloat = 3
            let tipH:  CGFloat = 6
            let x = (rect.width - bodyW - tipW) / 2
            let y = (rect.height - bodyH) / 2

            // Outer shell
            let shell = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: bodyW, height: bodyH), xRadius: 2.5, yRadius: 2.5)
            NSColor.labelColor.withAlphaComponent(0.5).setStroke()
            shell.lineWidth = 1
            shell.stroke()

            // Tip
            let tip = NSBezierPath(roundedRect: NSRect(x: x + bodyW + 1, y: y + (bodyH - tipH) / 2, width: tipW, height: tipH), xRadius: 1, yRadius: 1)
            NSColor.labelColor.withAlphaComponent(0.4).setFill()
            tip.fill()

            // Fill
            let fillW = max(2, (bodyW - 4) * CGFloat(fraction))
            let fill = NSBezierPath(roundedRect: NSRect(x: x + 2, y: y + 2, width: fillW, height: bodyH - 4), xRadius: 1.5, yRadius: 1.5)
            color.setFill()
            fill.fill()

            return true
        }.templateIfNeeded(isTemplate)
    }

    // MARK: - Circular (pie/ring) style

    static func circularImage(fraction: Double, color: NSColor, isTemplate: Bool) -> NSImage {
        let size = iconSize
        return NSImage(size: size, flipped: false) { rect in
            let r: CGFloat  = 7
            let cx = rect.midX
            let cy = rect.midY
            let lineW: CGFloat = 2.5

            // Track
            let track = NSBezierPath()
            track.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r,
                            startAngle: 90, endAngle: 90 - 360, clockwise: true)
            NSColor.labelColor.withAlphaComponent(0.2).setStroke()
            track.lineWidth = lineW
            track.stroke()

            // Progress arc
            if fraction > 0 {
                let endAngle = 90 - (360 * CGFloat(fraction))
                let arc = NSBezierPath()
                arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r,
                              startAngle: 90, endAngle: endAngle, clockwise: true)
                color.setStroke()
                arc.lineWidth = lineW
                arc.lineCapStyle = .round
                arc.stroke()
            }

            return true
        }.templateIfNeeded(isTemplate)
    }

    // MARK: - Minimal % (percentage only)

    static func minimalPctImage(fraction: Double, color: NSColor, isTemplate: Bool) -> NSImage {
        let str = "\(Int(fraction * 100))%"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: isTemplate ? NSColor.labelColor : color,
        ]
        let attrStr = NSAttributedString(string: str, attributes: attrs)
        let textSize = attrStr.size()
        let size = NSSize(width: max(textSize.width + 4, 32), height: 18)
        return NSImage(size: size, flipped: false) { rect in
            attrStr.draw(at: NSPoint(x: (rect.width - textSize.width) / 2,
                                     y: (rect.height - textSize.height) / 2))
            return true
        }.templateIfNeeded(isTemplate)
    }

    // MARK: - Minimal # (count only: "940/1k")

    static func minimalCountImage(used: Int, total: Int, color: NSColor, isTemplate: Bool) -> NSImage {
        func fmt(_ n: Int) -> String { n >= 1000 ? "\(n / 1000)k" : "\(n)" }
        let str = total > 0 ? "\(fmt(used))/\(fmt(total))" : "\(fmt(used))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: isTemplate ? NSColor.labelColor : color,
        ]
        let attrStr = NSAttributedString(string: str, attributes: attrs)
        let textSize = attrStr.size()
        let size = NSSize(width: max(textSize.width + 4, 32), height: 18)
        return NSImage(size: size, flipped: false) { rect in
            attrStr.draw(at: NSPoint(x: (rect.width - textSize.width) / 2,
                                     y: (rect.height - textSize.height) / 2))
            return true
        }.templateIfNeeded(isTemplate)
    }

    // MARK: - Segments (bar-chart style)

    static func segmentsImage(fraction: Double, color: NSColor, isTemplate: Bool) -> NSImage {
        let size = iconSize
        return NSImage(size: size, flipped: false) { rect in
            let totalSegs = 5
            let segW: CGFloat  = 4
            let segGap: CGFloat = 2
            let heights: [CGFloat] = [6, 8, 10, 12, 14]
            let totalW = CGFloat(totalSegs) * segW + CGFloat(totalSegs - 1) * segGap
            var x = (rect.width - totalW) / 2

            let filledSegs = Int((fraction * Double(totalSegs)).rounded())

            for i in 0..<totalSegs {
                let h = heights[i]
                let y = (rect.height - h) / 2
                let segRect = NSRect(x: x, y: y, width: segW, height: h)
                let path = NSBezierPath(roundedRect: segRect, xRadius: 1, yRadius: 1)

                if i < filledSegs {
                    color.setFill()
                } else {
                    NSColor.labelColor.withAlphaComponent(0.2).setFill()
                }
                path.fill()
                x += segW + segGap
            }
            return true
        }.templateIfNeeded(isTemplate)
    }

    // MARK: - Dual Bar (compact horizontal bar + %)

    static func dualBarImage(fraction: Double, color: NSColor, isTemplate: Bool) -> NSImage {
        let pct = Int(fraction * 100)
        let pctStr = "\(pct)%"
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: isTemplate ? NSColor.labelColor : color,
        ]
        let pctAS = NSAttributedString(string: pctStr, attributes: pctAttrs)
        let pctSize = pctAS.size()

        let barW: CGFloat = 28
        let gap:  CGFloat = 3
        let totalW = barW + gap + pctSize.width + 2

        return NSImage(size: NSSize(width: totalW, height: 18), flipped: false) { rect in
            let barH: CGFloat = 4
            let barX: CGFloat = 0
            let barY = (rect.height - barH) / 2

            // Track
            let track = NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: barW, height: barH), xRadius: 2, yRadius: 2)
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            track.fill()

            // Fill
            let fillW = max(barH, barW * CGFloat(fraction))
            let fill = NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: fillW, height: barH), xRadius: 2, yRadius: 2)
            color.setFill()
            fill.fill()

            // Percentage text
            pctAS.draw(at: NSPoint(x: barX + barW + gap, y: (rect.height - pctSize.height) / 2))
            return true
        }.templateIfNeeded(isTemplate)
    }

    // MARK: - Count Bar (compact horizontal bar + "used/total")

    static func countBarImage(used: Int, total: Int, fraction: Double, color: NSColor, isTemplate: Bool) -> NSImage {
        // Format: "937/1k", "42/500", "1.2k/2k" etc.
        func fmt(_ n: Int) -> String {
            if n >= 1000 { return "\(n / 1000)k" }
            return "\(n)"
        }
        let countStr = total > 0 ? "\(fmt(used))/\(fmt(total))" : "\(fmt(used))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: isTemplate ? NSColor.labelColor : color,
        ]
        let countAS   = NSAttributedString(string: countStr, attributes: attrs)
        let countSize = countAS.size()

        let barW: CGFloat = 22
        let gap:  CGFloat = 3
        let totalW = barW + gap + countSize.width + 2

        return NSImage(size: NSSize(width: totalW, height: 18), flipped: false) { rect in
            let barH: CGFloat = 4
            let barX: CGFloat = 0
            let barY = (rect.height - barH) / 2

            let track = NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: barW, height: barH), xRadius: 2, yRadius: 2)
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            track.fill()

            let fillW = max(barH, barW * CGFloat(fraction))
            let fill = NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: fillW, height: barH), xRadius: 2, yRadius: 2)
            color.setFill()
            fill.fill()

            countAS.draw(at: NSPoint(x: barX + barW + gap, y: (rect.height - countSize.height) / 2))
            return true
        }.templateIfNeeded(isTemplate)
    }

    // MARK: - Gauge (speedometer arc)

    static func gaugeImage(fraction: Double, color: NSColor, isTemplate: Bool) -> NSImage {
        let size = iconSize
        return NSImage(size: size, flipped: false) { rect in
            let cx = rect.midX
            let cy = rect.midY - 1
            let r:  CGFloat = 7
            let lw: CGFloat = 2.5

            // Arc from 210° to -30° (bottom-left to bottom-right)
            let startAngle: CGFloat = 210
            let endFullAngle: CGFloat = -30
            let sweepAngle = startAngle - endFullAngle  // 240°

            // Track
            let track = NSBezierPath()
            track.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r,
                            startAngle: startAngle, endAngle: endFullAngle, clockwise: true)
            NSColor.labelColor.withAlphaComponent(0.2).setStroke()
            track.lineWidth = lw
            track.lineCapStyle = .round
            track.stroke()

            // Fill arc
            if fraction > 0 {
                let fillEnd = startAngle - sweepAngle * CGFloat(fraction)
                let fill = NSBezierPath()
                fill.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r,
                               startAngle: startAngle, endAngle: fillEnd, clockwise: true)
                color.setStroke()
                fill.lineWidth = lw
                fill.lineCapStyle = .round
                fill.stroke()
            }

            // Needle dot
            let dot = NSBezierPath(ovalIn: NSRect(x: cx - 1.5, y: cy - 1.5, width: 3, height: 3))
            NSColor.labelColor.withAlphaComponent(0.6).setFill()
            dot.fill()

            return true
        }.templateIfNeeded(isTemplate)
    }
}

// MARK: - NSImage helper
private extension NSImage {
    func templateIfNeeded(_ isTemplate: Bool) -> NSImage {
        self.isTemplate = isTemplate
        return self
    }
}
