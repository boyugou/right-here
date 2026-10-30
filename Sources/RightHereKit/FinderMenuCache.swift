import Foundation
import RightHereCore

/// The folder menus the Finder extension has built, by kind, and what each was built from (ADR 0027). The extension holds one, and only its main queue touches it.
///
/// A click builds the menu it is asked for when none can be served; a warmup, which runs when the extension starts and again when a menu that is served has grown old, builds the menus
/// for every kind without a click waiting for it.
public struct FinderMenuCache<Menu> {
    public struct Entry {
        public var stamp: ConfigStore.Stamp
        public var builtAt: Date
        public var menu: Menu
    }

    /// The kinds a warmup builds: every menu that a click on a folder can ask for, the toolbar's included (a menu that is never built again is served for ever, old).
    public static var kinds: [FinderMenuKind] { [.items, .container, .sidebar, .toolbar] }

    private var entries: [FinderMenuKind: Entry] = [:]

    public init() {}

    public subscript(kind: FinderMenuKind) -> Entry? { entries[kind] }

    /// A menu built for a click.
    public mutating func store(_ menu: Menu, kind: FinderMenuKind, stamp: ConfigStore.Stamp, now: Date) {
        entries[kind] = Entry(stamp: stamp, builtAt: now, menu: menu)
    }

    /// What a warmup found. A warmup that found no menu (every app of the menu is gone) leaves none served: the menus that were built are not what a click would build now.
    /// A menu that a click built after the warmup began, from a config that changed meanwhile, is newer than what the warmup read, and the warmup does not put its own over it.
    public mutating func storeWarmup(hasMenu: Bool, stamp: ConfigStore.Stamp, startedAt: Date, now: Date, make: (FinderMenuKind) -> Menu) {
        guard hasMenu else {
            entries.removeAll()
            return
        }
        for kind in Self.kinds {
            if let existing = entries[kind], existing.builtAt >= startedAt, existing.stamp != stamp { continue }
            entries[kind] = Entry(stamp: stamp, builtAt: now, menu: make(kind))
        }
    }
}
