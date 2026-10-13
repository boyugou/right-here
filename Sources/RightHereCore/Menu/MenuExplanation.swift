import Foundation

/// One thing about a menu that its reader would otherwise have to guess: an entry the config asked for that is not there, or
/// one that is there with another app than the config named.
public struct MenuNote: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        /// The config asks for the entry and the menu does not show it.
        case leftOut
        /// The menu shows the entry, with another app than the config chose.
        case changed
    }

    public var kind: Kind
    /// The entry as the menu writes it ("Open in Zed", "Agent Presets"), or the group of entries.
    public var entry: String
    /// Why, in the planner's own words (English), so that `rh run`, `rh actions` and the menu say one thing.
    public var reason: String

    public init(kind: Kind, entry: String, reason: String) {
        self.kind = kind
        self.entry = entry
        self.reason = reason
    }

    public var line: String { "\(entry): \(reason)" }
}

/// A menu and what it leaves out or changes. `MenuBuilder.explain` builds both at once, so the account cannot disagree with
/// the menu.
public struct MenuExplanation: Sendable, Equatable, Codable {
    public var menu: [MenuNode]
    public var notes: [MenuNote]

    public init(menu: [MenuNode], notes: [MenuNote]) {
        self.menu = menu
        self.notes = notes
    }

    public var leftOut: [MenuNote] { notes.filter { $0.kind == .leftOut } }
    public var changed: [MenuNote] { notes.filter { $0.kind == .changed } }

    /// The menu is empty and the notes say why, as one line for a place that has room for one sentence (a config check).
    public var emptyMenuSummary: String? {
        guard menu.isEmpty else { return nil }
        // Each line is a sentence; strung together they need no full stops of their own.
        let reasons = leftOut.map { $0.line.hasSuffix(".") ? String($0.line.dropLast()) : $0.line }.joined(separator: "; ")
        return "the Finder menu would be empty for a folder" + (reasons.isEmpty ? "" : ": " + reasons)
    }
}

/// Collects the notes while a menu is built for `explain`. A menu built without one (the Finder extension's) skips all of it.
final class MenuNoteCollector {
    private(set) var notes: [MenuNote] = []
    /// The config as the shared file alone makes it, and the name of the per-machine overlay: an agent that is enabled there and
    /// not here was disabled by the overlay, which `Config` does not record.
    let shared: Config?
    let overlayName: String

    init(shared: Config?, overlayName: String) {
        self.shared = shared
        self.overlayName = overlayName
    }

    func leftOut(_ entry: String, _ reason: String?) {
        add(MenuNote(kind: .leftOut, entry: entry, reason: reason ?? "it cannot run here."))
    }

    func changed(_ entry: String, _ reason: String) {
        add(MenuNote(kind: .changed, entry: entry, reason: reason))
    }

    private func add(_ note: MenuNote) {
        // The same sentence about the same app is said once, whichever entry it came up under.
        if !notes.contains(where: { $0.kind == note.kind && $0.reason == note.reason && ($0.entry == note.entry || note.kind == .changed) }) {
            notes.append(note)
        }
    }
}
