import Cocoa

// Renders a simple 1024×1024 app icon: rounded blue square with a white "‹|" glyph.
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let rect = NSRect(origin: .zero, size: size).insetBy(dx: 60, dy: 60)
let bg = NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220)
let gradient = NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.55, blue: 1.0, alpha: 1),
                                   NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.85, alpha: 1)])!
gradient.draw(in: bg, angle: -90)

NSColor.white.setStroke()
// Divider line
let line = NSBezierPath()
line.lineWidth = 56
line.lineCapStyle = .round
line.move(to: NSPoint(x: 640, y: 300))
line.line(to: NSPoint(x: 640, y: 724))
line.stroke()
// Chevron pointing left
let chev = NSBezierPath()
chev.lineWidth = 56
chev.lineCapStyle = .round
chev.lineJoinStyle = .round
chev.move(to: NSPoint(x: 500, y: 700))
chev.line(to: NSPoint(x: 320, y: 512))
chev.line(to: NSPoint(x: 500, y: 324))
chev.stroke()
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
