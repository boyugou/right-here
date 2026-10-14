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
        abstract: "Pin a folder for quick access in shortcuts and agent prompts."
    )

    @Argument(help: "The folder to pin. Default: current directory.")
    var folder: String?

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        let runtime = Runtime()
        let path: String
        if let folder {
            path = (folder as NSString).expandingTildeInPath
        } else {
            path = runtime.facts.currentDirectory.path
        }
        guard runtime.facts.isDirectory(URL(fileURLWithPath: path)) == true else {
            throw ValidationError("\"\(path)\" is not an existing folder.")
        }
        var state = StateStore.load(paths: runtime.paths)
        let added = state.pin(path)
        try state.save(paths: runtime.paths)

        if json {
            try Output.json(PinResult(ok: true, pinned: path, alreadyPinned: !added))
        } else {
            if added {
                Output.print("pinned: \(path)")
            } else {
                Output.print("already pinned: \(path)")
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
        let path = (folder as NSString).expandingTildeInPath
        var state = StateStore.load(paths: runtime.paths)
        let removed = state.unpin(path)
        try state.save(paths: runtime.paths)

        if json {
            try Output.json(UnpinResult(ok: true, unpinned: path, wasPinned: removed))
        } else {
            if removed {
                Output.print("unpinned: \(path)")
            } else {
                Output.print("not pinned: \(path)")
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
                Output.print(pin)
            }
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
        var state = StateStore.load(paths: runtime.paths)
        if clear {
            state.clearRecents()
            try state.save(paths: runtime.paths)
            if json {
                try Output.json(ClearResult(ok: true, cleared: true))
            } else {
                Output.print("cleared recents")
            }
            return
        }
        if json {
            try Output.json(state.recents)
        } else {
            for recent in state.recents {
                Output.print(recent)
            }
        }
    }
}
