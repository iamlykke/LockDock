// Renders the app icon: swift Tools/make_icon.swift <output.iconset>
import AppKit

func render(size px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    // Body on Apple's 824pt grid with a soft drop shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35).cgColor)
    rgb(0x3D5AFE).setFill()
    bodyPath.fill()
    ctx.restoreGState()
    bodyPath.addClip()
    NSGradient(colors: [rgb(0x6C8CFF), rgb(0x3A4FE0), rgb(0x2A2F9E)])!.draw(in: body, angle: -90)

    // Monitor.
    let frame = NSRect(x: 196, y: 330, width: 632, height: 430)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0x0B0F40, 0.45).cgColor)
    rgb(0xF4F6FF).setFill()
    NSBezierPath(roundedRect: frame, xRadius: 46, yRadius: 46).fill()
    ctx.restoreGState()

    let neck = NSBezierPath()
    neck.move(to: NSPoint(x: 462, y: 332))
    neck.line(to: NSPoint(x: 562, y: 332))
    neck.line(to: NSPoint(x: 580, y: 250))
    neck.line(to: NSPoint(x: 444, y: 250))
    neck.close()
    rgb(0xD9DEF7).setFill()
    neck.fill()
    rgb(0xF4F6FF).setFill()
    NSBezierPath(roundedRect: NSRect(x: 382, y: 222, width: 260, height: 40), xRadius: 20, yRadius: 20).fill()

    let screen = frame.insetBy(dx: 28, dy: 28)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: 22, yRadius: 22)
    ctx.saveGState()
    screenPath.addClip()
    NSGradient(colors: [rgb(0x1B2266), rgb(0x0E1240)])!.draw(in: screen, angle: -90)
    ctx.restoreGState()

    // Dock bar with app tiles.
    let dock = NSRect(x: 250, y: screen.minY + 22, width: 346, height: 76)
    rgb(0xFFFFFF, 0.22).setFill()
    NSBezierPath(roundedRect: dock, xRadius: 24, yRadius: 24).fill()
    let tiles: [UInt32] = [0xFF6B6B, 0xFFC94D, 0x4CD787, 0x4DB8FF]
    for (i, color) in tiles.enumerated() {
        rgb(color).setFill()
        let x = dock.minX + 26 + CGFloat(i) * 82
        NSBezierPath(roundedRect: NSRect(x: x, y: dock.minY + 14, width: 48, height: 48), xRadius: 12, yRadius: 12).fill()
    }

    // Padlock badge, bottom right.
    let badgeCenter = NSPoint(x: 730, y: 330)
    let badge = NSRect(x: badgeCenter.x - 128, y: badgeCenter.y - 128, width: 256, height: 256)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x0B0F40, 0.5).cgColor)
    NSGradient(colors: [rgb(0xFFD66B), rgb(0xFF9F2E)])!.draw(in: NSBezierPath(ovalIn: badge), angle: -90)
    ctx.restoreGState()

    let shackle = NSBezierPath()
    shackle.move(to: NSPoint(x: badgeCenter.x - 44, y: badgeCenter.y - 6))
    shackle.line(to: NSPoint(x: badgeCenter.x - 44, y: badgeCenter.y + 26))
    shackle.appendArc(withCenter: NSPoint(x: badgeCenter.x, y: badgeCenter.y + 26), radius: 44,
                      startAngle: 180, endAngle: 0, clockwise: true)
    shackle.line(to: NSPoint(x: badgeCenter.x + 44, y: badgeCenter.y - 6))
    shackle.lineWidth = 22
    shackle.lineCapStyle = .round
    rgb(0xFFFFFF).setStroke()
    shackle.stroke()
    rgb(0xFFFFFF).setFill()
    NSBezierPath(roundedRect: NSRect(x: badgeCenter.x - 72, y: badgeCenter.y - 84, width: 144, height: 104),
                 xRadius: 22, yRadius: 22).fill()
    rgb(0xFF9F2E).setFill()
    NSBezierPath(ovalIn: NSRect(x: badgeCenter.x - 13, y: badgeCenter.y - 42, width: 26, height: 26)).fill()
    NSBezierPath(roundedRect: NSRect(x: badgeCenter.x - 6, y: badgeCenter.y - 62, width: 12, height: 30),
                 xRadius: 6, yRadius: 6).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
