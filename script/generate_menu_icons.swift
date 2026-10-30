#!/usr/bin/env swift
//
// Draws the Finder menu icons as vector PDFs and writes the asset catalog the Finder extension loads:
//   Apps/FinderExtension/Assets.xcassets/<name>.imageset   (template rendering, vector preserved)
//
// The set is one family: a 16 x 16 pt grid, a 1.25 pt round-capped stroke (the weight of a regular 13 pt SF Symbol),
// 2 to 2.5 pt corner radii, and no fill except for dots. Everything is drawn black; Finder tints a template image.
//
//   swift script/generate_menu_icons.swift [contact-sheet.png]
//
// The optional contact sheet shows the new icons beside the SF Symbols they replace, on light and dark grounds.

import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appendingPathComponent("Apps/FinderExtension/Assets.xcassets")

let stroke: CGFloat = 1.25

/// A polyline with rounded corners; `closed` joins the last point to the first.
func rounded(_ points: [CGPoint], radius: CGFloat, closed: Bool) -> CGPath {
    let path = CGMutablePath()
    let n = points.count
    if closed {
        let start = CGPoint(x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2)
        path.move(to: start)
        for i in 1...n { path.addArc(tangent1End: points[i % n], tangent2End: points[(i + 1) % n], radius: radius) }
        path.closeSubpath()
    } else {
        path.move(to: points[0])
        for i in 1..<(n - 1) { path.addArc(tangent1End: points[i], tangent2End: points[i + 1], radius: radius) }
        path.addLine(to: points[n - 1])
    }
    return path
}

func line(_ ctx: CGContext, _ points: [CGPoint]) {
    ctx.move(to: points[0])
    for p in points.dropFirst() { ctx.addLine(to: p) }
    ctx.strokePath()
}

func ring(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
    ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}

func dot(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}

/// A concave four-point sparkle centred on `c`.
func sparkle(_ c: CGPoint, _ r: CGFloat, pinch: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k = r * pinch
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y + k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + k, y: c.y - k))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y - k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - k, y: c.y + k))
    p.closeSubpath()
    return p
}

struct Glyph {
    let name: String
    let sfSymbol: String
    let draw: (CGContext) -> Void
}

let glyphs: [Glyph] = [
    Glyph(name: "rh-new-file", sfSymbol: "doc.badge.plus") { ctx in
        // A page with a folded corner, and a plus on it.
        ctx.addPath(rounded([CGPoint(x: 3, y: 1.5), CGPoint(x: 3, y: 14.5), CGPoint(x: 9, y: 14.5), CGPoint(x: 13, y: 10.5), CGPoint(x: 13, y: 1.5)], radius: 2, closed: true))
        ctx.strokePath()
        ctx.addPath(rounded([CGPoint(x: 9, y: 14.5), CGPoint(x: 9, y: 10.5), CGPoint(x: 13, y: 10.5)], radius: 1, closed: false))
        ctx.strokePath()
        line(ctx, [CGPoint(x: 8, y: 3.9), CGPoint(x: 8, y: 7.9)])
        line(ctx, [CGPoint(x: 6, y: 5.9), CGPoint(x: 10, y: 5.9)])
    },
    Glyph(name: "rh-copy-path", sfSymbol: "doc.on.doc") { ctx in
        // A route: a start, an end, and the way between them.
        ring(ctx, CGPoint(x: 3.8, y: 3.8), 2.1)
        ring(ctx, CGPoint(x: 12.2, y: 12.2), 2.1)
        ctx.move(to: CGPoint(x: 5.9, y: 3.8))
        ctx.addCurve(to: CGPoint(x: 10.1, y: 12.2), control1: CGPoint(x: 11.2, y: 3.8), control2: CGPoint(x: 4.8, y: 12.2))
        ctx.strokePath()
    },
    Glyph(name: "rh-more-agents", sfSymbol: "ellipsis.circle") { ctx in
        // Two sparkles: the big one outlined, the small one solid.
        ctx.addPath(sparkle(CGPoint(x: 6.6, y: 8.6), 5.6, pinch: 0.16))
        ctx.strokePath()
        ctx.addPath(sparkle(CGPoint(x: 12.6, y: 3.6), 2.6, pinch: 0.2))
        ctx.fillPath()
    },
    Glyph(name: "rh-reveal", sfSymbol: "magnifyingglass") { ctx in
        // A folder with a target dot: the thing you are looking at.
        ctx.addPath(rounded([CGPoint(x: 1.5, y: 2.5), CGPoint(x: 1.5, y: 13), CGPoint(x: 6.2, y: 13), CGPoint(x: 7.8, y: 11), CGPoint(x: 14.5, y: 11), CGPoint(x: 14.5, y: 2.5)], radius: 2, closed: true))
        ctx.strokePath()
        dot(ctx, CGPoint(x: 8, y: 6.7), 1.7)
    },
    Glyph(name: "rh-terminal", sfSymbol: "terminal") { ctx in
        ctx.addPath(CGPath(roundedRect: CGRect(x: 1.5, y: 2.5, width: 13, height: 11), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
        ctx.strokePath()
        ctx.addPath(rounded([CGPoint(x: 4.6, y: 10.2), CGPoint(x: 7.2, y: 8), CGPoint(x: 4.6, y: 5.8)], radius: 0.4, closed: false))
        ctx.strokePath()
        line(ctx, [CGPoint(x: 8.8, y: 5.6), CGPoint(x: 11.6, y: 5.6)])
    },
    Glyph(name: "rh-editor", sfSymbol: "chevron.left.forwardslash.chevron.right") { ctx in
        ctx.addPath(rounded([CGPoint(x: 5.2, y: 11.2), CGPoint(x: 1.6, y: 8), CGPoint(x: 5.2, y: 4.8)], radius: 0.4, closed: false))
        ctx.strokePath()
        ctx.addPath(rounded([CGPoint(x: 10.8, y: 11.2), CGPoint(x: 14.4, y: 8), CGPoint(x: 10.8, y: 4.8)], radius: 0.4, closed: false))
        ctx.strokePath()
        line(ctx, [CGPoint(x: 9.1, y: 13), CGPoint(x: 6.9, y: 3)])
    },
    Glyph(name: "rh-open-with", sfSymbol: "arrow.up.forward.app") { ctx in
        ctx.addPath(rounded([CGPoint(x: 6.5, y: 12), CGPoint(x: 1.5, y: 12), CGPoint(x: 1.5, y: 2), CGPoint(x: 11.5, y: 2), CGPoint(x: 11.5, y: 7)], radius: 2.2, closed: false))
        ctx.strokePath()
        line(ctx, [CGPoint(x: 7, y: 7.5), CGPoint(x: 14, y: 14.5)])
        ctx.addPath(rounded([CGPoint(x: 9.6, y: 14.5), CGPoint(x: 14.4, y: 14.5), CGPoint(x: 14.4, y: 9.7)], radius: 0.4, closed: false))
        ctx.strokePath()
    },
    Glyph(name: "rh-toolbar", sfSymbol: "contextualmenu.and.cursorarrow") { ctx in
        // The app's icon in lines, for the button in Finder's toolbar: the pin of Apps/RightHere/AppIcon.icon and the prompt in it.
        let pin = CGMutablePath()
        pin.move(to: CGPoint(x: 8, y: 1.25))
        pin.addCurve(to: CGPoint(x: 3, y: 9.75), control1: CGPoint(x: 8, y: 1.25), control2: CGPoint(x: 3, y: 5.96))
        pin.addCurve(to: CGPoint(x: 8, y: 14.75), control1: CGPoint(x: 3, y: 12.5), control2: CGPoint(x: 5.23, y: 14.75))
        pin.addCurve(to: CGPoint(x: 13, y: 9.75), control1: CGPoint(x: 10.77, y: 14.75), control2: CGPoint(x: 13, y: 12.5))
        pin.addCurve(to: CGPoint(x: 8, y: 1.25), control1: CGPoint(x: 13, y: 5.96), control2: CGPoint(x: 8, y: 1.25))
        pin.closeSubpath()
        ctx.addPath(pin)
        ctx.strokePath()
        ctx.addPath(rounded([CGPoint(x: 5.7, y: 11.5), CGPoint(x: 7.9, y: 9.75), CGPoint(x: 5.7, y: 8)], radius: 0.4, closed: false))
        ctx.strokePath()
        line(ctx, [CGPoint(x: 9.3, y: 8.1), CGPoint(x: 10.5, y: 8.1)])
    },
]

func configure(_ ctx: CGContext) {
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
}

func pdfData(_ glyph: Glyph) -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 16, height: 16)
    let info: [CFString: Any] = [kCGPDFContextCreator: "Right Here icon generator", kCGPDFContextTitle: glyph.name]
    let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, info as CFDictionary)!
    ctx.beginPDFPage(nil)
    configure(ctx)
    glyph.draw(ctx)
    ctx.endPDFPage()
    ctx.closePDF()
    return data as Data
}

try? FileManager.default.removeItem(at: catalog)
try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
try Data(#"{ "info" : { "author" : "xcode", "version" : 1 } }"#.utf8).write(to: catalog.appendingPathComponent("Contents.json"))
for glyph in glyphs {
    let set = catalog.appendingPathComponent("\(glyph.name).imageset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    try pdfData(glyph).write(to: set.appendingPathComponent("\(glyph.name).pdf"))
    let contents: [String: Any] = [
        "images": [["idiom": "universal", "filename": "\(glyph.name).pdf"]],
        "info": ["author": "xcode", "version": 1],
        "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"],
    ]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: set.appendingPathComponent("Contents.json"))
}

// Contact sheet: columns are the glyphs; rows are old (SF Symbol) and new, each on a light and a dark ground,
// at 1x pixel size (what Finder shows on a standard display) and enlarged 6x.
if CommandLine.arguments.count > 1 {
    let cell = 112, margin = 16
    let width = margin * 2 + cell * glyphs.count
    let rowHeights = [112, 112, 112, 112, 40, 40]
    let height = margin * 2 + rowHeights.reduce(0, +)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    var top = height - margin
    // (ground, ink, scale, new?)
    let rows: [(CGFloat, CGFloat, CGFloat, Bool)] = [(0.97, 0.12, 6, false), (0.97, 0.12, 6, true), (0.16, 0.92, 6, false), (0.16, 0.92, 6, true), (0.97, 0.12, 1, true), (0.16, 0.92, 1, true)]
    for (index, row) in rows.enumerated() {
        let h = rowHeights[index]
        ctx.setFillColor(CGColor(gray: row.0, alpha: 1)); ctx.fill(CGRect(x: margin, y: top - h, width: cell * glyphs.count, height: h))
        for (column, glyph) in glyphs.enumerated() {
            let size = 16 * row.2
            let origin = CGPoint(x: CGFloat(margin + column * cell) + (CGFloat(cell) - size) / 2, y: CGFloat(top) - CGFloat(h) / 2 - size / 2)
            ctx.saveGState()
            ctx.translateBy(x: origin.x, y: origin.y)
            ctx.scaleBy(x: row.2, y: row.2)
            if row.3 {
                configure(ctx)
                ctx.setStrokeColor(CGColor(gray: row.1, alpha: 1)); ctx.setFillColor(CGColor(gray: row.1, alpha: 1))
                glyph.draw(ctx)
            } else if let symbol = NSImage(systemSymbolName: glyph.sfSymbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)) {
                let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                    symbol.draw(in: rect)
                    NSColor(calibratedWhite: row.1, alpha: 1).set()
                    rect.fill(using: .sourceIn)
                    return true
                }
                tinted.draw(in: CGRect(x: 0, y: 0, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1)
            }
            ctx.restoreGState()
        }
        top -= h
    }
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print("wrote \(catalog.path)")
