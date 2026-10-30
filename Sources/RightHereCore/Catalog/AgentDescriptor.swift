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
    /// How the command takes a first prompt, for presets; `nil` when that is not known (and presets are not offered).
    public var promptArgument: PromptArgument?
    /// The argument flag this agent uses to bypass tool confirmation prompts or run autonomously, if known.
    public var bypassPermissionArgument: String?
    /// The agent's own page that says how to install it, for a person whose login shell does not find the command. Each was opened on 2026-10-22 and
    /// answered (ADR 0024: a built-in field is confirmed or absent).
    public var installPage: URL?

    /// The program the command starts: its first word that is not an assignment (`FOO=1 claude` runs `claude` with `FOO` set), which is what is looked up in the login shell's PATH.
    public var executable: String {
        let words = ShellWords.split(command)
        return words.first { $0.range(of: "^[A-Za-z_][A-Za-z0-9_]*=", options: .regularExpression) == nil } ?? command.split(separator: " ").first.map(String.init) ?? command
    }

    public init(
        id: String,
        name: String,
        command: String,
        variants: [Variant] = [],
        iconBundleID: String? = nil,
        terminalLink: Link? = nil,
        desktopLink: Link? = nil,
        promptArgument: PromptArgument? = nil,
        bypassPermissionArgument: String? = nil,
        installPage: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.variants = variants
        self.iconBundleID = iconBundleID
        self.terminalLink = terminalLink
        self.desktopLink = desktopLink
        self.promptArgument = promptArgument
        self.bypassPermissionArgument = bypassPermissionArgument
        self.installPage = installPage
    }
}

public enum KnownAgents {
    public static let all: [AgentDescriptor] = [
        claude, codex, agy, gemini, cursor, qwen, droid, kiro, opencode, kimi, muse, goose, copilot, aider, amp
    ]

    public static let agy = AgentDescriptor(
        id: "agy",
        name: "Antigravity",
        command: "agy",
        variants: [
            .init(id: "continue", title: "Continue Last Session", arguments: ["--continue"], titleKey: .variantContinue)
        ],
        iconBundleID: "com.google.antigravity",
        promptArgument: .flag("-i"),
        bypassPermissionArgument: "--dangerously-skip-permissions",
        installPage: URL(string: "https://antigravity.google")
    )

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
        promptArgument: .positional,
        bypassPermissionArgument: "--dangerously-skip-permissions",
        installPage: URL(string: "https://code.claude.com/docs/en/setup")
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
        promptArgument: .positional,
        bypassPermissionArgument: "--dangerously-bypass-approvals-and-sandbox",
        installPage: URL(string: "https://github.com/openai/codex")
    )

    public static let gemini = AgentDescriptor(
        id: "gemini",
        name: "Gemini CLI",
        command: "gemini",
        variants: [.init(id: "resume", title: "Resume Latest Session", arguments: ["--resume", "latest"], titleKey: .variantResumeLatest)],
        promptArgument: .flag("-i"),
        bypassPermissionArgument: "--approval-mode=yolo",
        installPage: URL(string: "https://github.com/google-gemini/gemini-cli")
    )

    /// Its documentation names the command `agent` and nothing else; the icon is the Cursor app's, when it is installed.
    public static let cursor = AgentDescriptor(
        id: "cursor-cli",
        name: "Cursor CLI",
        command: "agent",
        variants: [.init(id: "continue", title: "Continue Last Session", arguments: ["--continue"], titleKey: .variantContinue)],
        iconBundleID: "com.todesktop.230313mzl4w4u92",
        promptArgument: .positional,
        bypassPermissionArgument: "--force",
        installPage: URL(string: "https://cursor.com/docs/cli/installation")
    )

    public static let qwen = AgentDescriptor(
        id: "qwen",
        name: "Qwen Code",
        command: "qwen",
        promptArgument: .flag("-i"),
        bypassPermissionArgument: "--yolo",
        installPage: URL(string: "https://github.com/QwenLM/qwen-code")
    )

    public static let droid = AgentDescriptor(
        id: "droid",
        name: "Factory Droid",
        command: "droid",
        variants: [.init(id: "resume", title: "Resume Latest Session", arguments: ["--resume"], titleKey: .variantResumeLatest)],
        promptArgument: .positional,
        installPage: URL(string: "https://docs.factory.com/droid-cli/quickstart")
    )

    /// `kiro` alone starts the Kiro IDE; the chat is `kiro-cli chat`. It was Amazon Q Developer CLI.
    public static let kiro = AgentDescriptor(
        id: "kiro",
        name: "Kiro CLI",
        command: "kiro-cli chat",
        variants: [
            .init(id: "continue", title: "Continue Last Session", arguments: ["--resume"], titleKey: .variantContinue),
            .init(id: "resume", title: "Resume a Session…", arguments: ["--resume-picker"], titleKey: .variantResume)
        ],
        promptArgument: .positional,
        bypassPermissionArgument: "--trust-all-tools",
        installPage: URL(string: "https://kiro.dev/docs/cli/")
    )

    public static let opencode = AgentDescriptor(
        id: "opencode",
        name: "opencode",
        command: "opencode",
        variants: [.init(id: "continue", title: "Continue Last Session", arguments: ["--continue"], titleKey: .variantContinue)],
        bypassPermissionArgument: "--auto",
        installPage: URL(string: "https://opencode.ai")
    )

    public static let kimi = AgentDescriptor(
        id: "kimi",
        name: "Kimi Code",
        command: "kimi",
        variants: [
            .init(id: "continue", title: "Continue Last Session", arguments: ["--continue"], titleKey: .variantContinue),
            .init(id: "resume", title: "Resume a Session…", arguments: ["--resume"], titleKey: .variantResume)
        ],
        bypassPermissionArgument: "--yolo",
        installPage: URL(string: "https://github.com/MoonshotAI/kimi-cli")
    )

    public static let muse = AgentDescriptor(
        id: "muse",
        name: "Muse Code",
        command: "muse"
    )

    public static let goose = AgentDescriptor(
        id: "goose",
        name: "Goose",
        command: "goose session",
        installPage: URL(string: "https://github.com/aaif-goose/goose")
    )

    public static let copilot = AgentDescriptor(
        id: "copilot",
        name: "GitHub Copilot",
        command: "copilot",
        variants: [
            .init(id: "continue", title: "Continue Last Session", arguments: ["--continue"], titleKey: .variantContinue),
            .init(id: "resume", title: "Resume a Session…", arguments: ["--resume"], titleKey: .variantResume)
        ],
        promptArgument: .flag("-i"),
        bypassPermissionArgument: "--allow-all",
        installPage: URL(string: "https://github.com/github/copilot-cli")
    )

    public static let aider = AgentDescriptor(
        id: "aider",
        name: "aider",
        command: "aider",
        bypassPermissionArgument: "--yes-always",
        installPage: URL(string: "https://aider.chat")
    )
    public static let amp = AgentDescriptor(id: "amp", name: "Amp", command: "amp", installPage: URL(string: "https://ampcode.com"))

    public static func agent(id: String) -> AgentDescriptor? {
        all.first { $0.id == id }
    }
}
