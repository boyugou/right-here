import Foundation
import RightHereCore

/// Finds the app bundle that goes with an `rh`: the one it sits inside, or else the installed app.
public enum HostApp {
    /// - Parameter rhPath: The `rh` that is running (for the command line) or the one inside the app (for the app).
    public static func locate(rhPath: String, facts: any SystemFacts) -> URL? {
        if let range = rhPath.range(of: ".app/Contents/") {
            return URL(fileURLWithPath: String(rhPath[..<range.lowerBound]) + ".app")
        }
        return facts.applicationURL(bundleID: AppIdentity.hostBundleID)
    }

    public static func extensionURL(in app: URL) -> URL {
        app.appendingPathComponent("Contents/PlugIns/\(AppIdentity.extensionBundleName)")
    }

    /// Whether `rhPath` is a program that a build left in a folder of the project (SwiftPM's `.build`, Xcode's `DerivedData`). The
    /// runner script and the Quick Actions that point at it stop working when the build folder is cleaned.
    public static func isBuildProduct(_ rhPath: String) -> Bool {
        rhPath.contains("/.build/") || rhPath.contains("/DerivedData/")
    }
}
