import Foundation

/// WezTerm terminal adapter.
///
/// Starts a new session or runs a typed command in WezTerm via its bundled CLI executable
/// (`{app}/Contents/MacOS/wezterm`).
public struct WezTermAdapter: TerminalAdapter {
    public let terminalID = "wezterm"
    /// The folder is the value of `--cwd`, an argument; nothing types it.
    public var typesTheFolder: Bool { false }

    public init() {}

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        let directory = try session.requireDirectory(facts)
        let typed = try session.requireTypeableInput()
        guard let appURL = facts.applicationURL(bundleID: bundleID) else {
            throw PlanError.appNotInstalled("WezTerm")
        }
        let executable = appURL.appendingPathComponent("Contents/MacOS/wezterm").path
        if let typed {
            let shell = facts.loginShell
            let arguments = ["start", "--cwd", directory, "--", shell, "-lic", "\(typed); exec \(shell) -l"]
            return [.run(ProcessStep(executable: executable, arguments: arguments))]
        } else {
            return [.run(ProcessStep(executable: executable, arguments: ["start", "--cwd", directory]))]
        }
    }
}
