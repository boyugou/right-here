import AppKit
import SwiftUI

/// The window is only for setup and status; the Finder extension runs without the app. Closing the
/// window therefore quits it, so nothing stays resident.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct RightHereApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = SetupModel()

    var body: some Scene {
        Window("Right Here", id: "main") {
            SetupView(model: model)
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
    }
}
