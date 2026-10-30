import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

/// The window is only for setup and status; the Finder extension runs without the app. Closing the
/// window therefore quits it, so nothing stays resident.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The text of the Config page has changes that are not saved: closing the window quits the app, and they would be gone.
    var hasUnsavedText = false
    /// The language of the window, for the question asked when it quits.
    var localizer = Localizer.system

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The launch test restarts the Finder extension by switching it off and on again, a second apart. Quitting between the two leaves Finder without its menu, so
    /// the app waits for that second (the command line guards it with `InterruptGuard`).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if hasUnsavedText {
            let l10n = localizer
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = l10n.string(.appQuitUnsavedTitle)
            alert.informativeText = l10n.string(.appQuitUnsavedMessage)
            // The first button is the default one: keeping the text is what a Return does.
            alert.addButton(withTitle: l10n.string(.appCancel))
            alert.addButton(withTitle: l10n.string(.appQuitAnyway)).hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        }
        guard ProbeActivity.shared.isSwitching else { return .terminateNow }
        Task { @MainActor in
            // The two `pluginkit` calls are stopped after 30 seconds each, so this ends; the limit is for a bug that would keep the app from ever quitting.
            for _ in 0..<700 {
                guard ProbeActivity.shared.isSwitching else { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct RightHereApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = SetupModel()

    var body: some Scene {
        Window(AppIdentity.productName, id: "main") {
            SetupView(model: model)
                .onChange(of: model.textHasChanges, initial: true) { _, unsaved in delegate.hasUnsavedText = unsaved }
                .onChange(of: model.localizer, initial: true) { _, localizer in delegate.localizer = localizer }
        }
        // The sidebar runs to the top of the window, with the window's buttons in its corner; there is no bar with the app's name above it.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 580)
        .defaultLaunchBehavior(.presented)
        .commands {
            // The Help menu had only macOS's search: the guide on the website, in the window's language.
            CommandGroup(replacing: .help) {
                Button(model.localizer.render(.appHelpMenu(AppIdentity.productName))) {
                    NSWorkspace.shared.open(AppIdentity.guideURL(language: model.localizer.resolvedLanguage))
                }
            }
        }
    }
}
