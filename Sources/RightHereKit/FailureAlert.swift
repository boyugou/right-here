import AppKit
import Foundation
import RightHereCore

/// Tells the person why an action started from Finder did nothing. The Finder extension has no
/// window of its own, so `rh` shows the alert when it was started with `--alert`.
public enum FailureAlert {
    /// System Settings › Privacy & Security › Automation.
    public static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    public struct Content: Sendable, Equatable {
        public var title: String
        public var message: String
        /// A Settings page to offer, when the failure is a permission the person can grant.
        public var settingsURL: URL?
    }

    public static func content(for error: any Error, action: String) -> Content {
        if let execution = error as? ExecutionError, case .automationDenied(let application) = execution {
            let target = application ?? "the app"
            return Content(
                title: "Right Here needs your permission",
                message: "macOS blocked Right Here from controlling \(target). Allow it in System Settings › Privacy & Security › Automation, then try again.",
                settingsURL: automationSettingsURL
            )
        }
        return Content(title: "Right Here could not finish", message: error.localizedDescription + "\n\n(\(action))", settingsURL: nil)
    }

    @MainActor
    public static func show(_ content: Content) {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = content.title
        alert.informativeText = content.message
        alert.addButton(withTitle: "OK")
        if content.settingsURL != nil { alert.addButton(withTitle: "Open System Settings") }
        if alert.runModal() == .alertSecondButtonReturn, let url = content.settingsURL {
            NSWorkspace.shared.open(url)
        }
    }
}
