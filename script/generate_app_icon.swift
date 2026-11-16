#!/usr/bin/env swift
//
// Right Here's current-directory mark, drawn independently at each native resolution.
// Run `swift script/generate_app_icon.swift [preview-directory]` for the assets and an optional size comparison.
// Editable vectors and construction notes live in Design/AppIcon and docs/decisions/0033-current-design-language.md.

import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconSet = root.appendingPathComponent("Apps/RightHere/Assets.xcassets/AppIcon.appiconset")

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}
let background = rgb(0x244F46), slash = rgb(0xF4F4E9), origin = rgb(0xC5D8A8)
enum RenderError: Error { case bitmap, context, png }
func bitmap(_ width: Int, _ height: Int, draw: () -> Void) throws -> NSBitmapImageRep {
    guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw RenderError.bitmap }
    guard let context = NSGraphicsContext(bitmapImageRep: image) else { throw RenderError.context }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.shouldAntialias = true
    draw()
    return image
}
func writePNG(_ image: NSBitmapImageRep, to url: URL) throws {
    guard let bytes = image.representation(using: .png, properties: [:]) else { throw RenderError.png }
    try bytes.write(to: url)
}
func roundedPolygon(_ points: [NSPoint], rounding: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    guard let first = points.first, let last = points.last else { return path }
    func inset(_ vertex: NSPoint, toward other: NSPoint) -> NSPoint {
        let length = hypot(other.x - vertex.x, other.y - vertex.y)
        let amount = min(rounding, length / 2) / length
        return NSPoint(x: vertex.x + (other.x - vertex.x) * amount, y: vertex.y + (other.y - vertex.y) * amount)
    }
    path.move(to: inset(first, toward: last))
    for index in points.indices {
        let point = points[index]
        path.line(to: inset(point, toward: points[(index + points.count - 1) % points.count]))
        path.curve(to: inset(point, toward: points[(index + 1) % points.count]), controlPoint1: point, controlPoint2: point)
    }
    path.close()
    return path
}
func tile() -> NSBezierPath {
    let path = NSBezierPath()
    // An exponent of five gives a continuous corner, with no inset rim or decorative border.
    for step in 0...360 {
        let angle = Double(step) * .pi / 180
        let x = cos(angle), y = sin(angle)
        let point = NSPoint(x: 50 + 42 * CGFloat((x < 0 ? -1 : 1) * pow(abs(x), 0.4)), y: 50 + 42 * CGFloat((y < 0 ? -1 : 1) * pow(abs(y), 0.4)))
        if step == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close()
    return path
}
func drawIcon(_ side: CGFloat, monochrome: Bool = false) {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let scale = AffineTransform(scale: side / 100)
    (scale as NSAffineTransform).concat()
    background.setFill(); tile().fill()
    // Top-down design points become bottom-up AppKit points. The dot and slash share a baseline at y=76.
    let contour = [(59.0, 24.0), (75.0, 24.0), (56.0, 76.0), (40.0, 76.0)].map { NSPoint(x: $0.0, y: 100 - $0.1) }
    slash.setFill(); roundedPolygon(contour, rounding: side <= 32 ? 1.1 : 1.7).fill()
    let dot: NSRect
    let radius: CGFloat
    if side <= 16 {
        // At 16px the dot gets two complete pixels and a clear pixel of air before the slash.
        dot = NSRect(x: 18.75, y: 25, width: 12.5, height: 12.5)
        radius = 1.6
    } else if side <= 32 {
        dot = NSRect(x: 21, y: 24, width: 14, height: 14)
        radius = 2.6
    } else {
        dot = NSRect(x: 22, y: 24, width: 13, height: 13)
        radius = 3
    }
    (monochrome ? slash : origin).setFill()
    NSBezierPath(roundedRect: dot, xRadius: radius, yRadius: radius).fill()
}

func preview(in destination: URL) throws {
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    func save(_ image: NSBitmapImageRep, _ name: String) throws {
        try writePNG(image, to: destination.appendingPathComponent(name))
    }
    for side in [16, 32, 64, 128, 256, 512, 1024] {
        try save(bitmap(side, side) { drawIcon(CGFloat(side)) }, "current-\(side).png")
    }
    try save(bitmap(1024, 1024) { drawIcon(1024, monochrome: true) }, "current-monochrome.png")
    try save(bitmap(1200, 700) {
        for row in 0...1 {
            let baseline: CGFloat = CGFloat(row) * 350
            (row == 0 ? rgb(0xF8F8F5) : rgb(0x202927)).setFill()
            NSRect(x: 0, y: baseline, width: 1200, height: 350).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: row == 0 ? rgb(0x65736A) : rgb(0xA8B5AE)]
            NSString(string: row == 0 ? "LIGHT SURFACE" : "DARK SURFACE").draw(at: NSPoint(x: 32, y: baseline + 315), withAttributes: attributes)
            for (index, side) in [16, 32, 64, 128, 192].enumerated() {
                let center = CGFloat(index) * 225 + 124
                NSGraphicsContext.saveGraphicsState()
                let transform = AffineTransform(translationByX: center - CGFloat(side)/2, byY: baseline + 175 - CGFloat(side)/2)
                (transform as NSAffineTransform).concat()
                drawIcon(CGFloat(side))
                NSGraphicsContext.restoreGraphicsState()
                NSString(string: "\(side) px").draw(at: NSPoint(x: center - 18, y: baseline + 50), withAttributes: attributes)
            }
        }
    }, "sizes-light-dark.png")
}

try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
var images: [[String: String]] = []
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let side = points * scale
    let name = "icon_\(points)x\(points)@\(scale)x.png"
    try writePNG(bitmap(side, side) { drawIcon(CGFloat(side)) }, to: iconSet.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: iconSet.appendingPathComponent("Contents.json"))
try writePNG(bitmap(1024, 1024) { drawIcon(1024) }, to: root.appendingPathComponent("Apps/RightHere/icon-1024.png"))
if CommandLine.arguments.count > 1 { try preview(in: URL(fileURLWithPath: CommandLine.arguments[1])) }
print("Generated current-directory icon assets from vector geometry.")
