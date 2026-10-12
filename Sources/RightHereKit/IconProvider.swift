import AppKit
import Foundation
import RightHereCore

/// Turns a menu `Icon` into an image, remembering the result: loading an application icon is slow
/// enough to make a menu feel sluggish when repeated on every right-click.
public final class IconProvider: @unchecked Sendable {
    private let facts: any SystemFacts
    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]

    public init(facts: any SystemFacts) {
        self.facts = facts
    }

    public func image(for icon: Icon?, side: CGFloat = 16) -> NSImage? {
        guard let icon else { return nil }
        let key = "\(icon.kind.rawValue):\(icon.value):\(side)"
        if let cached = lock.withLock({ cache[key] }) { return cached }
        guard let image = makeImage(icon, side: side) else { return nil }
        lock.withLock { cache[key] = image }
        return image
    }

    private func makeImage(_ icon: Icon, side: CGFloat) -> NSImage? {
        switch icon.kind {
        case .app:
            guard let url = facts.applicationURL(bundleID: icon.value) else { return nil }
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: side, height: side)
            return image
        case .symbol:
            let configuration = NSImage.SymbolConfiguration(pointSize: side - 3, weight: .regular)
            let image = NSImage(systemSymbolName: icon.value, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
            image?.isTemplate = true
            return image
        }
    }
}
