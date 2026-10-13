import Foundation

/// A command-line AI agent Right Here can start in a folder.
public struct AgentDescriptor: Sendable, Equatable, Identifiable {
    public struct Variant: Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        /// Arguments appended to the command, for example `--continue`.
        public var arguments: [String]
        /// The localized title of a built-in variant; custom variants use `title` as written.
        public var titleKey: LocalizationKey?

        public init(id: String, title: String, arguments: [String], titleKey: LocalizationKey? = nil) {
            self.id = id
            self.title = title
            self.arguments = arguments
            self.titleKey = titleKey
        }

        public func localizedTitle(_ localizer: Localizer) -> String {
            titleKey.map { localizer.string($0) } ?? title
        }
    }

    /// A URL the agent's own handler turns into a session. `{dir}` is replaced by the
    /// percent-encoded working directory; prefill text, when there is any, is appended as
    /// the `promptParameter` query item.
    public struct Link: Sendable, Equatable {
        public var template: String
        public var promptParameter: String?

        public init(template: String, promptParameter: String? = nil) {
            self.template = template
            self.promptParameter = promptParameter
        }
    }

    public var id: String
    public var name: String
    /// The word typed into the shell to start the agent.
    public var command: String
    public var variants: [Variant]
    /// Bundle identifier of the app whose icon represents the agent in menus.
    public var iconBundleID: String?
    /// The agent's terminal deep link, which reuses the terminal of its last session.
    public var terminalLink: Link?
    /// The agent's desktop-app deep link.
    public var desktopLink: Link?
    /// File an agent reads project instructions from, for documentation only.
    public var instructionFile: String?

    /// The program the command starts: its first word, which is what is looked up in the login shell's PATH.
    public var executable: String {
        command.split(separator: " ").first.map(String.init) ?? command
    }

    public init(
        id: String,
        name: String,
        command: String,
        variants: [Variant] = [],
        iconBundleID: String? = nil,
        terminalLink: Link? = nil,
        desktopLink: Link? = nil,
        instructionFile: String? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.variants = variants
        self.iconBundleID = iconBundleID
        self.terminalLink = terminalLink
        self.desktopLink = desktopLink
        self.instructionFile = instructionFile
    }
}

public enum KnownAgents {
    public static let all: [AgentDescriptor] = [claude, codex, gemini, opencode, aider, amp]

    public static let claude = AgentDescriptor(
        id: "claude",
        name: "Claude Code",
        command: "claude",
        variants: [
            .init(id: "continue", title: "Continue Last Session", arguments: ["--continue"], titleKey: .variantContinue),
            .init(id: "resume", title: "Resume a Session…", arguments: ["--resume"], titleKey: .variantResume)
        ],
        iconBundleID: "com.anthropic.claudefordesktop",
        terminalLink: .init(template: "claude-cli://open?cwd={dir}", promptParameter: "q"),
        desktopLink: .init(template: "claude://code/new?folder={dir}"),
        instructionFile: "CLAUDE.md"
    )

    public static let codex = AgentDescriptor(
        id: "codex",
        name: "Codex",
        command: "codex",
        variants: [
            .init(id: "last", title: "Continue Last Session", arguments: ["resume", "--last"], titleKey: .variantContinue),
            .init(id: "resume", title: "Resume a Session…", arguments: ["resume"], titleKey: .variantResume)
        ],
        iconBundleID: "com.openai.codex",
        desktopLink: .init(template: "codex://threads/new?path={dir}"),
        instructionFile: "AGENTS.md"
    )

    public static let gemini = AgentDescriptor(
        id: "gemini",
        name: "Gemini CLI",
        command: "gemini",
        variants: [.init(id: "resume", title: "Resume Latest Session", arguments: ["--resume", "latest"], titleKey: .variantResumeLatest)],
        instructionFile: "GEMINI.md"
    )
    public static let opencode = AgentDescriptor(
        id: "opencode",
        name: "opencode",
        command: "opencode",
        variants: [.init(id: "continue", title: "Continue Last Session", arguments: ["--continue"], titleKey: .variantContinue)],
        instructionFile: "AGENTS.md"
    )
    public static let aider = AgentDescriptor(id: "aider", name: "aider", command: "aider")
    public static let amp = AgentDescriptor(id: "amp", name: "Amp", command: "amp", instructionFile: "AGENTS.md")

    public static func agent(id: String) -> AgentDescriptor? {
        all.first { $0.id == id }
    }
}
