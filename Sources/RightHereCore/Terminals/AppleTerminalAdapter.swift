import Foundation

/// Terminal.app. Handing it a folder opens a window in that folder; running a command uses
/// `do script`, which types the line into the user's own login shell.
public struct AppleTerminalAdapter: TerminalAdapter {
    public let terminalID = "terminal"
    public var supportsCommands: Bool { true }

    public init() {}

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        guard let typed = session.typedInput else {
            return [.open(OpenStep(bundleID: bundleID, targets: [try session.requireDirectory(facts)]))]
        }
        return [.appleScript(AppleScriptStep(
            source: Self.script,
            arguments: [session.directory.path, typed],
            controls: "Terminal"
        ))]
    }

    /// Constant source. `quoted form of` quotes the folder for the shell; the caller has already
    /// refused folders containing line breaks or control characters.
    static let script = """
    on run argv
        set cwd to item 1 of argv
        set typed to item 2 of argv
        tell application "Terminal"
            activate
            do script ("cd " & quoted form of cwd & " && " & typed)
        end tell
    end run
    """
}
