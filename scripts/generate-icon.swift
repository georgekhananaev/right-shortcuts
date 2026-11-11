// Draws the Right Shortcuts app icon into an .iconset folder.
// Usage: swift scripts/generate-icon.swift <output.iconset>
import AppKit

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

/// Draws the icon on a 1024 × 1024 canvas (y grows upward).
func drawIcon() {
    // Body: a rounded square with the standard macOS margin and a soft drop shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    color(0x5847F0).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    NSGradient(colors: [color(0x9A8CFF), color(0x6A5AF9), color(0x3E2FC9)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)?
        .draw(in: body, angle: -60)
    // A gentle glow in the upper left gives the surface some depth.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])?
        .draw(fromCenter: NSPoint(x: 330, y: 840), radius: 0, toCenter: NSPoint(x: 330, y: 840), radius: 620,
              options: [])
    NSGraphicsContext.restoreGraphicsState()

    // The context menu card.
    let card = NSRect(x: 250, y: 236, width: 440, height: 548)
    let cardPath = NSBezierPath(roundedRect: card, xRadius: 58, yRadius: 58)
    NSGraphicsContext.saveGraphicsState()
    let cardShadow = NSShadow()
    cardShadow.shadowColor = color(0x1B1060, alpha: 0.45)
    cardShadow.shadowBlurRadius = 40
    cardShadow.shadowOffset = NSSize(width: 0, height: -18)
    cardShadow.set()
    NSColor.white.setFill()
    cardPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Four menu rows; the second one is highlighted, as if the pointer rests on it.
    let rowHeight: CGFloat = 76
    let rowInset: CGFloat = 30
    let rowGap: CGFloat = 40
    let firstRowTop = card.maxY - 52
    for index in 0..<4 {
        let rowY = firstRowTop - CGFloat(index + 1) * rowHeight - CGFloat(index) * rowGap / 2
        let row = NSRect(x: card.minX + rowInset, y: rowY, width: card.width - rowInset * 2, height: rowHeight)
        let isHighlighted = index == 1
        if isHighlighted {
            color(0x6A5AF9).setFill()
            NSBezierPath(roundedRect: row, xRadius: 22, yRadius: 22).fill()
        }
        let dotColor = isHighlighted ? NSColor.white : color(0xB9B1FF)
        let barColor = isHighlighted ? NSColor.white.withAlphaComponent(0.92) : color(0xDCD8FF)
        let dot = NSRect(x: row.minX + 26, y: row.midY - 15, width: 30, height: 30)
        dotColor.setFill()
        NSBezierPath(roundedRect: dot, xRadius: 9, yRadius: 9).fill()
        let barWidth: CGFloat = [210, 250, 170, 200][index]
        let bar = NSRect(x: dot.maxX + 22, y: row.midY - 11, width: barWidth, height: 22)
        barColor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 11, yRadius: 11).fill()
    }

    // The pointer, resting on the highlighted row.
    let points: [NSPoint] = [
        NSPoint(x: 0, y: 0), NSPoint(x: 0, y: -236), NSPoint(x: 58, y: -182), NSPoint(x: 100, y: -276),
        NSPoint(x: 142, y: -258), NSPoint(x: 100, y: -166), NSPoint(x: 176, y: -166),
    ]
    let tip = NSPoint(x: 600, y: 600)
    let pointer = NSBezierPath()
    pointer.move(to: NSPoint(x: tip.x + points[0].x, y: tip.y + points[0].y))
    for point in points.dropFirst() {
        pointer.line(to: NSPoint(x: tip.x + point.x, y: tip.y + point.y))
    }
    pointer.close()
    pointer.lineJoinStyle = .round

    NSGraphicsContext.saveGraphicsState()
    let pointerShadow = NSShadow()
    pointerShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    pointerShadow.shadowBlurRadius = 18
    pointerShadow.shadowOffset = NSSize(width: 0, height: -8)
    pointerShadow.set()
    NSColor.white.setStroke()
    pointer.lineWidth = 30
    pointer.stroke()
    NSGraphicsContext.restoreGraphicsState()
    color(0x15122B).setFill()
    pointer.fill()
}

func render(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let scale = CGFloat(pixels) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    return png
}

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: outputURL.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: outputURL.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
print("Wrote \(outputURL.path)")
