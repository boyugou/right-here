import SwiftUI

@main
struct RightHereApp: App {
    @State private var model = SetupModel()

    var body: some Scene {
        Window("Right Here", id: "main") {
            SetupView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.presented)
    }
}
