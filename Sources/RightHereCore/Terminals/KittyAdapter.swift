import Foundation

/// kitty: a new window in the folder, or a typed command in the person's login shell. Started through LaunchServices like `WezTermAdapter`
/// (`open -n -b <id> --args ...`) so that `rh run` does not wait for the window to be closed. `terminal_placement` does not apply. Not yet tried
/// with a real kitty; `rh doctor --probe-launch` checks it.
public struct KittyAdapter: TerminalAdapter {
    public let terminalID = "kitty"
    /// The folder is the value of `--directory`, an argument; nothing types it.
    public var typesTheFolder: Bool { false }

    public init() {}

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        let directory = try session.requireDirectory(facts)
        let typed = try session.requireTypeableInput()
        guard facts.applicationURL(bundleID: bundleID) != nil else { throw PlanError.appNotInstalled("kitty") }
        // `-n` starts a separate kitty each time, and kitty stays running on macOS with no window left unless this option says it should not.
        var arguments = ["--directory", directory, "-o", "macos_quit_when_last_window_closed=yes"]
        if let typed {
            arguments += [facts.loginShell, "-lic", typed + "; exec " + ShellQuoting.quote(facts.loginShell, for: .posix) + " -l"]
        }
        return [.run(NewInstance.launch(bundleID: bundleID, arguments: arguments))]
    }
}
