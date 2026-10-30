import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

struct PinResult: Encodable {
    var ok: Bool
    var pinned: String
    var alreadyPinned: Bool
}

struct UnpinResult: Encodable {
    var ok: Bool
    var unpinned: String
    var wasPinned: Bool
}

struct ClearResult: Encodable {
    var ok: Bool
    var cleared: Bool
}

struct Pin: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Pin a folder: it is listed by `rh pins`, in the setup window and by the MCP tool right_here_bookmarks."
    )

    @Argument(help: "The folder to pin. Default: current directory.")
    var folder: String?

    /// `~` expanded, a relative path resolved against `base`, `.` and `..` removed.
    static func absolute(_ path: String, from base: URL) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, relativeTo: base).standardizedFileURL.path
    }

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        let runtime = Runtime()
        // A pin is an absolute path: `rh pin .` must still name the folder after the shell has moved on.
        let path = Pin.absolute(folder ?? ".", from: runtime.facts.currentDirectory)
        guard runtime.facts.isDirectory(URL(fileURLWithPath: path)) == true else {
            throw ValidationError("\"\(path.withControlCharactersEscaped)\" is not an existing folder.")
        }
        let added = try StateStore.update(paths: runtime.paths) { $0.pin(path) }

        if json {
            try Output.json(PinResult(ok: true, pinned: path, alreadyPinned: !added))
        } else {
            if added {
                Output.print("pinned: \(path.withControlCharactersEscaped)")
            } else {
                Output.print("already pinned: \(path.withControlCharactersEscaped)")
            }
        }
    }
}

struct Unpin: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Unpin a folder."
    )

    @Argument(help: "The folder to unpin.")
    var folder: String

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        let runtime = Runtime()
        let path = Pin.absolute(folder, from: runtime.facts.currentDirectory)
        let removed = try StateStore.update(paths: runtime.paths) { $0.unpin(path) }

        if json {
            try Output.json(UnpinResult(ok: true, unpinned: path, wasPinned: removed))
        } else {
            if removed {
                Output.print("unpinned: \(path.withControlCharactersEscaped)")
            } else {
                Output.print("not pinned: \(path.withControlCharactersEscaped)")
            }
        }
    }
}

struct Pins: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List pinned folders."
    )

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        let runtime = Runtime()
        let state = StateStore.load(paths: runtime.paths)
        if json {
            try Output.json(state.pins)
        } else {
            for pin in state.pins {
                // A folder name may hold a line break, and the file that keeps the pins can be written by any program: one line for each pin.
                Output.print(pin.withControlCharactersEscaped)
            }
            // On standard error, so a script that reads the folders gets nothing and a person at a terminal is told why.
            if state.pins.isEmpty { Output.error("No pinned folders yet. Pin one with `rh pin <folder>`.") }
        }
    }
}

struct Recents: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List recent folders used with Right Here."
    )

    @Flag(help: "Clear recent folders.")
    var clear = false

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        let runtime = Runtime()
        if clear {
            try StateStore.update(paths: runtime.paths) { $0.clearRecents() }
            if json {
                try Output.json(ClearResult(ok: true, cleared: true))
            } else {
                Output.print("cleared recents")
            }
            return
        }
        let state = StateStore.load(paths: runtime.paths)
        if json {
            try Output.json(state.recents)
        } else {
            for recent in state.recents {
                Output.print(recent.withControlCharactersEscaped)
            }
            if state.recents.isEmpty { Output.error("No recent folders yet. They are remembered when an action starts from Finder or with `rh run`.") }
        }
    }
}
