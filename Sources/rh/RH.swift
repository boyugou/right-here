import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

@main
struct RH: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rh",
        abstract: "Send a folder or a Finder selection to your terminals, editors and AI agents.",
        discussion: """
        rh runs actions: copy a path in the form you need, open a folder in a terminal or editor, \
        start an AI agent there, or create a new file. The Finder menu runs the same actions.

        Start with `rh init`, then `rh menu` to preview the Finder menu and `rh actions` to list \
        every action. Everything is also available as JSON (--json) for scripts and agents.
        """,
        version: RightHereInfo.version,
        subcommands: [
            Run.self, Actions.self, MenuCommand.self, Agents.self, Apps.self,
            ConfigCommand.self, Init.self, Install.self, Uninstall.self, Docs.self, Doctor.self,
            FinderCommand.self, MCP.self, Probe.self
        ]
    )
}

enum RightHereInfo {
    static let version = "0.1.0"
}

/// Everything a command needs: the live machine and the loaded config.
struct Runtime {
    let facts = LiveSystemFacts()
    let paths: RHPaths
    let loaded: LoadedConfig

    init() {
        paths = RHPaths.current(facts: facts)
        loaded = ConfigStore.load(paths: paths)
    }

    var config: Config { loaded.config }
    var planner: Planner { Planner(config: config, facts: facts) }

    /// Prints config problems to standard error. The valid parts of the config still apply.
    func reportConfigProblems() {
        for diagnostic in loaded.result.diagnostics {
            Output.error(diagnostic.summary(file: loaded.file))
        }
    }
}

enum Output {
    static func print(_ text: String) {
        Swift.print(text)
    }

    static func error(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    /// Prints the message to standard error and returns the exit status to throw.
    static func fail(_ message: String) -> ExitCode {
        error(message)
        return ExitCode(1)
    }

    static func json(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        Swift.print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
}

/// Paths and options that describe what was pointed at, shared by `run` and `menu`.
struct ContextOptions: ParsableArguments {
    @Option(help: "Where the request came from: items, container, sidebar, toolbar, services or cli. Chosen automatically when omitted.")
    var origin: String?

    @Option(help: "The folder being viewed, when acting on its empty background.")
    var container: String?

    @Argument(help: "Files or folders to act on. Without any, the folder given by --container, or the current directory, is used.")
    var paths: [String] = []

    func makeContext(facts: any SystemFacts) throws -> HereContext {
        func resolve(_ path: String) -> URL {
            URL(fileURLWithPath: (path as NSString).expandingTildeInPath, relativeTo: facts.currentDirectory).lexicallyNormalized
        }
        let items = paths.map(resolve)
        let folder = container.map(resolve)
        let chosen: HereContext.Origin
        if let origin {
            guard let parsed = HereContext.Origin(rawValue: origin) else {
                throw ValidationError("Unknown origin \"\(origin)\". Use one of: " + HereContext.Origin.allCases.map(\.rawValue).joined(separator: ", "))
            }
            chosen = parsed
        } else {
            chosen = items.isEmpty ? (folder == nil ? .cli : .container) : .items
        }
        return HereContext(origin: chosen, items: items, container: folder)
    }
}
