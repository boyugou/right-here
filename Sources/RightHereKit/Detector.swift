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

    /// The subset of `commands` that the login shell can resolve.
    public func commandsFound(_ commands: [String]) async -> Set<String> {
        let shell = facts.loginShell
        let flavor = facts.shellFlavor
        let list = commands.joined(separator: " ")
        let script: String
        let arguments: [String]
        switch flavor {
        case .posix:
            script = "for n in \(list); do command -v \"$n\" >/dev/null 2>&1 && echo \"$n\"; done"
            arguments = ["-lic", script]
        case .fish:
            script = "for n in \(list); command -v $n >/dev/null 2>&1; and echo $n; end"
            arguments = ["-lic", script]
        }
        let result = try? await runner.run(ProcessStep(executable: shell, arguments: arguments), timeout: .seconds(10))
        guard let output = result?.standardOutput else { return [] }
        return Set(output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
    }
}
