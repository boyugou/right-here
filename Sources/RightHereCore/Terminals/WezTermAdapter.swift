import Foundation

/// WezTerm: a new window in the folder, or a typed command in the person's login shell.
///
/// The terminal is started through LaunchServices (`open -n -b <id> --args ...`), which returns at once. Running the terminal's own binary
/// instead would make `rh run` wait for the window to be closed, and the MCP server's time limit would kill the terminal after two minutes.
/// `terminal_placement` does not apply: this opens a new window, unless the person's config says `prefer_to_spawn_tabs` and a WezTerm is already
/// running (then it is a tab). The flags are the ones its documentation gives (`start --cwd`, and the program after `--`); it has not yet been tried
/// with a real WezTerm, and `rh doctor --probe-launch` is how a person checks theirs.
public struct WezTermAdapter: TerminalAdapter {
    public let terminalID = "wezterm"
    /// The folder is the value of `--cwd`, an argument; nothing types it.
    public var typesTheFolder: Bool { false }

    public init() {}

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        let directory = try session.requireDirectory(facts)
        let typed = try session.requireTypeableInput()
        guard facts.applicationURL(bundleID: bundleID) != nil else { throw PlanError.appNotInstalled("WezTerm") }
        var arguments = ["start", "--cwd", directory]
        if let typed {
            arguments += ["--", facts.loginShell, "-lic", typed + "; exec " + ShellQuoting.quote(facts.loginShell, for: .posix) + " -l"]
        }
        return [.run(NewInstance.launch(bundleID: bundleID, arguments: arguments))]
    }
}

/// How terminals that take their orders as command-line arguments are started without waiting for them.
enum NewInstance {
    static func launch(bundleID: String, arguments: [String]) -> ProcessStep {
        ProcessStep(executable: "/usr/bin/open", arguments: ["-n", "-b", bundleID, "--args"] + arguments)
    }
}
