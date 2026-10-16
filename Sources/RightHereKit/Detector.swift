import Foundation
import RightHereCore

/// What the person's login shell says about their environment, which is what a new terminal window sees: which of some
/// commands it finds, and its `PATH`.
public struct LoginShellFacts: Sendable, Equatable {
    /// The commands it resolved, among those it was asked about.
    public var found: Set<String>
    /// The folders of its `PATH`, in order; `nil` when it was not asked, or did not answer.
    public var path: [String]?
    /// Whether the shell ran the script to its end. A startup file that exits, or a shell that takes longer than the limit, leaves this `false`, and what it found is then
    /// what it did not say, and not what is not there.
    public var answered: Bool

    public init(found: Set<String> = [], path: [String]? = nil, answered: Bool = false) {
        self.found = found
        self.path = path
        self.answered = answered
    }
}

/// Finds what is installed: terminals and editors through LaunchServices, agent commands through
/// the user's own login shell, so version-manager paths and aliases count.
public struct Detector: Sendable {
    private let facts: any SystemFacts
    private let runner: any ProcessRunner

    public init(facts: any SystemFacts = LiveSystemFacts(), runner: any ProcessRunner = LiveProcessRunner()) {
        self.facts = facts
        self.runner = runner
    }

    public func detect() async -> DetectedEnvironment {
        await look().environment
    }

    /// What `detect` finds, and whether the login shell answered: an agent that was not found because the shell said nothing is not an agent that is not installed.
    public func look() async -> (environment: DetectedEnvironment, shellAnswered: Bool) {
        let defaults = DefaultApps(config: .default, facts: facts)
        let terminal = try? defaults.resolve(role: .terminal, configured: nil)
        let editor = try? defaults.resolve(role: .editor, configured: nil)
        let shell = await probe(commands: KnownAgents.all.map(\.command))
        let agents = KnownAgents.all.filter { shell.found.contains($0.command) }.map(\.id)
        return (DetectedEnvironment(terminal: terminal?.id, editor: editor?.id, agents: agents), shell.answered)
    }

    /// The subset of `commands` that the login shell can resolve. The names travel as arguments of the
    /// script (`$@` or `$argv`), never as part of its text, so a command from the config cannot be read
    /// as shell syntax.
    public func commandsFound(_ commands: [String]) async -> Set<String> {
        await probe(commands: commands).found
    }

    /// What the login shell says, in one start of it: which of `commands` it resolves and, with `wantPath`, its `PATH`. A
    /// graphical app has the `PATH` launchd gives it (`/usr/bin:/bin:/usr/sbin:/sbin`), and so has a program an AI assistant
    /// starts, so neither can tell whether a folder is on the `PATH` of a new terminal window; the shell can.
    public func probe(commands: [String], wantPath: Bool = false) async -> LoginShellFacts {
        guard !commands.isEmpty || wantPath else { return LoginShellFacts() }
        // The line that carries the PATH starts with two control characters that no command name and no startup message has, so
        // nothing a command is called can pass for it. The names never become part of the script.
        let script: String
        switch facts.shellFlavor {
        // Every line starts with a line feed of its own: a startup file that printed a word without ending the line would otherwise be glued to the first of them.
        case .posix:
            script = "for n in \"$@\"; do command -v -- \"$n\" >/dev/null 2>&1 && printf '\\n%s\\n' \"$n\"; done"
                + (wantPath ? "; printf '\\n\\001rh-path\\001%s\\n' \"$PATH\"" : "") + "; printf '\\n\\001rh-done\\001\\n'"
        case .fish:
            script = "for n in $argv; command -v -- $n >/dev/null 2>&1; and printf '\\n%s\\n' $n; end"
                + (wantPath ? "; printf '\\n\\001rh-path\\001%s\\n' (string join : $PATH)" : "") + "; printf '\\n\\001rh-done\\001\\n'"
        }
        // With `-c`, a POSIX shell takes the first operand as `$0`; fish has no such slot.
        let operands = facts.shellFlavor == .posix ? ["rh-detect"] + commands : commands
        let result = try? await runner.run(ProcessStep(executable: facts.loginShell, arguments: ["-lic", script] + operands), timeout: .seconds(10))
        guard let output = result?.standardOutput else { return LoginShellFacts() }
        var shell = Self.parse(output)
        // What the startup files printed is in the output too: only a name that was asked about can be an answer.
        shell.found.formIntersection(commands)
        return shell
    }

    static let pathMarker = "\u{01}rh-path\u{01}"
    /// The last line of what the script prints: its absence says the shell did not get to the end.
    static let doneMarker = "\u{01}rh-done\u{01}"

    static func parse(_ output: String) -> LoginShellFacts {
        var found: Set<String> = []
        var path: [String]?
        var answered = false
        for line in output.split(separator: "\n") {
            if line == doneMarker {
                answered = true
            } else if line.hasPrefix(pathMarker) {
                path = line.dropFirst(pathMarker.count).split(separator: ":", omittingEmptySubsequences: true).map(String.init)
            } else {
                found.insert(line.trimmingCharacters(in: .whitespaces))
            }
        }
        return LoginShellFacts(found: found, path: path, answered: answered)
    }
}
