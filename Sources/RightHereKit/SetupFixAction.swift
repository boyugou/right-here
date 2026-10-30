import Foundation
import RightHereCore

/// What the setup window can do about a check itself, from a button under its fix: the doctor's fix is a sentence for a terminal ("Run `rh setup`",
/// "set general.terminal"), and in the window the thing it names is a button or a page away.
public enum SetupFixAction: Sendable, Equatable {
    case repair
    case extensionSettings
    /// The page of the window where the setting the fix names is changed.
    case page(SetupTab)
    /// Show the copies of the app other than the one to keep in Finder, to move them to the Trash.
    case revealOtherCopies

    /// `nil` when the window has nothing better than the sentence. On the first run the way in is Set Up on the first page, not Install or Repair.
    public init?(fix: LocalizedMessage, firstRun: Bool) {
        switch fix.key {
        case .doctorFixRunSetup, .doctorFixExtensionInstall, .doctorFixExtensionClean:
            if firstRun { return nil }
            self = .repair
        case .doctorFixExtensionEnable: self = .extensionSettings
        case .doctorFixPending, .doctorFixConfigErrors, .doctorFixConfigWarnings: self = .page(.config)
        case .doctorFixTerminal, .doctorFixTerminalFallback, .doctorFixEditor, .doctorFixEditorFallback: self = .page(.overview)
        case .doctorFixAgentRemove, .doctorFixAgentsAdd, .doctorFixAgentLauncher: self = .page(.agents)
        case .doctorFixAppCopies: self = .revealOtherCopies
        default: return nil
        }
    }
}
