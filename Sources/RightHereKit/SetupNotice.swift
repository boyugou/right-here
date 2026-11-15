import Foundation
import RightHereCore

/// What the setup window says after something the person did: a confirmation, or why it did not work. It is a value and not
/// a sentence, so the window writes it in the language of the system and a test can say what it is.
public enum SetupNotice: Sendable, Equatable {
    case promptCopied
    case mcpConfigurationCopied
    case pluginCommandsCopied
    /// The launch test's answer stays visible even when successful checks are folded away.
    case launchFinished(DoctorCheck)
    case folderPinned(String)
    case folderUnpinned(String)
    case recentsCleared
    case folderUnavailable(String)
    /// The worktree in this folder was removed.
    case worktreeRemoved(String)
    /// The folder is not inside a git repository.
    case notARepository(String)
    /// The window was asked to remove a worktree Right Here did not make: it does not do that, and git is not asked.
    case notRemovable
    /// A helper or git ended with an error and said why, in its own words (English, or the system's own wording for an error
    /// that never reached it). Shown as it is.
    case failed(String)
    /// A helper ended with an error and said nothing.
    case stopped(status: Int32)

    public var message: LocalizedMessage {
        switch self {
        case .promptCopied: .appPromptCopied
        case .mcpConfigurationCopied: .appMcpCopied
        case .pluginCommandsCopied: .appPluginCopied
        case .launchFinished(let check): check.detail ?? (check.status == .ok ? .appStatusOK : .appStatusProblem)
        case .folderPinned(let path): .appFolderPinned(path)
        case .folderUnpinned(let path): .appFolderUnpinned(path)
        case .recentsCleared: .appRecentsCleared
        case .folderUnavailable(let path): .appFolderUnavailable(path)
        case .worktreeRemoved(let folder): .appWorktreeRemoved(folder)
        case .notARepository(let folder): .appNotARepository(folder)
        case .notRemovable: .appWorktreeNotRemovable
        case .failed(let text): .doctorVerbatim(text)
        case .stopped(let status): .appCommandStopped(String(status))
        }
    }

    /// Whether this tells of something that did not work, so that the window shows it as a problem.
    public var isProblem: Bool {
        switch self {
        case .failed, .stopped, .notARepository, .notRemovable, .folderUnavailable: true
        case .launchFinished(let check): check.status != .ok
        case .promptCopied, .mcpConfigurationCopied, .pluginCommandsCopied, .worktreeRemoved, .folderPinned, .folderUnpinned, .recentsCleared: false
        }
    }
}
