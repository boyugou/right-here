import Foundation
import RightHereCore

/// What the doctor's checks add up to, as the setup window needs it: whether to say anything about the setup yet, which
/// checks are open, whether the first-run card is due, and which apps a click opens by default.
public struct SetupSummary: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        /// The doctor has not answered yet. Nothing is known, so nothing is claimed: not "all set", not "needs attention".
        case checking
        case allSet
        case needsAttention

        /// The sentence that says how the setup stands.
        public var titleKey: LocalizationKey {
            switch self {
            case .checking: .appChecking
            case .allSet: .appAllSet
            case .needsAttention: .appNeedsAttention
            }
        }
    }

    public let checks: [DoctorCheck]

    public init(checks: [DoctorCheck] = []) {
        self.checks = checks
    }

    public var state: State {
        if checks.isEmpty { return .checking }
        return attentionChecks.isEmpty ? .allSet : .needsAttention
    }

    /// The checks that are anything but ok, warnings included, in the doctor's order: the Checks page lists all of them.
    public var openChecks: [DoctorCheck] {
        checks.filter { $0.status != .ok }
    }

    /// The open checks the window asks the person to look at: all but those that are theirs to leave as they are (`DoctorCheck.isOptional`),
    /// so that a first run that went well does not end in "some checks need your attention" for a convenience.
    public var attentionChecks: [DoctorCheck] {
        openChecks.filter { !$0.isOptional }
    }

    /// The Finder extension is the one step of the first run that only the person can take, in System Settings, and the
    /// first-run card waits for it. A row that is a warning says the extension is on (and registered more than once), so it
    /// is not a first run.
    public var extensionNeedsSetup: Bool {
        guard let check = check(.finderExtension) else { return false }
        return check.status == .fail || check.status == .needsUser
    }

    public func check(_ id: CheckID) -> DoctorCheck? {
        checks.first { $0.id == id }
    }

    /// The titles of the open checks, in a language, so a banner can say which ones ("Finder extension and Default editor").
    public func openTitles(in localizer: Localizer) -> [String] {
        attentionChecks.map { $0.title(in: localizer) }
    }

    /// The terminal a click opens, by the name the system gives it; `nil` when there is none or nothing is known yet.
    public var terminal: String? { check(.terminalDefault)?.openedApp }

    /// The editor a click opens, by the name the system gives it; `nil` when there is none or nothing is known yet.
    public var editor: String? { check(.editorDefault)?.openedApp }
}

extension DoctorCheck {
    /// Whether the person may leave this warning as it is, so that the window does not ask them to look at it:
    /// - the command link is in place and its folder is not on PATH: that matters to someone who types `rh` in a terminal; the Finder menu, the Quick
    ///   Actions and an AI assistant's tools run the `rh` that the runner script and the MCP command name by its full path;
    /// - Claude Code's terminal link has no handler yet: it is made when Claude Code is started once, and only the menu's terminal link entry needs it;
    /// - no agent is enabled, which is what a person chose who picked none.
    public var isOptional: Bool {
        guard status == .warn else { return false }
        switch id {
        case .cliLink: return detail?.key == .doctorCliNotOnPath
        case .claudeLink: return true
        case .agents: return detail?.key == .doctorAgentsNone
        default: return false
        }
    }

    /// For the default terminal and editor checks: the app a click opens, as the name the check carries, whatever the
    /// language of the window (the check is a message with the name as its value; reading the name back out of the
    /// rendered sentence works in the few languages one has tried). `nil` when the check says there is no such app.
    public var openedApp: String? {
        guard let detail else { return nil }
        switch detail.key {
        case .menuOpenIn:
            return detail.arguments.first
        case .doctorAppFallback:
            // "%1$@ is not installed; %2$@ is used instead": the second is the one a click opens.
            return detail.arguments.count > 1 ? detail.arguments[1] : nil
        default:
            return nil
        }
    }
}
