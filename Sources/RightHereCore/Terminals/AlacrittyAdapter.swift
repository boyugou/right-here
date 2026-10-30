import Foundation

/// Alacritty: a new window in the folder, or a typed command in the person's login shell. Started through LaunchServices like `WezTermAdapter`
/// (`open -n -b <id> --args ...`) so that `rh run` does not wait for the window to be closed. `terminal_placement` does not apply. The flags
/// are the ones its man page documents (`--working-directory`, and `-e`, which takes the program and must come last); it has not yet been
/// tried on a real Mac, and `rh doctor --probe-launch` checks it. Before this adapter Alacritty was handed
/// the folder with `open`, which it does not declare that it accepts.
public struct AlacrittyAdapter: TerminalAdapter {
    public let terminalID = "alacritty"
    /// The folder is the value of `--working-directory`, an argument; nothing types it.
    public var typesTheFolder: Bool { false }

    public init() {}

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        let directory = try session.requireDirectory(facts)
        let typed = try session.requireTypeableInput()
        guard facts.applicationURL(bundleID: bundleID) != nil else { throw PlanError.appNotInstalled("Alacritty") }
        var arguments = ["--working-directory", directory]
        if let typed {
            arguments += ["-e", facts.loginShell, "-lic", typed + "; exec " + ShellQuoting.quote(facts.loginShell, for: .posix) + " -l"]
        }
        return [.run(NewInstance.launch(bundleID: bundleID, arguments: arguments))]
    }
}
