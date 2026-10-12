import Foundation

public enum PlanError: Error, Equatable, Sendable {
    /// Nothing is selected and there is no folder to act on.
    case noTarget
    /// A path that was named does not exist, for example a typo on the command line.
    case pathNotFound(String)
    case unknownAction(String)
    case unknownApp(String)
    /// A terminal id (or an agent's launcher) that names no terminal.
    case unknownTerminal(String)
    case appNotInstalled(String)
    case unknownAgent(String)
    case unknownVariant(agent: String, variant: String)
    case unknownTemplate(String)
    /// The target exists but cannot do what was asked, for example a terminal that cannot run a command.
    case unsupported(String)
    /// Text that would be typed into a terminal contains line breaks or control characters.
    case unsafeText(String)
    case nameExhausted
}

extension PlanError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noTarget: return "There is no folder or selection to act on."
        case .pathNotFound(let path): return "\(path) does not exist."
        case .unknownAction(let id): return "Unknown action \"\(id)\". Run `rh actions` to list them."
        case .unknownApp(let id): return "Unknown app \"\(id)\"."
        case .unknownTerminal(let id): return "Unknown terminal \"\(id)\". Run `rh apps` to list them; an agent's launcher can also be default, link or desktop."
        case .appNotInstalled(let name): return "\(name) is not installed."
        case .unknownAgent(let id): return "Unknown agent \"\(id)\"."
        case .unknownVariant(let agent, let variant): return "Agent \"\(agent)\" has no variant \"\(variant)\"."
        case .unknownTemplate(let id): return "Unknown new-file template \"\(id)\"."
        case .unsupported(let reason): return reason
        case .unsafeText(let text): return "\"\(text.debugDescription)\" contains line breaks or control characters and cannot be typed into a terminal."
        case .nameExhausted: return "No free file name was found."
        }
    }
}
