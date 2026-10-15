import Foundation
import RightHereCore

/// What the person's login shell says about their environment, which is what a new terminal window sees: which of some
/// commands it finds, and its `PATH`.
public struct LoginShellFacts: Sendable, Equatable {
    /// The commands it resolved, among those it was asked about.
    public var found: Set<String>
    /// The folders of its `PATH`, in order; `nil` when it was not asked, or did not answer.
    public var path: [String]?

    public init(found: Set<String> = [], path: [String]? = nil) {
        self.found = found
        self.path = path
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
        let defaults = DefaultApps(config: .default, facts: facts)
        let terminal = try? defaults.resolve(role: .terminal, configured: nil)
        let editor = try? defaults.resolve(role: .editor, configured: nil)
        let found = await commandsFound(KnownAgents.all.map(\.command))
        let agents = KnownAgents.all.filter { found.contains($0.command) }.map(\.id)
        return DetectedEnvironment(terminal: terminal?.id, editor: editor?.id, agents: agents)
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
        case .posix:
            script = "for n in \"$@\"; do command -v -- \"$n\" >/dev/null 2>&1 && printf '%s\\n' \"$n\"; done"
                + (wantPath ? "; printf '\\001rh-path\\001%s\\n' \"$PATH\"" : "")
        case .fish:
            script = "for n in $argv; command -v -- $n >/dev/null 2>&1; and echo $n; end"
                + (wantPath ? "; printf '\\001rh-path\\001%s\\n' (string join : $PATH)" : "")
        }
        // With `-c`, a POSIX shell takes the first operand as `$0`; fish has no such slot.
        let operands = facts.shellFlavor == .posix ? ["rh-detect"] + commands : commands
        let result = try? await runner.run(ProcessStep(executable: facts.loginShell, arguments: ["-lic", script] + operands), timeout: .seconds(10))
        guard let output = result?.standardOutput else { return LoginShellFacts() }
        return Self.parse(output)
    }

    static let pathMarker = "\u{01}rh-path\u{01}"

    static func parse(_ output: String) -> LoginShellFacts {
        var found: Set<String> = []
        var path: [String]?
        for line in output.split(separator: "\n") {
            if line.hasPrefix(pathMarker) {
                path = line.dropFirst(pathMarker.count).split(separator: ":", omittingEmptySubsequences: true).map(String.init)
            } else {
                found.insert(line.trimmingCharacters(in: .whitespaces))
            }
        }
        return LoginShellFacts(found: found, path: path)
    }
}
