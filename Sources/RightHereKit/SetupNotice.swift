import Foundation
import RightHereCore

/// What the setup window says after something the person did: a confirmation, or why it did not work. It is a value and not
/// a sentence, so the window writes it in the language of the system and a test can say what it is.
public enum SetupNotice: Sendable, Equatable {
    case promptCopied
    case mcpConfigurationCopied
    case pluginCommandsCopied
    /// The worktree in this folder was removed.
    case worktreeRemoved(String)
    /// The folder is not inside a git repository.
    case notARepository(String)
    /// The window was asked to remove a worktree Right Here did not make: it does not do that, and git is not asked.
    case notRemovable
    /// The worktree in this folder holds files git ignores that exist only there (`WorktreeError.ignoredFiles`): nothing was removed, and the window asks whether to
    /// lose exactly these.
    case worktreeHasIgnoredFiles(String, [String])
    /// A helper or git ended with an error and said why, in its own words (English, or the system's own wording for an error
    /// that never reached it). Shown as it is.
    case failed(String)
    /// Something failed for a reason the catalog has the sentences of (a refusal of a plan, a change the config would refuse), which the
    /// window writes in the person's language.
    case explained([LocalizedMessage])
    /// A helper ended with an error and said nothing.
    case stopped(status: Int32)
    /// A list the window showed was changed by something else before the person's change reached the file, so the change was not made (`ConfigOperation.expect`).
    case listChanged
    /// The change to take back is no longer the last one of the config: something else changed it after, so nothing was taken back.
    case undoRefused
    /// The file was changed after the card of a proposal was drawn, so applying it was refused: the card is drawn again.
    case proposalStale
    /// The proposal is no longer waiting (made or dismissed elsewhere, or expired), so there was nothing to apply.
    case proposalGone
    /// Something else kept the window busy for as long as a change waits, so the change was not made.
    case busy
    /// The app that was chosen to be added is available already (built in, or in the config), by this name.
    case appAlreadyAvailable(String)
    /// The app that was chosen is a built-in one that this Mac turns off.
    case appTurnedOff(String)
    /// The app that was chosen has no bundle identifier, so it cannot be found by one.
    case appNotFound(String)
    /// Install or Repair ended and every part worked; it made or changed this many of them.
    case repaired(changed: Int)
    /// Install or Repair ended, and these checks (their titles) still ask for it: it could not put them right.
    case repairLeft([String])

    /// The notice for an error: its sentences when the catalog has them, else its own words, escaped (they may quote a value that
    /// somebody else wrote).
    public static func failure(_ error: any Error) -> SetupNotice {
        if let failure = error as? any LocalizedFailure { return .explained(failure.shownSentences) }
        return .failed(((error as? LocalizedError)?.errorDescription ?? error.localizedDescription).withControlCharactersEscaped)
    }

    /// What the window shows, in the localizer's language. A step's detail starts in lower case beside the step's name, and as a notice it
    /// stands alone, so the first letter of a failure's sentences is a capital; another program's words (`failed`) are left as it wrote them.
    /// The values are as the notice holds them (a failure's are escaped already).
    public func text(in localizer: Localizer, isolatingValues: Bool = true) -> String {
        let text = localizer.render(sentences: messages, isolatingValues: isolatingValues)
        guard case .explained = self, let first = text.first, first.isLowercase else { return text }
        return String(first).uppercased(with: Locale(identifier: localizer.resolvedLanguage)) + text.dropFirst()
    }

    /// What the window says, one sentence after another.
    public var messages: [LocalizedMessage] {
        if case .explained(let sentences) = self { return sentences }
        return [message]
    }

    private var message: LocalizedMessage {
        switch self {
        case .promptCopied: .appPromptCopied
        case .mcpConfigurationCopied: .appMcpCopied
        case .pluginCommandsCopied: .appPluginCopied
        case .worktreeRemoved(let folder): .appWorktreeRemoved(folder)
        case .notARepository(let folder): .appNotARepository(folder)
        case .notRemovable: .appWorktreeNotRemovable
        case .worktreeHasIgnoredFiles(let folder, let files): .refusalWorktreeIgnoredFiles(folder, WorktreeError.shown(files))
        case .failed(let text): .doctorVerbatim(text)
        case .explained(let sentences): .doctorVerbatim(Localizer.english.render(sentences: sentences))
        case .stopped(let status): .appCommandStopped(String(status))
        case .listChanged: .appListChanged
        case .undoRefused: .appUndoRefused
        case .proposalStale: .appProposalStale
        case .proposalGone: .appProposalGone
        case .busy: .appEditBusy
        case .appAlreadyAvailable(let name): .appAppAlreadyAvailable(name)
        case .appTurnedOff(let name): .appAppTurnedOff(name)
        case .appNotFound(let name): .appAppNotFound(name)
        case .repaired(let changed): changed == 0 ? .appRepairDoneUnchanged : .appRepairDone
        case .repairLeft(let titles): .appRepairLeft(titles.joined(separator: ", "))
        }
    }

    /// Whether this tells of something that did not work, so that the window shows it as a problem.
    public var isProblem: Bool {
        switch self {
        case .failed, .explained, .stopped, .notARepository, .notRemovable, .worktreeHasIgnoredFiles, .listChanged, .undoRefused, .proposalStale, .proposalGone, .busy, .appNotFound, .appAlreadyAvailable, .appTurnedOff, .repairLeft: true
        case .promptCopied, .mcpConfigurationCopied, .pluginCommandsCopied, .worktreeRemoved, .repaired: false
        }
    }
}
