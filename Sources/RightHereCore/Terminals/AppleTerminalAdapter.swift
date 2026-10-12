import Foundation

/// Terminal.app. Handing it a folder opens a window in that folder; running a command uses
/// `do script`, which types the line into the user's own login shell.
public struct AppleTerminalAdapter: TerminalAdapter {
    public let terminalID = "terminal"
    public var supportsCommands: Bool { true }
    public var typesTheFolder: Bool { true }

    public init() {}

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        let directory = try session.requireDirectory(facts)
        guard let typed = try session.requireTypeableInput() else {
            return [.open(OpenStep(bundleID: bundleID, targets: [directory]))]
        }
        // The folder is typed after `cd`, so it is held to the same rule as the command.
        do { try ShellQuoting.validateForTyping(directory) } catch { throw PlanError.unsafeText(directory) }
        // The line is read by whichever shell the Terminal profile starts: the account's login shell unless
        // the profile names a command, and nothing here can tell which. POSIX single quotes are read the same
        // way by sh, bash, zsh and fish with one exception: fish takes a backslash inside them as an escape,
        // so `\'` ends the quoting in sh and not in fish. A folder name with a backslash is therefore
        // refused rather than quoted for a guessed shell, and every other name is quoted the one way all of
        // them agree on. (Quoting it for the login shell, as this used to, breaks as soon as the profile runs
        // a different one.) AppleScript's `quoted form of` is not used for the same reason.
        if directory.unicodeScalars.contains("\\") {
            throw PlanError.unsupported("Terminal types the folder into a shell, and shells disagree about a backslash in a name, so it will not start a command in \(directory). Rename the folder, or use a terminal that is handed the folder, such as Ghostty.")
        }
        let line = "cd " + ShellQuoting.quote(directory, for: .posix) + " && " + typed
        return [.appleScript(AppleScriptStep(source: Self.script, arguments: [line], controls: "Terminal"))]
    }

    /// Constant source. The whole line to type arrives as an argument, already quoted and checked.
    static let script = """
    on run argv
        tell application "Terminal"
            activate
            do script (item 1 of argv)
        end tell
    end run
    """
}
