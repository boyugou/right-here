import Foundation

extension Step {
    /// A one-line description for logs, error messages and `rh run --dry-run`. Control characters in
    /// names are shown as escapes, so a file called with a terminal escape sequence cannot act on the
    /// terminal that prints this.
    public var summary: String {
        switch self {
        case .open(let step):
            return "open " + (step.bundleID ?? "default app") + " " + step.targets.map(Self.visible).joined(separator: " ")
        case .openURL(let url):
            return "open URL " + Self.visible(url)
        case .run(let step):
            return "run " + ([step.executable] + step.arguments).map(Self.visible).joined(separator: " ")
        case .appleScript(let step):
            return "AppleScript" + (step.controls.map { " controlling \($0)" } ?? "")
        case .copyToPasteboard(let text):
            return "copy \(text.count) characters to the clipboard"
        case .createFile(let step):
            return "create " + Self.visible(step.path)
        case .reveal(let paths):
            return "reveal " + paths.map(Self.visible).joined(separator: " ")
        case .pause(let milliseconds):
            return "wait \(milliseconds) ms"
        }
    }
}

extension Step {
    /// What the one-line summary leaves out and a person checking a plan wants to see: the text that
    /// will be copied, and the arguments an AppleScript receives (the folder, the typed command).
    public var details: [String] {
        switch self {
        case .copyToPasteboard(let text):
            return ["text: " + Self.preview(text)]
        case .appleScript(let step):
            return step.arguments.isEmpty ? [] : ["arguments: " + step.arguments.map(Self.preview).joined(separator: ", ")]
        case .createFile(let step):
            return step.contents.isEmpty ? [] : ["contents: " + Self.preview(step.contents)]
        default:
            return []
        }
    }

    /// A quoted, single-line rendering that shows control characters instead of acting like them.
    private static func preview(_ text: String) -> String {
        let limit = 200
        let shown = text.count > limit ? String(text.prefix(limit)) + "…" : text
        return "\"" + shown.withControlCharactersEscaped.scalarReplacing(["\"": "\\\""]) + "\""
    }

    /// The text with control characters replaced by visible escapes; everything else is unchanged.
    static func visible(_ text: String) -> String {
        text.withControlCharactersEscaped
    }
}
