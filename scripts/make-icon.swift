// Draws the app icon: a hot gradient squircle with a white alarm clock mid-tantrum.
// Usage: swift scripts/make-icon.swift <output.iconset folder>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // macOS icon grid: an 824 pt squircle centred on a 1024 canvas.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let gradient = NSGradient(colors: [
        NSColor(red: 1.0, green: 0.78, blue: 0.10, alpha: 1),
        NSColor(red: 0.90, green: 0.30, blue: 0.08, alpha: 1),
        NSColor(red: 0.86, green: 0.13, blue: 0.40, alpha: 1),
        NSColor(red: 0.55, green: 0.08, blue: 0.35, alpha: 1),
    ], atLocations: [0, 0.35, 0.7, 1], colorSpace: .deviceRGB)!
    gradient.draw(in: body, angle: -60)

    // Faint "!!" behind the clock.
    let bang = NSAttributedString(string: "!!", attributes: [
        .font: NSFont.systemFont(ofSize: 620 * s, weight: .black),
        .foregroundColor: NSColor.white.withAlphaComponent(0.12),
    ])
    NSGraphicsContext.current?.cgContext.saveGState()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: 560 * s, y: 120 * s)
    ctx.rotate(by: 0.18)
    bang.draw(at: .zero)
    ctx.restoreGState()

    // Shake lines either side of the clock.
    NSColor.white.withAlphaComponent(0.85).setStroke()
    for (x, flip) in [(250.0, -1.0), (774.0, 1.0)] {
        for (i, dy) in [-70.0, 0.0, 70.0].enumerated() {
            let line = NSBezierPath()
            line.lineWidth = 26 * s
            line.lineCapStyle = .round
            let len = i == 1 ? 70.0 : 50.0
            line.move(to: NSPoint(x: x * s, y: (520 + dy) * s))
            line.line(to: NSPoint(x: (x + flip * len) * s, y: (520 + dy * 1.25) * s))
            line.stroke()
        }
    }
    NSGraphicsContext.restoreGraphicsState()

    // The clock, tilted, as if it is jumping.
    let config = NSImage.SymbolConfiguration(pointSize: 470 * s, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let clock = NSImage(systemSymbolName: "alarm.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        ctx.translateBy(x: 512 * s, y: 505 * s)
        ctx.rotate(by: 0.16)
        let r = NSRect(x: -clock.size.width / 2, y: -clock.size.height / 2, width: clock.size.width, height: clock.size.height)
        let drop = NSShadow()
        drop.shadowColor = NSColor(red: 0.4, green: 0.02, blue: 0.2, alpha: 0.45)
        drop.shadowBlurRadius = 20 * s
        drop.shadowOffset = NSSize(width: 0, height: -12 * s)
        drop.set()
        clock.draw(in: r)
        ctx.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let png = render(size: CGFloat(px)).representation(using: .png, properties: [:])!
    try png.write(to: out.appendingPathComponent("icon_\(name).png"))
}
print("icon written to \(out.path)")
