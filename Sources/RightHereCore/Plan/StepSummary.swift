import Foundation

/// How a step is written for a person. Every value a step works on (a path, an argument, a text, a URL) is printed as a
/// quoted string (`String.jsonQuoted`): it reads back as exactly that value, a name cannot pass for the words around it,
/// and a control character in it is shown as an escape and never reaches the terminal that prints it. (`--json` prints the
/// steps themselves, as JSON.)
extension Step {
    /// One line for logs, error messages and the report of a run: what the step does and, for the steps that act on
    /// paths, which.
    public var summary: String {
        switch self {
        case .open(let step): return ([heading] + step.targets.map(\.jsonQuoted)).joined(separator: " ")
        case .reveal(let paths): return ([heading] + paths.map(\.jsonQuoted)).joined(separator: " ")
        default: return heading
        }
    }

    /// The first line of the step in a printed plan: what it does, without the values that follow on lines of their own
    /// (`details`).
    public var heading: String {
        switch self {
        case .open(let step): return "open " + (step.bundleID.map(Self.visible) ?? "default app")
        case .openURL(let url): return "open URL " + url.jsonQuoted
        case .run(let step): return "run " + ([step.executable] + step.arguments).map(\.jsonQuoted).joined(separator: " ")
        case .appleScript(let step): return "AppleScript" + (step.controls.map { " controlling " + Self.visible($0) } ?? "")
        case .copyToPasteboard(let text): return "copy \(text.count) character\(text.count == 1 ? "" : "s") to the clipboard"
        case .createFile(let step): return "create " + step.path.jsonQuoted
        case .reveal: return "reveal"
        case .pause(let milliseconds): return "wait \(milliseconds) ms"
        }
    }

    /// The lines under the heading in a printed plan: one target per line for the steps that open or reveal paths, and for
    /// the others what the heading leaves out and a person checking a plan wants to see, in full: the text that will be
    /// copied, the arguments an AppleScript receives (the folder, the typed command), the contents of a new file.
    public var details: [String] {
        switch self {
        case .open(let step): return step.targets.map { "target: " + $0.jsonQuoted }
        case .reveal(let paths): return paths.map { "target: " + $0.jsonQuoted }
        case .copyToPasteboard(let text): return ["text: " + text.jsonQuoted]
        case .appleScript(let step): return step.arguments.isEmpty ? [] : ["arguments: " + step.arguments.map(\.jsonQuoted).joined(separator: ", ")]
        case .createFile(let step): return step.contents.isEmpty ? [] : ["contents: " + step.contents.jsonQuoted]
        default: return []
        }
    }

    /// The text with control characters replaced by visible escapes; everything else is unchanged.
    private static func visible(_ text: String) -> String {
        text.withControlCharactersEscaped
    }
}
