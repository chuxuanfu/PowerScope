import AppKit
import Foundation
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let s = CGFloat(size)
    let rect = NSRect(x: s * 0.045, y: s * 0.045, width: s * 0.91, height: s * 0.91)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.27, alpha: 1), ending: NSColor(calibratedRed: 0.025, green: 0.055, blue: 0.09, alpha: 1))!.draw(in: bg, angle: -45)
    let ring = NSBezierPath(ovalIn: NSRect(x: s * 0.20, y: s * 0.20, width: s * 0.60, height: s * 0.60))
    NSColor(calibratedRed: 0.26, green: 0.87, blue: 0.73, alpha: 0.18).setStroke()
    ring.lineWidth = s * 0.045
    ring.stroke()
    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: s * 0.57, y: s * 0.83))
    bolt.line(to: NSPoint(x: s * 0.30, y: s * 0.46))
    bolt.line(to: NSPoint(x: s * 0.47, y: s * 0.46))
    bolt.line(to: NSPoint(x: s * 0.41, y: s * 0.18))
    bolt.line(to: NSPoint(x: s * 0.71, y: s * 0.57))
    bolt.line(to: NSPoint(x: s * 0.53, y: s * 0.57))
    bolt.close()
    NSColor(calibratedRed: 0.30, green: 0.92, blue: 0.76, alpha: 1).setFill()
    bolt.fill()
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    let name: String
    switch size {
    case 1024: name = "icon_512x512@2x.png"
    case 64: name = "icon_32x32@2x.png"
    default: name = "icon_\(size)x\(size).png"
    }
    try png.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name))
    if [32, 256, 512].contains(size) {
        try png.write(to: URL(fileURLWithPath: destination).appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png"))
    }
}
