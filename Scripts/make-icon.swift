// Generates the UpdateDoctor app icon. Run: swift Scripts/make-icon.swift
// Writes assets/AppIcon-1024.png, assets/AppIcon.iconset and (with iconutil) App/AppIcon.icns.
// Design: macOS style rounded square with a navy to teal gradient, a white shield
// with a heartbeat line, and a green, yellow and red status dot trio. No text.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("assets")
try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func drawIcon(size px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)
    // Small sizes get a slightly larger, simpler mark so it stays readable.
    let small = px <= 32

    // Apple icon grid: 824 x 824 body centered in 1024, continuous corners.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    color(0x0B1D3A).setFill()
    squircle.fill()
    ctx.restoreGState()

    ctx.saveGState()
    squircle.addClip()
    NSGradient(colors: [color(0x0A1A3F), color(0x0B4F78), color(0x12A5A0)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: body, angle: 60)
    // Soft top highlight.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
    ctx.restoreGState()

    // Shield.
    let cx: CGFloat = 512
    let top: CGFloat = small ? 815 : 790, bottom: CGFloat = small ? 205 : 245
    let half: CGFloat = small ? 255 : 225
    let shield = NSBezierPath()
    shield.move(to: NSPoint(x: cx, y: top))
    shield.curve(to: NSPoint(x: cx + half, y: top - 85), controlPoint1: NSPoint(x: cx + 90, y: top - 55), controlPoint2: NSPoint(x: cx + 170, y: top - 80))
    shield.curve(to: NSPoint(x: cx, y: bottom), controlPoint1: NSPoint(x: cx + half + 5, y: top - 330), controlPoint2: NSPoint(x: cx + 150, y: bottom + 90))
    shield.curve(to: NSPoint(x: cx - half, y: top - 85), controlPoint1: NSPoint(x: cx - 150, y: bottom + 90), controlPoint2: NSPoint(x: cx - half - 5, y: top - 330))
    shield.curve(to: NSPoint(x: cx, y: top), controlPoint1: NSPoint(x: cx - 170, y: top - 80), controlPoint2: NSPoint(x: cx - 90, y: top - 55))
    shield.close()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: NSColor.black.withAlphaComponent(0.30).cgColor)
    NSColor.white.setFill()
    shield.fill()
    ctx.restoreGState()

    // Heartbeat line across the shield.
    let pulse = NSBezierPath()
    let y: CGFloat = small ? 520 : 535
    if small {
        pulse.move(to: NSPoint(x: 330, y: y))
        pulse.line(to: NSPoint(x: 440, y: y))
        pulse.line(to: NSPoint(x: 490, y: y + 150))
        pulse.line(to: NSPoint(x: 560, y: y - 130))
        pulse.line(to: NSPoint(x: 600, y: y))
        pulse.line(to: NSPoint(x: 694, y: y))
        pulse.lineWidth = 64
    } else {
        pulse.move(to: NSPoint(x: 340, y: y))
        pulse.line(to: NSPoint(x: 420, y: y))
        pulse.line(to: NSPoint(x: 460, y: y + 60))
        pulse.line(to: NSPoint(x: 500, y: y - 120))
        pulse.line(to: NSPoint(x: 555, y: y + 150))
        pulse.line(to: NSPoint(x: 595, y: y))
        pulse.line(to: NSPoint(x: 684, y: y))
        pulse.lineWidth = 40
    }
    pulse.lineCapStyle = .round
    pulse.lineJoinStyle = .round
    color(0x0E8C95).setStroke()
    pulse.stroke()

    // Status dot trio: green, yellow, red.
    if !small {
        let colors = [color(0x2FCB65), color(0xFFC83D), color(0xFF4F4F)]
        let r: CGFloat = 30, gap: CGFloat = 86, dy: CGFloat = 375
        for (i, c) in colors.enumerated() {
            let x = cx + CGFloat(i - 1) * gap
            let dot = NSBezierPath(ovalIn: NSRect(x: x - r, y: dy - r, width: r * 2, height: r * 2))
            c.setFill()
            dot.fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

write(drawIcon(size: 1024), assets.appendingPathComponent("AppIcon-1024.png"))
let iconset = assets.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    write(drawIcon(size: base), iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    write(drawIcon(size: base * 2), iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let app = root.appendingPathComponent("App")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", app.appendingPathComponent("AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote assets/AppIcon-1024.png, assets/AppIcon.iconset, App/AppIcon.icns" : "iconutil failed")
