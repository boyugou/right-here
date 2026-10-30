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

        Start with `rh setup` (it writes the config and connects Finder, and says what only you can do), then `rh menu` (it previews \
        the Finder menu) and `rh doctor` (it checks the setup). `rh docs start` has the steps. `rh actions` lists every action; run one with \
        `rh run <action> [folder]`, for example `rh run copy-path.absolute ~/Projects`. Everything is also available as JSON \
        (--json) for scripts and agents.
        """,
        version: AppIdentity.version,
        subcommands: [
            Run.self, Actions.self, MenuCommand.self, Agents.self, Apps.self,
            Pin.self, Unpin.self, Pins.self, Recents.self, WorktreeCommand.self,
            ConfigCommand.self, Setup.self, Init.self, Install.self, Uninstall.self, Docs.self, Doctor.self,
            FinderCommand.self, MCP.self, Probe.self
        ]
    )

    /// Looks at the environment and at the command line before ArgumentParser reads it: a variable that moves Right Here's files and is set
    /// to nothing (`RHEnvironment`), a misspelt command, or an argument with a dash that would be read as an option (`InvocationCheck`) is
    /// said in one line with status 64, instead of acting on the real folders or printing the whole help with status 0.
    static func main() async {
        if let problem = RHEnvironment.problem(in: ProcessInfo.processInfo.environment) {
            Output.error("error: " + problem)
            Darwin.exit(64)
        }
        let arguments = Array(CommandLine.arguments.dropFirst())
        if let problem = InvocationCheck.problem(arguments, commands: configuration.subcommands.map { $0._commandName }) {
            Output.error("error: " + problem)
            Darwin.exit(64)
        }
        // What ArgumentParser's `main` does, except that an error is printed here, through `Output`: its own message quotes what was typed or what a command found (an unknown
        // topic, a path with `..` after a link, an app that is not there), and a name in it must not act on the terminal either.
        do {
            var command = try parseAsRoot(arguments)
            if var asyncCommand = command as? any AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            let code = exitCode(for: error)
            let message = fullMessage(for: error)
            if !message.isEmpty { code == .success ? Output.print(message) : Output.error(message) }
            Darwin.exit(code.rawValue)
        }
    }
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
    var defaults: DefaultApps { DefaultApps(config: config, facts: facts) }

    /// Prints config problems to standard error. The valid parts of the config still apply.
    func reportConfigProblems() {
        for diagnostic in loaded.result.diagnostics {
            Output.error(diagnostic.summary(file: loaded.file))
        }
    }
}

enum Output {
    /// What goes to a terminal: its control characters, and the ones that draw nothing, are shown as escapes. A line feed and a tab stay, since a line is
    /// what a command prints and a table is made of tabs and spaces. Every line the command line prints goes through here, so a name from a file, a config or git
    /// cannot act on the terminal or forge a line of what a command says, whichever command prints it.
    static func safe(_ text: String) -> String {
        text.escapingControlCharacters(keeping: ["\n", "\t"])
    }

    /// A person at a terminal reads the output as it is, so the marks that tell an AI agent which words are data (ADR 0020, `Fence`) are taken off when standard output is a
    /// terminal: `rh setup` would otherwise print "⟦user⟧Ghostty⟦/user⟧" to the person who runs it first. A pipe, a file and the JSON (`json`) keep them, which is where an agent
    /// reads. The name inside is still shown with its control characters as escapes.
    static func forTheReader(_ text: String, isTerminal: Bool = isatty(STDOUT_FILENO) != 0) -> String {
        isTerminal ? Fence.withoutMarks(text) : text
    }

    static func print(_ text: String) {
        Swift.print(safe(forTheReader(text)))
    }

    static func error(_ text: String) {
        FileHandle.standardError.write(Data((safe(text) + "\n").utf8))
    }

    /// The text padded with spaces to a column `width` characters wide. `String.padding(toLength:)` cuts a longer text off,
    /// which dropped the end of a long name or id (and an escaped name is longer than it looks); here it is kept whole and
    /// two spaces keep it apart from the next column.
    static func column(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + "  " : text + String(repeating: " ", count: width - text.count)
    }

    /// Prints the message to standard error and returns the exit status to throw.
    static func fail(_ message: String) -> ExitCode {
        error(message)
        return ExitCode(1)
    }

    /// JSON is what an AI agent is told to read, so what a check quotes from the config is fenced in its `text` (`DoctorCheck.encode`). A value is printed as it is, but
    /// a character that a terminal acts on or that draws nothing (a C1 control, a bidirectional mark, a tag character) is written as the JSON escape, which a JSON
    /// reader reads back as the same character.
    static func json(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.userInfo[.fencesQuotedText] = true
        Swift.print(String(decoding: try encoder.encode(value), as: UTF8.self).escapingControlCharacters(keeping: ["\n"]))
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
