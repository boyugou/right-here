import AppKit
import Foundation
import RightHereCore
import Synchronization
import UniformTypeIdentifiers

/// Turns a menu `Icon` into an image, remembering the result: loading an application icon is slow
/// enough to make a menu feel sluggish when repeated on every right-click.
public final class IconProvider: Sendable {
    /// The dedicated template icons (Apps/FinderExtension/Assets.xcassets, drawn by script/generate_menu_icons.swift),
    /// keyed by the SF Symbol name an `Icon` carries. A symbol without an entry is drawn from the system set.
    public static let dedicatedGlyphs: [String: String] = [
        "doc.badge.plus": "rh-new-file",
        "doc.on.doc": "rh-copy-path",
        "ellipsis.circle": "rh-more-agents",
        "magnifyingglass": "rh-reveal",
        "terminal": "rh-terminal",
        "chevron.left.forwardslash.chevron.right": "rh-editor",
        "arrow.up.forward.app": "rh-open-with",
    ]

    /// The glyph of the button that Finder's toolbar can show: the app's pin and prompt in lines, in the same catalog.
    public static let toolbarGlyph = "rh-toolbar"

    private let facts: any SystemFacts
    private let cache = Mutex<[String: NSImage]>([:])

    public init(facts: any SystemFacts) {
        self.facts = facts
    }

    public func image(for icon: Icon?, side: CGFloat = 16) -> NSImage? {
        guard let icon else { return nil }
        let key = "\(icon.kind.rawValue):\(icon.value):\(side)"
        if let cached = cache.withLock({ $0[key] }) { return cached }
        guard let image = makeImage(icon, side: side) else { return nil }
        cache.withLock { $0[key] = image }
        return image
    }

    /// Pre-renders and caches a batch of icons ahead of time, avoiding main-thread disk I/O when opening a menu.
    public func prewarm(_ icons: [Icon], side: CGFloat = 16) {
        for icon in icons {
            _ = image(for: icon, side: side)
        }
    }

    /// The icon as one bitmap, three pixels to the point. An image from `NSWorkspace` holds every size of the icon (an app's has about thirty, tens of megabytes), and a
    /// menu is sent to Finder with its images: measured, three menu items with such icons took 560 ms and 210 MB to archive, and the same three as one bitmap each
    /// took 2 ms and 30 KB. A menu that showed its entries a second after the click, as reported on macOS 26.5.1, was that.
    static func flattened(_ image: NSImage, side: CGFloat) -> NSImage {
        let pixels = Int((side * 3).rounded(.up))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else {
            image.size = NSSize(width: side, height: side)
            return image
        }
        // The context counts in pixels, whatever size the representation is given afterwards: drawn into `side` points it fills a third of the bitmap.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        rep.size = NSSize(width: side, height: side)
        let flat = NSImage(size: NSSize(width: side, height: side))
        flat.addRepresentation(rep)
        flat.isTemplate = image.isTemplate
        return flat
    }

    private func makeImage(_ icon: Icon, side: CGFloat) -> NSImage? {
        switch icon.kind {
        case .app:
            guard let url = facts.applicationURL(bundleID: icon.value) else { return nil }
            return Self.flattened(NSWorkspace.shared.icon(forFile: url.path), side: side)
        case .fileType:
            guard let type = UTType(filenameExtension: icon.value) else { return nil }
            return Self.flattened(NSWorkspace.shared.icon(for: type), side: side)
        case .symbol:
            // The app and the Finder extension carry the catalog (project.yml); any other process falls through to the system symbol.
            if let glyph = Self.dedicatedGlyphs[icon.value], let image = NSImage(named: NSImage.Name(glyph))?.copy() as? NSImage {
                image.size = NSSize(width: side, height: side)
                image.isTemplate = true
                return image
            }
            let configuration = NSImage.SymbolConfiguration(pointSize: side - 3, weight: .regular)
            let image = NSImage(systemSymbolName: icon.value, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
            image?.isTemplate = true
            return image
        }
    }
}
