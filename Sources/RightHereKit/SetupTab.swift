import Foundation

/// The sections of the setup window. Navigation order and grouping are shared by the sidebar and View menu.
///
/// The window is for setup and status; the Finder extension and `rh` work without it. A section is here only when
/// the person can do or learn something in it: the first-run steps and the state of things, the menu the extension
/// builds, the checks behind the state, what to hand an AI assistant, the worktrees Right Here made for agents, and the
/// folders it remembers. What `rh` can do from a terminal and the window has no use for is not repeated here.
public enum SetupTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case menu
    case ai
    case folders
    case worktrees
    case checks

    public var id: String { rawValue }

    public static let navigationGroups: [[SetupTab]] = [
        [.overview, .menu, .ai],
        [.folders, .worktrees],
        [.checks]
    ]

    /// Numbered shortcuts follow the visible sections, across group separators.
    public var shortcutDigit: Character? {
        zip(Self.navigationGroups.joined(), "123456789").first { $0.0 == self }?.1
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
        case .overview, .menu, .ai, .worktrees, .folders: nil
        }
    }
}
