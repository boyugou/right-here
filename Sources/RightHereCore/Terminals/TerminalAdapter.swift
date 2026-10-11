import Foundation

public enum TerminalPlacement: String, Sendable, Codable, CaseIterable {
    case newWindow
    case newTab
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
    /// Whether the terminal can run a command in the new session, which agents need.
    var supportsCommands: Bool { get }
    func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step]
}

/// For a terminal that opens a window in a folder when handed the folder, and has no way to run a command.
public struct OpenFolderTerminalAdapter: TerminalAdapter {
    public let terminalID: String
    public let displayName: String
    public var supportsCommands: Bool { false }

    public init(terminalID: String, displayName: String) {
        self.terminalID = terminalID
        self.displayName = displayName
    }

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        if session.typedInput != nil {
            throw PlanError.unsupported("\(displayName) cannot run a command yet. Choose another terminal for this agent.")
        }
        return [.open(OpenStep(bundleID: bundleID, targets: [session.directory.path]))]
    }
}

public enum TerminalAdapters {
    public static func adapter(for app: AppDescriptor) -> any TerminalAdapter {
        OpenFolderTerminalAdapter(terminalID: app.id, displayName: app.name)
    }
}
