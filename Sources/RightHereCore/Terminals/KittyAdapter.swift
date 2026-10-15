import Foundation

/// kitty terminal adapter.
///
/// Starts a new session or runs a typed command in kitty via its bundled CLI executable
/// (`{app}/Contents/MacOS/kitty`).
public struct KittyAdapter: TerminalAdapter {
    public let terminalID = "kitty"
    /// The folder is the value of `--directory`, an argument; nothing types it.
    public var typesTheFolder: Bool { false }

    public init() {}

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        let directory = try session.requireDirectory(facts)
        let typed = try session.requireTypeableInput()
        guard let appURL = facts.applicationURL(bundleID: bundleID) else {
            throw PlanError.appNotInstalled("kitty")
        }
        let executable = appURL.appendingPathComponent("Contents/MacOS/kitty").path
        if let typed {
            let shell = facts.loginShell
            let arguments = ["--directory", directory, shell, "-lic", "\(typed); exec \(shell) -l"]
            return [.run(ProcessStep(executable: executable, arguments: arguments))]
        } else {
            return [.run(ProcessStep(executable: executable, arguments: ["--directory", directory]))]
        }
    }
}
