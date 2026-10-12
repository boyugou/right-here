import Foundation
import RightHereCore

/// The arguments the Finder extension hands the runner script. They live here, not in the extension, so
/// the tests can run the real `rh` with exactly what a menu click sends and see that it is accepted.
public enum RunnerArguments {
    /// For a chosen menu action: `run --alert <id> --origin <origin> [--container <folder>] -- <items>`.
    /// The `--` keeps any item (a file whose name starts with a dash) from being read as an option.
    public static func run(actionID: String, context: HereContext) -> [String] {
        var arguments = ["run", "--alert", actionID, "--origin", context.origin.rawValue]
        if let container = context.container { arguments += ["--container", container.path] }
        arguments.append("--")
        arguments += context.items.map(\.path)
        return arguments
    }

    /// What the extension runs when `rh doctor` leaves a probe marker. The marker's text picks from a fixed
    /// list (`launch`, `launch:window`, `launch:tab`); anything else is the harmless automation probe, so
    /// the marker file, which any process of the person's could write, never supplies arguments.
    public static func probe(markerText: String) -> [String] {
        switch markerText.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "launch": return ["probe", "launch", "--from-extension"]
        case "launch:window": return ["probe", "launch", "--from-extension", "--placement", "window"]
        case "launch:tab": return ["probe", "launch", "--from-extension", "--placement", "tab"]
        default: return ["probe", "automation", "--from-extension"]
        }
    }
}
