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
    }

    public let checks: [DoctorCheck]

    public init(checks: [DoctorCheck] = []) {
        self.checks = checks
    }

    public var state: State {
        if checks.isEmpty { return .checking }
        return openChecks.isEmpty ? .allSet : .needsAttention
    }

    /// The checks that are anything but ok, warnings included, in the doctor's order.
    public var openChecks: [DoctorCheck] {
        checks.filter { $0.status != .ok }
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
        openChecks.map { $0.title(in: localizer) }
    }

    /// The terminal a click opens, by the name the system gives it; `nil` when there is none or nothing is known yet.
    public var terminal: String? { check(.terminalDefault)?.openedApp }

    /// The editor a click opens, by the name the system gives it; `nil` when there is none or nothing is known yet.
    public var editor: String? { check(.editorDefault)?.openedApp }
}

extension DoctorCheck {
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
