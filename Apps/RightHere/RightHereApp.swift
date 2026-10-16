import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

/// The window is only for setup and status; the Finder extension runs without the app. Closing the
/// window therefore quits it, so nothing stays resident.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The launch test restarts the Finder extension by switching it off and on again, a second apart. Quitting between the two leaves Finder without its menu, so
    /// the app waits for that second (the command line guards it with `InterruptGuard`).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
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
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 580)
        .defaultLaunchBehavior(.presented)
    }
}
