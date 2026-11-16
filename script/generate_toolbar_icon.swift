#!/usr/bin/env swift
import CoreGraphics
import Foundation

// The monochrome toolbar mark shares the app icon's original vector geometry.
let output = URL(fileURLWithPath: "Apps/FinderExtension/Assets.xcassets/rh-toolbar.imageset/rh-toolbar.pdf")
var box = CGRect(x: 0, y: 0, width: 20, height: 20)
guard let consumer = CGDataConsumer(url: output as CFURL),
      let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
    fatalError("Cannot create the toolbar icon PDF")
}
context.beginPDFPage(nil)
context.translateBy(x: 0, y: 20)
context.scaleBy(x: 0.2, y: -0.2)
context.setFillColor(CGColor(gray: 0, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 22, y: 63, width: 13, height: 13), cornerWidth: 3, cornerHeight: 3, transform: nil))
context.fillPath()
let slash = CGMutablePath()
slash.move(to: CGPoint(x: 58.416572, y: 25.596750))
slash.addCurve(to: CGPoint(x: 60.7, y: 24), control1: CGPoint(x: 59, y: 24), control2: CGPoint(x: 59, y: 24))
slash.addLine(to: CGPoint(x: 73.3, y: 24))
slash.addCurve(to: CGPoint(x: 74.416572, y: 25.596750), control1: CGPoint(x: 75, y: 24), control2: CGPoint(x: 75, y: 24))
slash.addLine(to: CGPoint(x: 56.583428, y: 74.403250))
slash.addCurve(to: CGPoint(x: 54.3, y: 76), control1: CGPoint(x: 56, y: 76), control2: CGPoint(x: 56, y: 76))
slash.addLine(to: CGPoint(x: 41.7, y: 76))
slash.addCurve(to: CGPoint(x: 40.583428, y: 74.403250), control1: CGPoint(x: 40, y: 76), control2: CGPoint(x: 40, y: 76))
slash.closeSubpath()
context.addPath(slash)
context.fillPath()
context.endPDFPage()
context.closePDF()
