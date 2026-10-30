import Foundation

/// A terminal started the way its config entry says (`open_args`, `run_args`): an argument vector with `{dir}`,
/// `{command}`, `{shell}` and `{app}` replaced inside its elements. This is how a terminal without a built-in adapter
/// (WezTerm, kitty, Alacritty, ...) can start agents without waiting for one to be written and tried on a machine that
/// has it. Nothing goes through a shell unless the template itself says so, and then the template is the person's own.
///
/// The folder is checked to be a folder, and the typed command to be typeable, exactly as for the built-in adapters.
public struct TemplateTerminalAdapter: TerminalAdapter {
    public let terminalID: String
    public let displayName: String
    private let launch: TerminalLaunch

    private var noRunArgs: String { "\(displayName) has no run_args in the config, so it cannot start a command. Add run_args, or choose another terminal for this agent." }
    public var commandRefusal: String? { launch.run == nil ? noRunArgs : nil }

    public init(terminalID: String, displayName: String, launch: TerminalLaunch) {
        self.terminalID = terminalID
        self.displayName = displayName
        self.launch = launch
    }

    /// Whether a template's first element can name a program: absolute, or relative to the installed app.
    public static func isValidExecutable(_ element: String) -> Bool {
        element.hasPrefix("/") || element.hasPrefix("{app}/")
    }

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        let directory = try session.requireDirectory(facts)
        let typed = try session.requireTypeableInput()
        let template: [String]
        if typed != nil {
            guard let run = launch.run else { throw PlanError.unsupported(noRunArgs) }
            template = run
        } else if let open = launch.open {
            template = open
        } else {
            return [.open(OpenStep(bundleID: bundleID, targets: [directory]))]
        }
        guard let program = template.first, Self.isValidExecutable(program) else {
            throw PlanError.unsupported("The first element of \(displayName)'s launch arguments must be an absolute path or start with {app}/.")
        }
        let appPath = facts.applicationURL(bundleID: bundleID)?.path ?? ""
        if template.joined().contains("{app}"), appPath.isEmpty { throw PlanError.appNotInstalled(displayName) }
        let replacements = ["{dir}": directory, "{command}": typed ?? "", "{shell}": facts.loginShell, "{app}": appPath]
        let argv = template.map { Self.expand($0, replacements) }
        return [.run(ProcessStep(executable: argv[0], arguments: Array(argv.dropFirst())))]
    }

    /// One pass over the template: only a placeholder that is in the template is replaced, never text that arrived with
    /// a replacement (a folder called `{command}` stays a folder called `{command}`).
    static func expand(_ element: String, _ replacements: [String: String]) -> String {
        var result = ""
        var rest = Substring(element)
        scan: while !rest.isEmpty {
            for (placeholder, value) in replacements where rest.hasPrefix(placeholder) {
                result += value
                rest = rest.dropFirst(placeholder.count)
                continue scan
            }
            result.append(rest.removeFirst())
        }
        return result
    }
}
