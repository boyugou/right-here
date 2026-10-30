import Foundation

extension TerminalSession {
    /// The session's folder as a path, after checking it is a folder. Handing a file to a terminal
    /// app would run it, so an adapter never passes on anything else.
    public func requireDirectory(_ facts: any SystemFacts) throws -> String {
        guard facts.isDirectory(directory) == true else {
            throw PlanError.unsupported("\(directory.path) is not a folder.")
        }
        return directory.path
    }

    /// The command to type, checked again here so an adapter does not rely on its caller: a line
    /// break or any other control character would press keys the person did not choose.
    public func requireTypeableInput() throws -> String? {
        guard let typedInput else { return nil }
        do { try ShellQuoting.validateForTyping(typedInput) } catch { throw PlanError.unsafeText(typedInput) }
        return typedInput
    }
}

public enum TerminalPlacement: String, Sendable, Codable, CaseIterable {
    case newWindow
    case newTab
    case splitRight
    case splitDown

    /// How the config file spells it: `window`, `tab`, `split-right`, `split-down`. One spelling each.
    public static let configNames = ["window", "tab", "split-right", "split-down"]

    public init?(configName: String) {
        switch configName {
        case "window": self = .newWindow
        case "tab": self = .newTab
        case "split-right": self = .splitRight
        case "split-down": self = .splitDown
        default: return nil
        }
    }

    public var configName: String {
        switch self {
        case .newWindow: return "window"
        case .newTab: return "tab"
        case .splitRight: return "split-right"
        case .splitDown: return "split-down"
        }
    }
}

/// A shell session to start in a terminal.
public struct TerminalSession: Sendable, Equatable {
    public var directory: URL
    /// Typed into the new shell, followed by Return, exactly as a person would. The shell is the
    /// user's own interactive login shell, so PATH, version managers and aliases apply, and it
    /// stays open when the command ends. The caller has already validated the text.
    public var typedInput: String?
    public var placement: TerminalPlacement

    public init(directory: URL, typedInput: String? = nil, placement: TerminalPlacement = .newWindow) {
        self.directory = directory
        self.typedInput = typedInput
        self.placement = placement
    }
}

/// Knows how one terminal opens a session in a folder. Adapters only build steps.
public protocol TerminalAdapter: Sendable {
    var terminalID: String { get }
    /// Why this terminal has no way to run a command in a new session, which agents need; `nil` when it has one.
    var commandRefusal: String? { get }
    /// Whether the folder may reach a shell as typed text (`cd …`) rather than as the session's working directory, which
    /// the terminal is handed as an argument and which nothing types. Typed text is read by a shell the adapter cannot see,
    /// so such an adapter refuses folder names with a control character, and the common shells read some others differently.
    /// An adapter says `false` only when it hands the folder over and types none of it: the default is `true`, so one that
    /// says nothing is held to the strict rule (a terminal defined in the config is one: its template may put `{dir}` into a
    /// shell line).
    var typesTheFolder: Bool { get }
    /// The places a session can start in: a terminal that is not listed here as having tabs and splits opens a new window whatever `terminal_placement` says.
    var supportedPlacements: [TerminalPlacement] { get }
    /// Why this installed terminal cannot run a command on this machine even though it normally can
    /// (an old version, say), or `nil` when nothing stands in the way.
    func commandBlocker(bundleID: String, facts: any SystemFacts) -> String?
    func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step]
}

extension TerminalAdapter {
    public var commandRefusal: String? { nil }
    /// Whether the terminal can run a command in the new session.
    public var supportsCommands: Bool { commandRefusal == nil }
    public func commandBlocker(bundleID: String, facts: any SystemFacts) -> String? { nil }
    public var typesTheFolder: Bool { true }
    public var supportedPlacements: [TerminalPlacement] { [.newWindow] }
}

/// For a terminal that opens a window in a folder when handed the folder, and has no way to run a command.
public struct OpenFolderTerminalAdapter: TerminalAdapter {
    public let terminalID: String
    public let displayName: String
    public var commandRefusal: String? { "\(displayName) cannot run commands yet. Choose another terminal for this agent." }
    public var typesTheFolder: Bool { false }

    public init(terminalID: String, displayName: String) {
        self.terminalID = terminalID
        self.displayName = displayName
    }

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        if session.typedInput != nil, let refusal = commandRefusal { throw PlanError.unsupported(refusal) }
        return [.open(OpenStep(bundleID: bundleID, targets: [try session.requireDirectory(facts)]))]
    }
}

public enum TerminalAdapters {
    /// The adapter that drives a terminal. A terminal with no driver of its own can only be handed a folder.
    public static func adapter(for app: AppDescriptor) -> any TerminalAdapter {
        switch app.driver {
        case .ghostty: return GhosttyAdapter()
        case .appleScriptTerminal: return AppleTerminalAdapter()
        case .iterm: return ITermAdapter()
        case .wezterm: return WezTermAdapter()
        case .kitty: return KittyAdapter()
        case .alacritty: return AlacrittyAdapter()
        case .warp: return WarpAdapter()
        case .template(let launch): return TemplateTerminalAdapter(terminalID: app.id, displayName: app.name, launch: launch)
        case .openFolder: return OpenFolderTerminalAdapter(terminalID: app.id, displayName: app.name)
        }
    }
}
