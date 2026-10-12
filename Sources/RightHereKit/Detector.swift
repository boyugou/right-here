import Foundation
import RightHereCore

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
        let planner = Planner(config: .default, facts: facts)
        let terminal = try? planner.resolveDefault(role: .terminal, configured: nil)
        let editor = try? planner.resolveDefault(role: .editor, configured: nil)
        let found = await commandsFound(KnownAgents.all.map(\.command))
        let agents = KnownAgents.all.filter { found.contains($0.command) }.map(\.id)
        return DetectedEnvironment(terminal: terminal?.id, editor: editor?.id, agents: agents)
    }

    /// The subset of `commands` that the login shell can resolve. The names travel as arguments of the
    /// script (`$@` or `$argv`), never as part of its text, so a command from the config cannot be read
    /// as shell syntax.
    public func commandsFound(_ commands: [String]) async -> Set<String> {
        guard !commands.isEmpty else { return [] }
        let script: String
        switch facts.shellFlavor {
        case .posix:
            script = "for n in \"$@\"; do command -v -- \"$n\" >/dev/null 2>&1 && printf '%s\\n' \"$n\"; done"
        case .fish:
            script = "for n in $argv; command -v -- $n >/dev/null 2>&1; and echo $n; end"
        }
        // With `-c`, a POSIX shell takes the first operand as `$0`; fish has no such slot.
        let operands = facts.shellFlavor == .posix ? ["rh-detect"] + commands : commands
        let result = try? await runner.run(ProcessStep(executable: facts.loginShell, arguments: ["-lic", script] + operands), timeout: .seconds(10))
        guard let output = result?.standardOutput else { return [] }
        return Set(output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
    }
}
