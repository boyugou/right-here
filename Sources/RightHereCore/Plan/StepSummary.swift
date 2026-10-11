import Foundation

extension Step {
    /// A one-line description for logs and error messages.
    public var summary: String {
        switch self {
        case .open(let step):
            return "open " + (step.bundleID ?? "default app") + " " + step.targets.joined(separator: " ")
        case .openURL(let url):
            return "open URL " + url
        case .run(let step):
            return "run " + ([step.executable] + step.arguments).joined(separator: " ")
        case .appleScript(let step):
            return "AppleScript" + (step.controls.map { " controlling \($0)" } ?? "")
        case .copyToPasteboard(let text):
            return "copy \(text.count) characters to the clipboard"
        case .createFile(let step):
            return "create " + step.path
        case .reveal(let paths):
            return "reveal " + paths.joined(separator: " ")
        case .pause(let milliseconds):
            return "wait \(milliseconds) ms"
        }
    }
}
