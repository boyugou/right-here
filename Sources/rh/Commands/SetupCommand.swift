import ArgumentParser
import Foundation
import RightHereCore
import RightHereKit

/// What a person says they use, as flags: shared by `rh setup` and `rh init`. Each is checked against the terminals, editors and
/// agents Right Here knows, with the closest id offered when one is misspelt.
struct ChoiceOptions: ParsableArguments {
    @Option(help: "The terminal you use, by its id (`rh apps` lists them with their names): ghostty, terminal, iterm, wezterm, kitty, ... Written only when the config file is created.")
    var terminal: String?

    @Option(help: "The editor you use, by its id (`rh apps`): vscode, zed, cursor, ... Written only when the config file is created.")
    var editor: String?

    @Option(help: "The AI agents you use, by their ids separated by commas (claude,codex; `rh agents` lists them), or none for no agent. Written only when the config file is created.")
    var agents: String?

    func choices() throws -> SetupChoices {
        do {
            return try SetupChoices.parse(terminal: terminal, editor: editor, agents: agents)
        } catch {
            throw ValidationError(error.localizedDescription)
        }
    }
}

/// What `rh setup`, `rh init` and `rh install` share: the `rh` they put in place, the app it belongs to, and printing the report.
enum SetupCommandSupport {
    /// The runner for this machine, or why there is none.
    static func runner(systemWide: Bool? = nil) throws -> SetupRunner {
        guard let rhPath = Installer.currentExecutablePath() else { throw Output.fail("error: cannot tell where rh is installed.") }
        let facts = LiveSystemFacts()
        return SetupRunner(facts: facts, rhPath: rhPath, app: HostApp.locate(rhPath: rhPath, facts: facts), systemWide: systemWide)
    }

    static func run(_ request: SetupRequest, with runner: SetupRunner) async throws -> SetupReport {
        // A full run takes seconds, and a terminal that shows nothing for that long looks stuck. The steps go to standard error and only to a terminal:
        // a script or an AI agent that reads the report gets it as it was.
        let showsSteps = !request.dryRun && isatty(STDERR_FILENO) != 0
        do {
            return try await runner.run(request, progress: { phase in
                if showsSteps { FileHandle.standardError.write(Data((phase.englishLine + "\n").utf8)) }
            })
        } catch {
            throw Output.fail("error: \(error.localizedDescription)")
        }
    }

    /// Prints the report as the command line does (`withTitle` is off for the commands that do one piece) and fails when a step did.
    static func finish(_ report: SetupReport, json: Bool, withTitle: Bool = true) throws {
        if json {
            try Output.json(report)
        } else {
            for line in report.english().dropFirst(withTitle ? 0 : 1) { Output.print(line) }
        }
        if !report.ok {
            let failed = report.steps.filter { $0.outcome == .failed }.count
            if report.dryRun {
                Output.error("The dry run found \(failed) problem(s): the steps above that would fail say why. Fix the cause before you run `rh setup`.")
            } else {
                Output.error("Finished with \(failed) problem(s): the steps above that failed say why. Fix the cause and run `rh setup` again; it only does what is still missing.")
            }
            throw ExitCode(1)
        }
    }
}

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Set Right Here up: the config file, the runner script, the command link, the Quick Actions and the Finder extension.",
        discussion: """
        One command that does the whole job, in order, and can be run again at any time: it makes what is missing, changes what is \
        out of date, and leaves what is right as it is, saying which in each line. It ends with the checks of `rh doctor`, the things \
        only you can do (switching the Finder extension on in System Settings; the PATH line for ~/.local/bin; the permission macOS \
        asks for the first time an agent starts in your terminal) and the commands to run next.

        The config file is created from what is installed on this Mac. Say what you use with --terminal, --editor and --agents; \
        that is written only when the file is created. A config that exists is never rewritten: setup lists the line to change \
        instead, and --force is the one way to replace the file (the old one is saved next to it first). A config that exists \
        but cannot be used (it is not TOML, cannot be read, or is a link to a file that is not there) fails that step and is \
        named with its line; no Quick Actions are made from it and no edits are listed for it.

        Setup opens no window and no terminal, and never changes System Settings. --dry-run shows what it would do and changes nothing. \
        With RH_HOME set, every per-user path moves under that folder and what is registered for the whole Mac (the Finder \
        extension) is left alone: a way to try it without touching your own setup.
        """
    )

    @OptionGroup var choices: ChoiceOptions

    @Flag(help: "Replace a config file that exists, after saving it next to itself. Only when you asked to start the config over: without it an existing config is never rewritten.")
    var force = false

    @Flag(name: .customLong("dry-run"), help: "Show what would be done and change nothing.")
    var dryRun = false

    @Flag(help: "Print JSON: steps, what was chosen, config edits that were not applied, warnings, needsUser, next and the doctor's checks.")
    var json = false

    func run() async throws {
        let chosen = try choices.choices()
        let runner = try SetupCommandSupport.runner()
        let report = try await SetupCommandSupport.run(.setup(choices: chosen, force: force, dryRun: dryRun), with: runner)
        try SetupCommandSupport.finish(report, json: json)
    }
}
