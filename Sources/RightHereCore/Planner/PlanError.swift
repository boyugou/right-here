import Foundation

public enum PlanError: Error, Equatable, Sendable {
    /// Nothing is selected and there is no folder to act on.
    case noTarget
    /// A path that was named does not exist, for example a typo on the command line.
    case pathNotFound(String)
    /// A path the system will not let `rh` look at (a privacy-protected folder, say), so what it is cannot be told.
    case unreadable(String)
    case unknownApp(String)
    /// A terminal id (or an agent's launcher) that names no terminal.
    case unknownTerminal(String)
    case appNotInstalled(String)
    /// None of the apps of a role is installed, so there is no default to pick.
    case noDefaultApp(AppDescriptor.Role)
    case unknownAgent(String, choices: [String])
    case unknownVariant(agent: String, variant: String, choices: [String])
    case unknownTemplate(String, choices: [String])
    case unknownPreset(String, choices: [String])
    /// The prompt of a preset, once filled in, cannot be typed into a terminal as one argument (the reason says why).
    case unsafePrompt(preset: String, reason: String)
    /// A name the prompt of a preset carries from the selection (`subject` says which: the file, the folder) is what makes
    /// it impossible to type, so it is named instead of blaming the prompt.
    case unsafePresetName(preset: String, subject: String, reason: String)
    /// The target exists but cannot do what was asked, for example a terminal that cannot run a command.
    case unsupported(String)
    /// Text that would be typed into a terminal (a command line) contains line breaks or control characters.
    case unsafeText(String)
    /// A folder whose path a terminal would have to type (`cd …`) has a line break or another control character in it.
    case unsafeFolder(String)
    case nameExhausted
}

extension PlanError {
    /// An app that is no terminal was named where a terminal is needed.
    static func notATerminal(_ app: AppDescriptor) -> PlanError {
        .unsupported("\(app.name) is not a terminal. Use open.app.\(app.id) to open files with it.")
    }
}

extension PlanError: LocalizedError {
    /// Messages name paths, which are whatever somebody called them, so control characters are shown as escapes.
    public var errorDescription: String? {
        message.withControlCharactersEscaped
    }

    /// " Did you mean "x"?" when one is close, then what exists (so a typo is fixed without a second command).
    private static func hint(_ word: String, _ choices: [String]) -> String {
        var text = ""
        if let close = Suggestion.closest(to: word, in: choices) { text += " Did you mean \"\(close)\"?" }
        if !choices.isEmpty { text += " Known: " + choices.joined(separator: ", ") + "." }
        return text
    }

    /// The text without any escaping: what `rh actions` shows as the reason an action is unavailable, so that it and
    /// `rh run` say the same thing.
    var message: String {
        switch self {
        case .noTarget: return "There is no folder or selection to act on."
        case .pathNotFound(let path): return "\(path) does not exist."
        case .unreadable(let path): return "macOS did not let Right Here look at \(path), so it cannot tell whether it is a folder. Allow access to that folder under System Settings, Privacy & Security, Files & Folders (or Full Disk Access), then try again."
        case .unknownApp(let id): return "Unknown app \"\(id)\"."
        case .unknownTerminal(let id): return "Unknown terminal \"\(id)\". Run `rh apps` to list them; an agent's launcher can also be default, link or desktop."
        case .appNotInstalled(let name): return "\(name) is not installed."
        case .noDefaultApp(let role):
            switch role {
            case .terminal: return "No terminal is installed."
            case .editor: return "No editor is installed."
            case .general: return "No app is installed."
            }
        case .unknownAgent(let id, let choices): return "Unknown agent \"\(id)\"." + Self.hint(id, choices) + " `rh agents` lists them."
        case .unknownVariant(let agent, let variant, let choices): return "Agent \"\(agent)\" has no variant \"\(variant)\"." + Self.hint(variant, choices)
        case .unknownTemplate(let id, let choices): return "Unknown new-file template \"\(id)\"." + Self.hint(id, choices) + " A `[[new_file.template]]` in the config replaces the built-in ones."
        case .unknownPreset(let id, let choices): return "Unknown preset \"\(id)\"." + Self.hint(id, choices) + " A `[[preset]]` in the config adds or replaces one."
        case .unsafePrompt(let preset, let reason): return "The prompt of preset \"\(preset)\" cannot be typed into a terminal: \(reason)."
        case .unsafePresetName(let preset, let subject, let reason): return "\(subject) cannot be named in the prompt of preset \"\(preset)\": \(reason)."
        case .unsupported(let reason): return reason
        case .unsafeText(let text): return "\(text.jsonQuoted) contains line breaks or control characters and cannot be typed into a terminal."
        case .unsafeFolder(let path): return "The folder \(path.jsonQuoted) has a line break or another control character in its path, so it cannot be typed into a terminal. Rename it, or use a terminal that is handed the folder, such as Ghostty."
        case .nameExhausted: return "No free file name was found."
        }
    }
}
