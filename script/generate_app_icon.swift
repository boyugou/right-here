#!/usr/bin/env swift
//
// Draws the Right Here app icon and writes the asset catalog:
//   Apps/RightHere/Assets.xcassets/AppIcon.appiconset
//
// The art is full-bleed: macOS 26 masks app icons into the rounded square itself.
//   swift script/generate_app_icon.swift

import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appendingPathComponent("Apps/RightHere/Assets.xcassets")
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset")

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Draws the icon into the current graphics context on a 1024-point canvas.
func drawIcon() {
    let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)

    // Background: indigo to sky blue, with a soft glow in the upper left.
    NSGradient(colors: [color(0x4B3FE0), color(0x2F7BF6), color(0x35B8FF)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: canvas, angle: -50)
    NSGradient(colors: [color(0xFFFFFF, alpha: 0.30), color(0xFFFFFF, alpha: 0)])!
        .draw(fromCenter: NSPoint(x: 210, y: 880), radius: 0, toCenter: NSPoint(x: 210, y: 880), radius: 720, options: [])

    // The context-menu card, a little up and to the left so the pointer has room.
    let card = NSRect(x: 168, y: 292, width: 580, height: 560)
    NSGraphicsContext.saveGraphicsState()
    let cardShadow = NSShadow()
    cardShadow.shadowColor = color(0x0A1A5C, alpha: 0.42)
    cardShadow.shadowOffset = NSSize(width: 0, height: -28)
    cardShadow.shadowBlurRadius = 64
    cardShadow.set()
    color(0xFFFFFF).setFill()
    NSBezierPath(roundedRect: card, xRadius: 76, yRadius: 76).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Three rows centred in the card; the middle one is highlighted.
    let rows: [(offset: CGFloat, barWidth: CGFloat, highlighted: Bool)] = [(150, 300, false), (0, 290, true), (-150, 220, false)]
    for row in rows {
        let centerY = card.midY + row.offset
        if row.highlighted {
            color(0x2F7BF6).setFill()
            NSBezierPath(roundedRect: NSRect(x: card.minX + 38, y: centerY - 56, width: card.width - 76, height: 112), xRadius: 40, yRadius: 40).fill()
        }
        let tint = row.highlighted ? color(0xFFFFFF) : color(0xB7C3DA)
        tint.setFill()
        NSBezierPath(ovalIn: NSRect(x: card.minX + 84, y: centerY - 26, width: 52, height: 52)).fill()
        NSBezierPath(roundedRect: NSRect(x: card.minX + 168, y: centerY - 17, width: row.barWidth, height: 34), xRadius: 17, yRadius: 17).fill()
    }

    // The pointer, drawn once: white with a dark outline and a soft shadow, over the card's lower right.
    let tip = NSPoint(x: 590, y: 488)
    let outline: [(CGFloat, CGFloat)] = [(0, 0), (0, -262), (64, -202), (114, -312), (166, -288), (116, -180), (200, -180)]
    let pointer = NSBezierPath()
    for (index, point) in outline.enumerated() {
        let p = NSPoint(x: tip.x + point.0 * 1.12, y: tip.y + point.1 * 1.12)
        index == 0 ? pointer.move(to: p) : pointer.line(to: p)
    }
    pointer.close()
    pointer.lineJoinStyle = .round
    pointer.lineWidth = 24

    NSGraphicsContext.saveGraphicsState()
    let pointerShadow = NSShadow()
    pointerShadow.shadowColor = color(0x0A1A5C, alpha: 0.5)
    pointerShadow.shadowOffset = NSSize(width: 0, height: -16)
    pointerShadow.shadowBlurRadius = 30
    pointerShadow.set()
    color(0x101828).setStroke()
    pointer.stroke()
    NSGraphicsContext.restoreGraphicsState()
    color(0xFFFFFF).setFill()
    pointer.fill()
    color(0x101828).setStroke()
    pointer.stroke()
    color(0xFFFFFF).setFill()
    pointer.fill()
}

func bitmap(side: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(side) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try? FileManager.default.removeItem(at: iconSet)
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
try Data(#"{ "info" : { "author" : "xcode", "version" : 1 } }"#.utf8).write(to: catalog.appendingPathComponent("Contents.json"))

var images: [[String: String]] = []
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let name = "icon_\(points)x\(points)@\(scale)x.png"
    let data = bitmap(side: pixels).representation(using: .png, properties: [:])!
    try data.write(to: iconSet.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: iconSet.appendingPathComponent("Contents.json"))

// A large preview for review, outside the catalog.
if CommandLine.arguments.count > 1 {
    try bitmap(side: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print("wrote \(iconSet.path)")
