import Foundation

/// Ghostty 1.3 and later, through its AppleScript dictionary.
///
/// A plain "open here" hands the folder to Ghostty, which opens a window in it without any
/// permission prompt. Running a command needs AppleScript: the working directory and an initial
/// input are set on the new surface, so the command is typed into the user's own login shell.
/// PATH, version managers and aliases apply, and the shell stays open afterwards.
public struct GhosttyAdapter: TerminalAdapter {
    public let terminalID = "ghostty"
    public var supportsCommands: Bool { true }

    public init() {}

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        guard let typed = session.typedInput else {
            return [.open(OpenStep(bundleID: bundleID, targets: [session.directory.path]))]
        }
        let placement = session.placement == .newTab ? "tab" : "window"
        return [.appleScript(AppleScriptStep(
            source: Self.script,
            arguments: [session.directory.path, typed, placement],
            controls: "Ghostty"
        ))]
    }

    /// Constant source. The folder, the typed text and the placement arrive only as arguments.
    /// `initial input` is typed into the user's login shell once it is up; the linefeed is Return.
    static let script = """
    on run argv
        set cwd to item 1 of argv
        set typed to item 2 of argv
        set placement to item 3 of argv
        tell application "Ghostty"
            set cfg to new surface configuration
            set initial working directory of cfg to cwd
            if typed is not "" then set initial input of cfg to typed & linefeed
            if placement is "tab" and (count of windows) > 0 then
                new tab in front window with configuration cfg
            else
                new window with configuration cfg
            end if
            activate
        end tell
    end run
    """
}
