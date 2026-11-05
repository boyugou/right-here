import Foundation

/// The kinds of menu Finder asks a Finder Sync extension for.
public enum FinderMenuKind: String, Sendable, Codable, CaseIterable {
    /// Right-click on selected items.
    case items
    /// Right-click on the empty background of a folder window.
    case container
    case sidebar
    /// The toolbar button.
    case toolbar
}

extension HereContext {
    /// Builds the context from what Finder reports while a menu is built or handled.
    ///
    /// For a background menu Finder still reports a selection: in column view it is the folder
    /// selected in the previous column. The folder that was clicked is `targetedURL`, so the
    /// selection is ignored there.
    ///
    /// Only file URLs are taken: the path of another kind (`smb://server/Users`) reads as a folder of this Mac (`/Users`).
    public static func finder(kind: FinderMenuKind, selected all: [URL], targeted any: URL?) -> HereContext {
        let selected = all.filter(\.isFileURL)
        let targeted = any.flatMap { $0.isFileURL ? $0 : nil }
        switch kind {
        case .items:
            return HereContext(origin: .items, items: selected, container: targeted)
        case .container:
            return HereContext(origin: .container, container: targeted ?? selected.first)
        case .sidebar:
            return HereContext(origin: .sidebar, container: targeted ?? selected.first)
        case .toolbar:
            if selected.isEmpty { return HereContext(origin: .toolbar, container: targeted) }
            return HereContext(origin: .toolbar, items: selected, container: targeted)
        }
    }
}
