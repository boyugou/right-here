import AppKit
import Foundation
import RightHereCore

/// Tells the person why an action started from Finder did nothing. The Finder extension has no
/// window of its own, so `rh` shows the alert when it was started with `--alert`.
public enum FailureAlert {
    /// System Settings › Privacy & Security › Automation.
    public static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    /// Whether a failure may put a window on the screen. Only a real run started on purpose from Finder asks for one:
    /// a dry run never shows an alert (it is a question, answered on the command line), and `RH_NO_UI` switches alerts
    /// off (the tests set it, and under it `rh` also never starts `open` or `osascript`, so nothing a test does can
    /// leave a window on someone's desktop).
    public static func shouldShow(requested: Bool, dryRun: Bool, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        requested && !dryRun && environment["RH_NO_UI"] == nil
    }

    /// System Settings › Privacy & Security › Files & Folders.
    public static let filesAndFoldersSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!

    public struct Content: Sendable, Equatable {
        public var title: String
        public var message: String
        public var okTitle: String
        public var settingsTitle: String
        /// A Settings page to offer, when the failure is a permission the person can grant.
        public var settingsURL: URL?
        /// The app whose icon the alert shows: `rh` has no bundle of its own, so without one an alert shows the icon of the folder `rh`
        /// is in (`Contents/Helpers`, a plain folder) instead of Right Here's.
        public var app: URL?
    }

    /// The app an alert of this `rh` speaks for: the one it sits inside, or else the installed one.
    public static func app(rhPath: String?, facts: any SystemFacts) -> URL? {
        HostApp.locate(rhPath: rhPath ?? "", facts: facts)
    }

    /// The app's icon file, which the alert reads at once. `NSWorkspace` gives an app that Launch Services has not seen yet (a copy just
    /// unpacked, or moved) a placeholder that turns into the icon later, after the alert has been drawn with it.
    public static func iconFile(of app: URL) -> URL {
        app.appendingPathComponent("Contents/Resources/AppIcon.icns")
    }

    public static func content(for error: any Error, action: String, localizer: Localizer = .english, app: URL? = nil) -> Content {
        if let execution = error as? ExecutionError, case .automationDenied(let application) = execution {
            let target = application ?? localizer.string(.alertTheApp)
            return Content(
                title: localizer.string(.alertPermissionTitle),
                message: localizer.render(.alertPermissionMessage(target)),
                okTitle: localizer.string(.alertOk),
                settingsTitle: localizer.string(.alertOpenSettings),
                settingsURL: automationSettingsURL,
                app: app
            )
        }
        // A path macOS would not let `rh` look at is a permission the person can grant, so the alert can take them there.
        var settingsURL: URL?
        if let plan = error as? PlanError, case .unreadable = plan { settingsURL = filesAndFoldersSettingsURL }
        return Content(
            title: localizer.string(.alertFailedTitle),
            message: error.localizedDescription + "\n\n(\(action))",
            okTitle: localizer.string(.alertOk),
            settingsTitle: localizer.string(.alertOpenSettings),
            settingsURL: settingsURL,
            app: app
        )
    }

    @MainActor
    public static func show(_ content: Content) {
        guard ProcessInfo.processInfo.environment["RH_NO_UI"] == nil else { return }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        if let app = content.app { alert.icon = NSImage(contentsOf: iconFile(of: app)) ?? NSWorkspace.shared.icon(forFile: app.path) }
        alert.alertStyle = .warning
        alert.messageText = content.title
        alert.informativeText = content.message
        alert.addButton(withTitle: content.okTitle)
        if content.settingsURL != nil { alert.addButton(withTitle: content.settingsTitle) }
        if alert.runModal() == .alertSecondButtonReturn, let url = content.settingsURL {
            NSWorkspace.shared.open(url)
        }
    }
}
