#!/usr/bin/env swift
//
// Generates the Right Here app icon: a premium dark frosted-glass folder with a luminous
// cyan/violet targeting reticle and terminal prompt (`>_`) in an Apple-spec metallic squircle.
//
// Writes, deterministically:
//   Apps/RightHere/Assets.xcassets/AppIcon.appiconset   all macOS standard resolutions (16 to 512 pt @ 1x/2x)
//   Apps/RightHere/icon-1024.png                        1024 px grid icon with shadow, for docs, README, and installer
//
//   swift script/generate_app_icon.swift [preview-dir]

import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let masterIconURL = root.appendingPathComponent("Apps/RightHere/master-icon.jpg")
let catalog = root.appendingPathComponent("Apps/RightHere/Assets.xcassets")
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset")
let exportURL = root.appendingPathComponent("Apps/RightHere/icon-1024.png")

guard let masterImage = NSImage(contentsOf: masterIconURL) else {
    FileHandle.standardError.write(Data("error: master icon not found at \(masterIconURL.path)\n".utf8))
    exit(1)
}
masterImage.size = NSSize(width: 1024, height: 1024)

// The squircle outer boundary in master-icon.jpg is centered at (512, 512) and spans 684x684.
let sourceCropRect = NSRect(x: 170, y: 170, width: 684, height: 684)

func drawSquircleIcon(in canvasSize: CGFloat = 1024) {
    let scale = canvasSize / 1024.0
    let box = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
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

    // Soft drop shadow
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.40)
    shadow.shadowOffset = NSSize(width: 0, height: -14 * scale)
    shadow.shadowBlurRadius = 24 * scale
    shadow.set()
    NSColor.black.setFill()
    squircle.fill()

    // Draw the master icon artwork inside the squircle
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSShadow().set() // remove shadow for inner content
    masterImage.draw(in: box, from: sourceCropRect, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    // Subtle hairline top highlight matching Apple HIG
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSColor(white: 1.0, alpha: 0.25).setStroke()
    squircle.lineWidth = max(1, 2 * scale)
    squircle.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

func bitmap(side: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawSquircleIcon(in: CGFloat(side))
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
    let side = points * scale
    try png(bitmap(side: side)).write(to: iconSet.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: iconSet.appendingPathComponent("Contents.json"))

// Export the master 1024 icon
try png(bitmap(side: 1024)).write(to: exportURL)

if CommandLine.arguments.count > 1 {
    let preview = URL(fileURLWithPath: CommandLine.arguments[1])
    try FileManager.default.createDirectory(at: preview, withIntermediateDirectories: true)
    for side in [16, 32, 128, 1024] {
        try png(bitmap(side: side)).write(to: preview.appendingPathComponent("icon_\(side).png"))
    }
}
print("Generated new premium AppIcon assets in \(iconSet.path)")
