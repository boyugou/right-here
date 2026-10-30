import Foundation

/// How an agent session is started.
public enum AgentLauncher: Sendable, Equatable, Hashable {
    /// Type the command into a new shell of a terminal; `nil` means the default terminal.
    case terminal(String?)
    /// The agent's own terminal deep link, which reuses the terminal of its last session.
    case terminalLink
    /// The agent's desktop app, through its deep link.
    case desktop

    /// The words for a launcher in an action id (`agent.claude@link`) and in a config's `launcher` key.
    public static let terminalWord = "terminal"
    public static let linkWord = "link"
    public static let desktopWord = "desktop"
    /// Only in an action id: the default terminal.
    public static let defaultWord = "default"

    /// The words after the `@` of an agent action that are not the id of a terminal, so no app can be called one: `agent.claude@desktop`
    /// is the desktop app, never a terminal whose id is `desktop`.
    public static let reservedWords: Set<String> = [linkWord, desktopWord, defaultWord]

    /// What `launcher = "…"` accepts in an `[agent.<id>]` table.
    public static let configNames = [terminalWord, linkWord, desktopWord]

    /// The launcher an `[agent.<id>]` table asks for. `terminal` is the table's own terminal choice, which applies
    /// with `launcher = "terminal"` and also when no launcher is named.
    public static func fromConfig(name: String?, terminal: String?) -> AgentLauncher? {
        switch name {
        case linkWord?: return .terminalLink
        case desktopWord?: return .desktop
        case terminalWord?: return .terminal(terminal)
        default: return terminal.map { .terminal($0) }
        }
    }
}

/// A parsed action identifier. The text form is stable and meant to be written by people and agents:
///
///     copy-path.<style>              copy-path.git-relative
///     open.terminal[@<terminal>]     open.terminal@ghostty
///     open.editor                    the default editor
///     open.app.<app>                 open.app.zed
///     agent.<agent>[.<variant>][@<launcher>]
///                                    agent.claude   agent.claude.continue@ghostty   agent.codex@desktop
///                                    launcher: a terminal id, "default" (the default terminal),
///                                    "link" or "desktop"
///     preset.<id>[@<terminal>]       preset.review   preset.tests@ghostty
///     new-file.<template>            new-file.md
///     reveal
///     repository.copy-link           the item's page on its git host, copied (ADR 0033)
///     repository.open-page           the same page, opened in the browser
public enum ActionRef: Sendable, Equatable, Hashable {
    case copyPath(PathStyle)
    case openTerminal(String?)
    case openEditor
    case openApp(String)
    /// A `nil` launcher means the one configured for the agent.
    case agent(id: String, variant: String?, launcher: AgentLauncher?)
    case newFile(String)
    /// A prompt preset of the config, typed into a terminal with its agent; `nil` is the agent's own terminal choice.
    case preset(id: String, terminal: String?)
    case reveal
    case copyRepositoryLink
    case openRepositoryPage

    public init?(parsing text: String) {
        let (body, suffix) = Self.split(text)
        let parts = body.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy(Self.isWord), !parts.isEmpty else { return nil }

        switch (parts[0], parts.count) {
        case ("copy-path", 2):
            guard suffix == nil, let style = PathStyle(rawValue: parts[1]) else { return nil }
            self = .copyPath(style)
        case ("open", 2) where parts[1] == "terminal":
            guard case .valid(let terminal) = Self.terminalSuffix(suffix) else { return nil }
            self = .openTerminal(terminal)
        case ("open", 2) where parts[1] == "editor":
            guard suffix == nil else { return nil }
            self = .openEditor
        case ("open", 3) where parts[1] == "app":
            guard suffix == nil else { return nil }
            self = .openApp(parts[2])
        case ("agent", 2), ("agent", 3):
            guard case .valid(let launcher) = Self.launcherSuffix(suffix) else { return nil }
            self = .agent(id: parts[1], variant: parts.count == 3 ? parts[2] : nil, launcher: launcher)
        case ("preset", 2):
            // A preset with no suffix is typed into the default terminal; `@default` would be a second spelling of that.
            guard case .valid(let terminal) = Self.terminalSuffix(suffix), terminal != AgentLauncher.defaultWord else { return nil }
            self = .preset(id: parts[1], terminal: terminal)
        case ("new-file", 2):
            guard suffix == nil else { return nil }
            self = .newFile(parts[1])
        case ("reveal", 1):
            guard suffix == nil else { return nil }
            self = .reveal
        case ("repository", 2) where parts[1] == "copy-link":
            guard suffix == nil else { return nil }
            self = .copyRepositoryLink
        case ("repository", 2) where parts[1] == "open-page":
            guard suffix == nil else { return nil }
            self = .openRepositoryPage
        default:
            return nil
        }
    }

    /// The actions whose plan needs what git says about the repository (`RepositoryState`), read before planning.
    public var readsRepository: Bool { self == .copyRepositoryLink || self == .openRepositoryPage }

    public var id: String {
        switch self {
        case .copyPath(let style):
            return "copy-path.\(style.rawValue)"
        case .openTerminal(let terminal):
            return "open.terminal" + (terminal.map { "@\($0)" } ?? "")
        case .openEditor:
            return "open.editor"
        case .openApp(let app):
            return "open.app.\(app)"
        case .agent(let agent, let variant, let launcher):
            let suffix: String
            switch launcher {
            case nil: suffix = ""
            case .terminal(let terminal)?: suffix = "@" + (terminal ?? AgentLauncher.defaultWord)
            case .terminalLink?: suffix = "@" + AgentLauncher.linkWord
            case .desktop?: suffix = "@" + AgentLauncher.desktopWord
            }
            return "agent.\(agent)" + (variant.map { ".\($0)" } ?? "") + suffix
        case .preset(let id, let terminal):
            return "preset.\(id)" + (terminal.map { "@\($0)" } ?? "")
        case .newFile(let template):
            return "new-file.\(template)"
        case .reveal:
            return "reveal"
        case .copyRepositoryLink:
            return "repository.copy-link"
        case .openRepositoryPage:
            return "repository.open-page"
        }
    }

    // MARK: Parsing helpers

    private static func split(_ text: String) -> (body: String, suffix: String?) {
        guard let at = text.firstIndex(of: "@") else { return (text, nil) }
        return (String(text[..<at]), String(text[text.index(after: at)...]))
    }

    private enum Parsed<Value> {
        case valid(Value)
        case malformed
    }

    private static func isWord(_ part: String) -> Bool {
        IDRule.isValid(part)
    }

    /// `@ghostty` selects a terminal; no suffix means the default terminal.
    private static func terminalSuffix(_ suffix: String?) -> Parsed<String?> {
        guard let suffix else { return .valid(nil) }
        return isWord(suffix) ? .valid(suffix) : .malformed
    }

    /// No suffix means the launcher configured for the agent.
    private static func launcherSuffix(_ suffix: String?) -> Parsed<AgentLauncher?> {
        guard let suffix else { return .valid(nil) }
        switch suffix {
        case AgentLauncher.linkWord: return .valid(.terminalLink)
        case AgentLauncher.desktopWord: return .valid(.desktop)
        case AgentLauncher.defaultWord: return .valid(.terminal(nil))
        default: return isWord(suffix) ? .valid(.terminal(suffix)) : .malformed
        }
    }
}
