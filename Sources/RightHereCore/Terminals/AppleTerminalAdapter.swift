import Foundation

/// Terminal.app. Handing it a folder opens a window in that folder; running a command uses
/// `do script`, which types the line into the user's own login shell.
public struct AppleTerminalAdapter: TerminalAdapter {
    public let terminalID = "terminal"
    public var typesTheFolder: Bool { true }

    public init() {}

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        let directory = try session.requireDirectory(facts)
        guard let typed = try session.requireTypeableInput() else {
            return [.open(OpenStep(bundleID: bundleID, targets: [directory]))]
        }
        // The folder is typed after `cd`, so it is held to the same rule as the command.
        do { try ShellQuoting.validateForTyping(directory) } catch { throw PlanError.unsafeFolder(directory) }
        // The line is read by whichever shell the Terminal profile starts: the account's login shell unless the profile names a command, and
        // nothing here can tell which. `quoteTyped` writes a word the way every shell reads the same (POSIX shells, fish, tcsh, nushell, elvish,
        // PowerShell); a backslash cannot be written so, and a folder name with one is refused rather than quoted for a guessed shell. Quoting
        // for the login shell, as this used to, breaks as soon as the profile runs a different one, and AppleScript's `quoted form of` is not
        // used for the same reason.
        guard let folder = ShellQuoting.quoteTyped(directory) else {
            throw PlanError.refused(.refusalTypesFolderBackslash("Terminal", directory))
        }
        let line = "cd " + folder + " && " + typed
        try TerminalSession.requireFitsANewTTY(line, terminal: "Terminal")
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
