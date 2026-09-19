import Cocoa

/// The look of Tuck's menu bar button. Every style is a tiny template image
/// (the system tints it for light/dark menu bars) with a "tucked" and a
/// "peeking" variant.
enum IconStyle: String, CaseIterable {
    case chevron, dot, line, ellipsis

    var title: String {
        switch self {
        case .chevron: return "Thin Chevron  ‹"
        case .dot: return "Dot  •"
        case .line: return "Line  |"
        case .ellipsis: return "Ellipsis  ···"
        }
    }

    static var current: IconStyle {
        get { IconStyle(rawValue: UserDefaults.standard.string(forKey: "iconStyle") ?? "") ?? .chevron }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "iconStyle") }
    }

    /// `collapsed` = icons are tucked away.
    func image(collapsed: Bool) -> NSImage {
        let height: CGFloat = 18
        let width: CGFloat
        switch self {
        case .chevron: width = 9
        case .dot: width = 9
        case .line: width = collapsed ? 5 : 9
        case .ellipsis: width = 15
        }
        let style = self
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let midX = rect.midX, midY = rect.midY
            switch style {
            case .chevron:
                // Hairline chevron, 4.5 × 9 pt.
                let path = NSBezierPath()
                path.lineWidth = 1.3
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                let dx: CGFloat = collapsed ? 2.25 : -2.25
                path.move(to: NSPoint(x: midX + dx, y: midY + 4.5))
                path.line(to: NSPoint(x: midX - dx, y: midY))
                path.line(to: NSPoint(x: midX + dx, y: midY - 4.5))
                path.stroke()
            case .dot:
                if collapsed {
                    NSBezierPath(ovalIn: NSRect(x: midX - 2.5, y: midY - 2.5, width: 5, height: 5)).fill()
                } else {
                    let ring = NSBezierPath(ovalIn: NSRect(x: midX - 3, y: midY - 3, width: 6, height: 6))
                    ring.lineWidth = 1.2
                    ring.stroke()
                }
            case .line:
                let xs: [CGFloat] = collapsed ? [midX] : [midX - 2, midX + 2]
                for x in xs {
                    NSBezierPath(roundedRect: NSRect(x: x - 0.7, y: midY - 5.5, width: 1.4, height: 11),
                                 xRadius: 0.7, yRadius: 0.7).fill()
                }
            case .ellipsis:
                if collapsed {
                    for offset in [-4.5, 0, 4.5] as [CGFloat] {
                        NSBezierPath(ovalIn: NSRect(x: midX + offset - 1.25, y: midY - 1.25, width: 2.5, height: 2.5)).fill()
                    }
                } else {
                    NSBezierPath(roundedRect: NSRect(x: midX - 4.5, y: midY - 0.7, width: 9, height: 1.4),
                                 xRadius: 0.7, yRadius: 0.7).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = collapsed ? "Show tucked icons" : "Hide tucked icons"
        return image
    }
}
