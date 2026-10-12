import Foundation

/// Terminal.app. Handing it a folder opens a window in that folder; running a command uses
/// `do script`, which types the line into the user's own login shell.
public struct AppleTerminalAdapter: TerminalAdapter {
    public let terminalID = "terminal"
    public var supportsCommands: Bool { true }

    public init() {}

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        let directory = try session.requireDirectory(facts)
        guard let typed = try session.requireTypeableInput() else {
            return [.open(OpenStep(bundleID: bundleID, targets: [directory]))]
        }
        // The folder is typed after `cd`, so it is held to the same rule as the command.
        do { try ShellQuoting.validateForTyping(directory) } catch { throw PlanError.unsafeText(directory) }
        // The line is built here, quoted for the person's own login shell: AppleScript's `quoted form of`
        // is POSIX quoting, which fish reads differently (it treats a backslash inside single quotes as an
        // escape), so a folder name with a backslash next to a quote could break out of it.
        let line = "cd " + ShellQuoting.quote(directory, for: facts.shellFlavor) + " && " + typed
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
