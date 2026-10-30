import Foundation
import RightHereCore

/// The sections of the setup window, in the order its sidebar lists them.
///
/// The window is for setup and status; the Finder extension and `rh` work without it. A section is here only when
/// the person can do or learn something in it: the first-run steps and the state of things, the menu the extension
/// builds, the agents it offers, the config file, the checks behind the state, what to hand an AI assistant, the worktrees Right Here made for agents, and the
/// folders it remembers. What `rh` can do from a terminal and the window has no use for is not repeated here.
public enum SetupTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case menu
    case agents
    case config
    case checks
    case ai
    case worktrees
    case folders

    public var id: String { rawValue }

    /// The catalog text that names the section, in the sidebar and above its page.
    public var titleKey: LocalizationKey {
        switch self {
        case .overview: .appTabOverview
        case .menu: .appMenuTitle
        case .agents: .appTabAgents
        case .config: .appTabConfig
        case .checks: .appTabChecks
        case .ai: .appTabAI
        case .worktrees: .appTabWorktrees
        case .folders: .appTabFolders
        }
    }
}

/// What a sidebar row shows beside its title.
public enum SetupBadge: Sendable, Equatable {
    /// This many checks are not ok and are not the person's to leave (`SetupSummary.attentionChecks`).
    case attention(Int)
}

extension SetupSummary {
    /// The badge of a sidebar row. Every tab is named, so a new one has to decide.
    public func badge(for tab: SetupTab) -> SetupBadge? {
        switch tab {
        case .checks: attentionChecks.isEmpty ? nil : .attention(attentionChecks.count)
        case .overview, .menu, .agents, .config, .ai, .worktrees, .folders: nil
        }
    }
}
