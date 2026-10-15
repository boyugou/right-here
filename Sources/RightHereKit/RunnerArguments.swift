import Foundation
import RightHereCore

/// The arguments the Finder extension hands the runner script. They live here, not in the extension, so
/// the tests can run the real `rh` with exactly what a menu click sends and see that it is accepted.
public enum RunnerArguments {
    /// The most items one click hands over. The whole argument list has to fit the system's limit (about 1 MB
    /// with the environment), and a selection of thousands of files would otherwise make the runner fail to
    /// start at all. What an action needs from a selection is its first item and whether there are several, and
    /// nobody opens that many files at once on purpose.
    public static let maxItems = 500

    /// For a chosen menu action: `run --alert <id> --origin <origin> [--container <folder>] -- <items>`.
    /// The `--` keeps any item (a file whose name starts with a dash) from being read as an option.
    public static func run(actionID: String, context: HereContext) -> [String] {
        var arguments = ["run", "--alert", actionID, "--origin", context.origin.rawValue]
        if let container = context.container { arguments += ["--container", container.path] }
        arguments.append("--")
        arguments += context.items.prefix(maxItems).map(\.path)
        return arguments
    }

    /// What the extension runs when `rh doctor` leaves a probe marker. The marker's text picks from a fixed
    /// list (`launch`, and `launch:` followed by the name of a terminal placement); anything else is the harmless automation probe, so
    /// the marker file, which any process of the person's could write, never supplies arguments.
    public static func probe(markerText: String) -> [String] {
        let text = markerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "launch" { return ["probe", "launch", "--from-extension"] }
        if text.hasPrefix("launch:"), let placement = TerminalPlacement(configName: String(text.dropFirst("launch:".count))) {
            return ["probe", "launch", "--from-extension", "--placement", placement.configName]
        }
        return ["probe", "automation", "--from-extension"]
    }
}
