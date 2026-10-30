import Foundation

/// Ghostty 1.3 and later, through its AppleScript dictionary.
///
/// A plain "open here" hands the folder to Ghostty, which opens a window in it without any
/// permission prompt. Running a command needs AppleScript: the working directory and an initial
/// input are set on the new surface, so the command is typed into the user's own login shell.
/// PATH, version managers and aliases apply, and the shell stays open afterwards.
public struct GhosttyAdapter: TerminalAdapter {
    public let terminalID = "ghostty"
    /// The folder is an argument of the script (the new surface's working directory); nothing types it.
    public var typesTheFolder: Bool { false }
    public var supportedPlacements: [TerminalPlacement] { TerminalPlacement.allCases }

    /// The first release with an AppleScript dictionary.
    static let firstScriptableVersion = AppVersion("1.3")!

    public init() {}

    public func commandBlocker(bundleID: String, facts: any SystemFacts) -> String? {
        guard let text = facts.bundleVersion(bundleID: bundleID), let version = AppVersion(text), version < Self.firstScriptableVersion else {
            return nil
        }
        return "Ghostty \(version) cannot run commands; Ghostty \(Self.firstScriptableVersion) or later can. Update Ghostty or choose another terminal."
    }

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        let directory = try session.requireDirectory(facts)
        let typed = try session.requireTypeableInput()
        // Handing Ghostty a folder always opens a window, and needs no permission. A new tab, or a command,
        // is done through its AppleScript dictionary (Ghostty 1.3 and later).
        if typed == nil, session.placement == .newWindow {
            return [.open(OpenStep(bundleID: bundleID, targets: [directory]))]
        }
        if let blocker = commandBlocker(bundleID: bundleID, facts: facts) { throw PlanError.unsupported(blocker) }
        let placement = session.placement.configName
        return [.appleScript(AppleScriptStep(
            source: Self.script,
            arguments: [directory, typed ?? "", placement],
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
            if placement is "split-right" and (count of windows) > 0 then
                set currTab to selected tab of front window
                split (focused terminal of currTab) direction right with configuration cfg
            else if placement is "split-down" and (count of windows) > 0 then
                set currTab to selected tab of front window
                split (focused terminal of currTab) direction down with configuration cfg
            else if placement is "tab" and (count of windows) > 0 then
                new tab in front window with configuration cfg
            else
                new window with configuration cfg
            end if
            activate
        end tell
    end run
    """
}
