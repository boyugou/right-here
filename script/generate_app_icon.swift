#!/usr/bin/env swift
//
// Draws the app icon from geometry at each shipped size. No source photograph or raster enlargement.
// Run `swift script/generate_app_icon.swift [preview-directory]` to also compare palettes and small sizes.

import AppKit
import CoreGraphics

struct Palette {
    let name: String
    let tile: NSColor
    let folder: NSColor
    let mark: NSColor
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

let palettes = [
    Palette(name: "Paper", tile: color(244, 241, 233), folder: color(37, 49, 52), mark: color(225, 133, 103)),
    Palette(name: "Ink", tile: color(32, 45, 50), folder: color(174, 196, 187), mark: color(32, 45, 50)),
    Palette(name: "Blue", tile: color(242, 242, 239), folder: color(40, 84, 159), mark: color(248, 245, 235))
]
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconSet = root.appendingPathComponent("Apps/RightHere/Assets.xcassets/AppIcon.appiconset")

enum DrawingError: Error { case bitmap, context, png }

func tilePath() -> NSBezierPath {
    let box = NSRect(x: 100, y: 100, width: 824, height: 824)
    let path = NSBezierPath()
    // A continuous curve keeps the corner transition smooth without a second, decorative frame.
    for step in 0...360 {
        let t = Double(step) / 360 * 2 * .pi
        let c = cos(t), s = sin(t)
        let point = NSPoint(x: box.midX + box.width / 2 * CGFloat((c < 0 ? -1 : 1) * pow(abs(c), 0.4)),
                            y: box.midY + box.height / 2 * CGFloat((s < 0 ? -1 : 1) * pow(abs(s), 0.4)))
        if step == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close()
    return path
}

func folderPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 277, y: 320))
    path.curve(to: NSPoint(x: 232, y: 365), controlPoint1: NSPoint(x: 248, y: 320), controlPoint2: NSPoint(x: 232, y: 336))
    path.line(to: NSPoint(x: 232, y: 660))
    path.curve(to: NSPoint(x: 277, y: 705), controlPoint1: NSPoint(x: 232, y: 689), controlPoint2: NSPoint(x: 248, y: 705))
    path.line(to: NSPoint(x: 400, y: 705))
    path.curve(to: NSPoint(x: 440, y: 688), controlPoint1: NSPoint(x: 420, y: 705), controlPoint2: NSPoint(x: 427, y: 703))
    path.line(to: NSPoint(x: 478, y: 650))
    path.line(to: NSPoint(x: 747, y: 650))
    path.curve(to: NSPoint(x: 792, y: 605), controlPoint1: NSPoint(x: 776, y: 650), controlPoint2: NSPoint(x: 792, y: 634))
    path.line(to: NSPoint(x: 792, y: 365))
    path.curve(to: NSPoint(x: 747, y: 320), controlPoint1: NSPoint(x: 792, y: 336), controlPoint2: NSPoint(x: 776, y: 320))
    path.close()
    return path
}

func drawIcon(side: CGFloat, palette: Palette) {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let transform = AffineTransform(scale: side / 1024)
    (transform as NSAffineTransform).concat()

    let tile = tilePath()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.13)
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.shadowBlurRadius = 18
    shadow.set()
    palette.tile.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    palette.folder.setFill()
    folderPath().fill()

    // A single turn into an arrow: an action taken in this folder. Give small sizes a little more weight.
    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: 410, y: 548))
    mark.line(to: NSPoint(x: 410, y: 474))
    mark.curve(to: NSPoint(x: 435, y: 449), controlPoint1: NSPoint(x: 410, y: 458), controlPoint2: NSPoint(x: 419, y: 449))
    mark.line(to: NSPoint(x: 610, y: 449))
    mark.move(to: NSPoint(x: 560, y: 499))
    mark.line(to: NSPoint(x: 610, y: 449))
    mark.line(to: NSPoint(x: 560, y: 399))
    mark.lineWidth = side <= 32 ? 52 : 44
    mark.lineCapStyle = .round
    mark.lineJoinStyle = .round
    palette.mark.setStroke()
    mark.stroke()
}

func bitmap(width: Int, height: Int, draw: () -> Void) throws -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw DrawingError.bitmap }
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { throw DrawingError.context }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.shouldAntialias = true
    draw()
    return rep
}

func png(_ image: NSBitmapImageRep) throws -> Data {
    guard let data = image.representation(using: .png, properties: [:]) else { throw DrawingError.png }
    return data
}

func icon(side: Int, palette: Palette) throws -> NSBitmapImageRep {
    try bitmap(width: side, height: side) { drawIcon(side: CGFloat(side), palette: palette) }
}

func preview(in directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for palette in palettes {
        for side in [16, 32, 64, 128, 256, 1024] {
            try png(icon(side: side, palette: palette)).write(to: directory.appendingPathComponent("\(palette.name.lowercased())-\(side).png"))
        }
    }
    for dark in [false, true] {
        let sheet = try bitmap(width: 1200, height: 630) {
            (dark ? color(26, 28, 30) : color(250, 249, 246)).setFill()
            NSRect(x: 0, y: 0, width: 1200, height: 630).fill()
            for (index, palette) in palettes.enumerated() {
                let origin = CGFloat(index) * 400
                NSGraphicsContext.saveGraphicsState()
                let transform = AffineTransform(translationByX: origin + 40, byY: 270)
                (transform as NSAffineTransform).concat()
                drawIcon(side: 320, palette: palette)
                NSGraphicsContext.restoreGraphicsState()
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 19, weight: .medium),
                    .foregroundColor: dark ? NSColor.white : color(37, 49, 52)]
                NSString(string: palette.name).draw(at: NSPoint(x: origin + 55, y: 220), withAttributes: attributes)
                for (offset, side) in [16, 32, 64, 128].enumerated() {
                    NSGraphicsContext.saveGraphicsState()
                    let at = AffineTransform(translationByX: origin + 55 + CGFloat(offset) * 75, byY: 45)
                    (at as NSAffineTransform).concat()
                    drawIcon(side: CGFloat(side), palette: palette)
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
        }
        try png(sheet).write(to: directory.appendingPathComponent(dark ? "palettes-dark.png" : "palettes-light.png"))
    }
}

if let palette = palettes.first {
    try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
        let name = "icon_\(points)x\(points)@\(scale)x.png"
        try png(icon(side: points * scale, palette: palette)).write(to: iconSet.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: iconSet.appendingPathComponent("Contents.json"))
    try png(icon(side: 1024, palette: palette)).write(to: root.appendingPathComponent("Apps/RightHere/icon-1024.png"))
}
if CommandLine.arguments.count > 1 { try preview(in: URL(fileURLWithPath: CommandLine.arguments[1])) }
print("Generated app icon assets from vector geometry.")
