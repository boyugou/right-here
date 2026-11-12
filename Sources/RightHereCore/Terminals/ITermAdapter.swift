import Foundation

/// iTerm2 3.0 and later, through its AppleScript dictionary.
///
/// A plain "open here" in a window hands the folder to iTerm, which opens a window in it without
/// any permission prompt. Running a command, or opening a new tab, uses AppleScript to target the
/// session and type the command into the user's interactive login shell.
public struct ITermAdapter: TerminalAdapter {
    public let terminalID = "iterm"
    public var typesTheFolder: Bool { true }
    public var supportedPlacements: [TerminalPlacement] { TerminalPlacement.allCases }

    /// iTerm2 3.0 introduced the modern AppleScript object model (windows, tabs, sessions, write text).
    static let firstScriptableVersion = AppVersion("3.0")!

    public init() {}

    public func commandBlocker(bundleID: String, facts: any SystemFacts) -> LocalizedMessage? {
        guard let text = facts.bundleVersion(bundleID: bundleID), let version = AppVersion(text), version < Self.firstScriptableVersion else {
            return nil
        }
        return .refusalTerminalTooOld("iTerm", "\(version)", "\(Self.firstScriptableVersion)")
    }

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        let directory = try session.requireDirectory(facts)
        let typed = try session.requireTypeableInput()
        // Handing iTerm a folder opens a window, and needs no permission. A new tab, or a command,
        // is done through its AppleScript dictionary.
        if typed == nil, session.placement == .newWindow {
            return [.open(OpenStep(bundleID: bundleID, targets: [directory]))]
        }
        if let blocker = commandBlocker(bundleID: bundleID, facts: facts) { throw PlanError.refused(blocker) }
        // The folder is typed after `cd`, so it is held to the same rule as the command.
        do { try ShellQuoting.validateForTyping(directory) } catch { throw PlanError.unsafeFolder(directory) }
        // `quoteTyped` refuses only a backslash here: the control characters were refused above.
        guard let folder = ShellQuoting.quoteTyped(directory) else {
            throw PlanError.refused(.refusalTypesFolderBackslash("iTerm", directory))
        }
        let quotedDir = "cd " + folder
        let line: String
        if let typed {
            line = quotedDir + " && " + typed
        } else {
            line = quotedDir
        }
        try TerminalSession.requireFitsANewTTY(line, terminal: "iTerm")
        let placement = session.placement.configName
        return [.appleScript(AppleScriptStep(
            source: Self.script,
            arguments: [line, placement],
            controls: "iTerm"
        ))]
    }

    /// Constant source. The whole line to type and the placement arrive only as arguments.
    /// `write text` types into the user's login shell and sends a newline. Each branch types into the session of what its command returned
    /// (iTerm2's scripting documentation: `create tab` returns the new tab, which it does not say becomes the current one).
    static let script = """
    on run argv
        set line to item 1 of argv
        set placement to item 2 of argv
        tell application id "com.googlecode.iterm2"
            if placement is "split-right" and (count of windows) > 0 then
                tell current session of current window
                    set newSession to (split vertically with default profile)
                    tell newSession to write text line
                end tell
            else if placement is "split-down" and (count of windows) > 0 then
                tell current session of current window
                    set newSession to (split horizontally with default profile)
                    tell newSession to write text line
                end tell
            else if placement is "tab" and (count of windows) > 0 then
                tell current window
                    set newTab to (create tab with default profile)
                    tell current session of newTab
                        write text line
                    end tell
                end tell
            else
                set targetWindow to (create window with default profile)
                tell current session of targetWindow
                    write text line
                end tell
            end if
            activate
        end tell
    end run
    """
}
