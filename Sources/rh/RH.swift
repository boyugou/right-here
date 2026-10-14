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
        every action. Run one with `rh run <action> [folder]`, for example `rh run copy-path.absolute ~/Projects`. \
        Everything is also available as JSON (--json) for scripts and agents.
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
    static let version = "0.2.0"
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
    var defaults: DefaultApps { DefaultApps(config: config, facts: facts) }

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

    @Argument(help: "Files or folders to act on. Without any, the folder given by --container, or the current directory, is used. Put -- before a path that starts with a dash.")
    var paths: [String] = []

    func makeContext(facts: any SystemFacts) throws -> HereContext {
        let input = ContextInput(origin: origin, paths: paths, container: container, resolution: .relative(to: facts.currentDirectory))
        do {
            return try input.makeContext(hasLinkBeforeDotDot: PathHazard.linkBeforeDotDot)
        } catch ContextInput.Problem.dotDotAfterLink(let path) {
            throw ValidationError("\"\(path)\" has `..` after a symbolic link, which the file system reads differently from the text. Give the folder's real path instead.")
        } catch ContextInput.Problem.emptyPath {
            // An empty argument is most often an unset shell variable (`rh run reveal "$DIR"`); acting on the current
            // directory instead would be a surprise.
            throw ValidationError("An empty path was given (is a shell variable unset?). Leave the path out to use the current directory.")
        } catch ContextInput.Problem.unknownOrigin(let name) {
            throw ValidationError("Unknown origin \"\(name)\". Use one of: " + HereContext.Origin.allCases.map(\.rawValue).joined(separator: ", "))
        } catch ContextInput.Problem.containsNUL {
            throw ValidationError("A path cannot contain a NUL character.")
        }
    }
}
