import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func drawIcon(size: Int, filename: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 204, yRadius: 204)
    NSGradient(starting: NSColor(calibratedRed: 0.23, green: 0.43, blue: 0.36, alpha: 1), ending: NSColor(calibratedRed: 0.10, green: 0.27, blue: 0.22, alpha: 1))!.draw(in: tile, angle: -90)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.91, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 264, y: 194, width: 498, height: 636), xRadius: 43, yRadius: 43).fill()
    NSGraphicsContext.restoreGraphicsState()
    let ink = NSColor(calibratedRed: 0.21, green: 0.39, blue: 0.32, alpha: 1)
    ink.setStroke()
    let mark = NSBezierPath()
    mark.lineWidth = 34
    mark.lineCapStyle = .round
    mark.lineJoinStyle = .round
    mark.move(to: NSPoint(x: 355, y: 514))
    mark.line(to: NSPoint(x: 355, y: 685))
    mark.line(to: NSPoint(x: 447, y: 590))
    mark.line(to: NSPoint(x: 539, y: 685))
    mark.line(to: NSPoint(x: 539, y: 514))
    mark.stroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 27
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 645, y: 677)); arrow.line(to: NSPoint(x: 645, y: 526))
    arrow.move(to: NSPoint(x: 601, y: 568)); arrow.line(to: NSPoint(x: 645, y: 524)); arrow.line(to: NSPoint(x: 688, y: 568))
    arrow.stroke()
    ink.withAlphaComponent(0.22).setFill()
    for (y, width) in [(417, 332), (347, 332), (277, 216)] {
        NSBezierPath(roundedRect: NSRect(x: 347, y: y, width: width, height: 17), xRadius: 8, yRadius: 8).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
}
for size in [16, 32, 128, 256, 512] {
    try drawIcon(size: size, filename: "icon_\(size)x\(size).png")
    try drawIcon(size: size * 2, filename: "icon_\(size)x\(size)@2x.png")
}
