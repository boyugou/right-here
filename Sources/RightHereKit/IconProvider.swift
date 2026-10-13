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

    private func makeImage(_ icon: Icon, side: CGFloat) -> NSImage? {
        switch icon.kind {
        case .app:
            guard let url = facts.applicationURL(bundleID: icon.value) else { return nil }
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: side, height: side)
            return image
        case .fileType:
            guard let type = UTType(filenameExtension: icon.value) else { return nil }
            let image = NSWorkspace.shared.icon(for: type).copy() as? NSImage
            image?.size = NSSize(width: side, height: side)
            return image
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
