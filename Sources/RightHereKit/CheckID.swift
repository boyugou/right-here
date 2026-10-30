import Foundation
import RightHereCore

/// Which check a row of the doctor is: a fixed set, plus one check for each agent that is enabled.
public enum CheckID: Hashable, Sendable {
    case config
    /// Changes that an AI assistant proposed and that wait for the person.
    case pending
    case terminalDefault
    case editorDefault
    case agents
    case agent(String)
    case claudeLink
    case finderMenu
    case finderRunner
    case services
    case cliLink
    case finderExtension
    /// More than one copy of the app is installed.
    case appCopies
    case finderActivity
    case finderChain
    case finderLaunch
    case syncFolder
    case syncRemote
    case syncState
    case syncCommands
    case syncConflict

    /// The id as `rh doctor --json` prints it: `terminal.default`, `agent.claude`.
    public var rawValue: String {
        switch self {
        case .config: "config"
        case .pending: "config.pending"
        case .terminalDefault: "terminal.default"
        case .editorDefault: "editor.default"
        case .agents: "agents"
        case .agent(let id): "agent." + id
        case .claudeLink: "claude.link"
        case .finderMenu: "finder.menu"
        case .finderRunner: "finder.runner"
        case .services: "services"
        case .cliLink: "cli.link"
        case .finderExtension: "finder.extension"
        case .appCopies: "app.copies"
        case .finderActivity: "finder.activity"
        case .finderChain: "finder.chain"
        case .finderLaunch: "finder.launch"
        case .syncFolder: "sync.folder"
        case .syncRemote: "sync.remote"
        case .syncState: "sync.state"
        case .syncCommands: "sync.commands"
        case .syncConflict: "sync.conflict"
        }
    }

    /// An agent's row is titled, and its text may be written, by the config.
    public var isAgent: Bool {
        if case .agent = self { true } else { false }
    }

    /// Whether the row can hold text that the config gave (an app's or an agent's name, an agent's command, the error that quotes a value, the folder the
    /// config syncs with) or that a probe took from it. `rh doctor --report` leaves such text out, and a report an AI agent reads marks it as data. There
    /// is no `default`: a new check has to be put on one side or the other.
    public var quotesTheConfig: Bool {
        switch self {
        case .config, .terminalDefault, .editorDefault, .agents, .agent, .finderMenu, .finderActivity, .finderChain, .finderLaunch,
             .syncFolder, .syncRemote, .syncState, .syncCommands, .syncConflict:
            true
        case .pending, .claudeLink, .finderRunner, .services, .cliLink, .finderExtension, .appCopies:
            false
        }
    }

    /// The catalog text that titles the row, in every language. An agent's row is titled with the agent's own name.
    public var titleKey: LocalizationKey? {
        switch self {
        case .config: .appCheckConfig
        case .pending: .appCheckPending
        case .terminalDefault: .appCheckTerminal
        case .editorDefault: .appCheckEditor
        case .agents: .appCheckAgents
        case .agent: nil
        case .claudeLink: .appCheckClaudeLink
        case .finderMenu: .appCheckMenu
        case .finderRunner: .appCheckRunner
        case .services: .appCheckServices
        case .cliLink: .appCheckCLI
        case .finderExtension: .appCheckExtension
        case .appCopies: .appCheckCopies
        case .finderActivity: .appCheckLastAction
        case .finderChain: .appCheckChain
        case .finderLaunch: .appCheckLaunch
        case .syncFolder: .appCheckSyncFolder
        case .syncRemote: .appCheckSyncRemote
        case .syncState: .appCheckSync
        case .syncCommands: .appCheckSyncCommands
        case .syncConflict: .appCheckSyncConflict
        }
    }
}
