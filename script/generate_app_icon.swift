#!/usr/bin/env swift
//
// Draws the Right Here app icon: a folder with a location pin standing in it ("act on the folder you are
// looking at, right here"). Two blues for the folder, one orange for the pin.
//
// Writes, deterministically:
//   Apps/RightHere/Assets.xcassets/AppIcon.appiconset   full-bleed art; macOS 26 masks it into the rounded square itself
//   Apps/RightHere/icon-1024.png                        the same art on the macOS icon grid (824 pt squircle, shadow), for the website and README
//
//   swift script/generate_app_icon.swift [preview-dir]
//
// With a preview directory it also writes 16, 32, 128 and 1024 px full-bleed renders there for review.

import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appendingPathComponent("Apps/RightHere/Assets.xcassets")
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset")
let exportURL = root.appendingPathComponent("Apps/RightHere/icon-1024.png")

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func shadowed(_ shadowColor: NSColor, dy: CGFloat, blur: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = shadowColor
    shadow.shadowOffset = NSSize(width: 0, height: dy)
    shadow.shadowBlurRadius = blur
    shadow.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

/// The folder: a lighter back panel with a tab, and a white front panel that the pin stands in.
func drawFolder() {
    let left: CGFloat = 120, width: CGFloat = 784
    let backRect = NSRect(x: left, y: 236, width: width, height: 490)
    let tab = NSBezierPath()
    tab.move(to: NSPoint(x: left, y: 660))
    tab.line(to: NSPoint(x: left, y: 724))
    tab.curve(to: NSPoint(x: left + 58, y: 784), controlPoint1: NSPoint(x: left, y: 758), controlPoint2: NSPoint(x: left + 26, y: 784))
    tab.line(to: NSPoint(x: left + 262, y: 784))
    tab.curve(to: NSPoint(x: left + 322, y: 752), controlPoint1: NSPoint(x: left + 292, y: 784), controlPoint2: NSPoint(x: left + 302, y: 770))
    tab.line(to: NSPoint(x: left + 346, y: 726))
    tab.line(to: NSPoint(x: left + 346, y: 660))
    tab.close()
    let back = NSBezierPath(roundedRect: backRect, xRadius: 70, yRadius: 70)
    back.append(tab)
    shadowed(color(0x050B3A, alpha: 0.35), dy: -26, blur: 50) { color(0x6F8FFF).setFill(); back.fill() }
    NSGradient(colors: [color(0xA9BEFF), color(0x6F8FFF)])!.draw(in: back, angle: -90)

    let frontRect = NSRect(x: left, y: 196, width: width, height: 430)
    let front = NSBezierPath(roundedRect: frontRect, xRadius: 70, yRadius: 70)
    shadowed(color(0x050B3A, alpha: 0.32), dy: -20, blur: 38) { color(0xFFFFFF).setFill(); front.fill() }
    NSGradient(colors: [color(0xFFFFFF), color(0xD9E4FA)])!.draw(in: front, angle: -90)
}

/// The pin: a circle and a tip, with a round hole, in orange. It overlaps the folder's back panel so it reads as standing in it.
func drawPin() {
    let center = NSPoint(x: 512, y: 574), radius: CGFloat = 176, tipY: CGFloat = 292, hole: CGFloat = 66

    // The spot it marks, flat on the front panel.
    let spot = NSRect(x: 512 - 150, y: tipY - 38, width: 300, height: 76)
    color(0x2F6BF2, alpha: 0.16).setFill()
    NSBezierPath(ovalIn: spot).fill()
    color(0x2F6BF2, alpha: 0.5).setStroke()
    let ring = NSBezierPath(ovalIn: spot.insetBy(dx: 4, dy: 4))
    ring.lineWidth = 9
    ring.stroke()

    let tangent = acos(radius / (center.y - tipY)) * 180 / .pi
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: radius, startAngle: -90 + tangent, endAngle: 270 - tangent)
    path.line(to: NSPoint(x: center.x, y: tipY))
    path.close()
    path.append(NSBezierPath(ovalIn: NSRect(x: center.x - hole, y: center.y - hole, width: hole * 2, height: hole * 2)).reversed)
    path.windingRule = .evenOdd
    shadowed(color(0x3A1200, alpha: 0.45), dy: -16, blur: 30) { color(0xFF8A1F).setFill(); path.fill() }
    NSGradient(colors: [color(0xFF8A1F), color(0xFFB43A)])!.draw(in: path, angle: -90)
}

/// Full-bleed art on a 1024-point canvas.
func drawArt() {
    let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    NSGradient(colors: [color(0x2A2FD6), color(0x2F6BF2), color(0x3FB4FF)], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!.draw(in: canvas, angle: -90)
    NSGradient(colors: [color(0xFFFFFF, alpha: 0.22), color(0xFFFFFF, alpha: 0)])!
        .draw(fromCenter: NSPoint(x: 300, y: 960), radius: 0, toCenter: NSPoint(x: 300, y: 960), radius: 760, options: [])
    drawFolder()
    drawPin()
}

/// The macOS icon grid: an 824-point continuous-corner square centred on 1024, with the soft drop shadow.
func drawGridIcon() {
    let box = NSRect(x: 100, y: 100, width: 824, height: 824)
    let exponent = 5.0
    let squircle = NSBezierPath()
    let steps = 360
    for step in 0...steps {
        let t = Double(step) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = box.midX + box.width / 2 * CGFloat(c.magnitude == 0 ? 0 : (c < 0 ? -1 : 1) * pow(c.magnitude, 2 / exponent))
        let y = box.midY + box.height / 2 * CGFloat(s.magnitude == 0 ? 0 : (s < 0 ? -1 : 1) * pow(s.magnitude, 2 / exponent))
        step == 0 ? squircle.move(to: NSPoint(x: x, y: y)) : squircle.line(to: NSPoint(x: x, y: y))
    }
    squircle.close()
    shadowed(color(0x000000, alpha: 0.30), dy: -14, blur: 28) { color(0x2F6BF2).setFill(); squircle.fill() }
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let transform = NSAffineTransform()
    transform.translateX(by: box.minX, yBy: box.minY)
    transform.scale(by: box.width / 1024)
    transform.concat()
    drawArt()
    NSGraphicsContext.restoreGraphicsState()
    // A hairline inner highlight, the way system icons catch light on their top edge.
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    color(0xFFFFFF, alpha: 0.35).setStroke()
    squircle.lineWidth = 3
    squircle.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

func bitmap(side: Int, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(side) / 1024)
    transform.concat()
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }

try? FileManager.default.removeItem(at: iconSet)
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
try Data(#"{ "info" : { "author" : "xcode", "version" : 1 } }"#.utf8).write(to: catalog.appendingPathComponent("Contents.json"))

var images: [[String: String]] = []
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(points)x\(points)@\(scale)x.png"
    try png(bitmap(side: points * scale, drawArt)).write(to: iconSet.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: iconSet.appendingPathComponent("Contents.json"))

try png(bitmap(side: 1024, drawGridIcon)).write(to: exportURL)

if CommandLine.arguments.count > 1 {
    let preview = URL(fileURLWithPath: CommandLine.arguments[1])
    try FileManager.default.createDirectory(at: preview, withIntermediateDirectories: true)
    for side in [16, 32, 128, 1024] {
        try png(bitmap(side: side, drawArt)).write(to: preview.appendingPathComponent("bleed_\(side).png"))
        try png(bitmap(side: side, drawGridIcon)).write(to: preview.appendingPathComponent("grid_\(side).png"))
    }
}
print("wrote \(iconSet.path)")
