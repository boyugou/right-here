import RightHereCore
import RightHereKit
import SwiftUI

extension SetupTab {
    var title: LocalizationKey {
        switch self {
        case .overview: .appTabOverview
        case .menu: .appMenuTitle
        case .checks: .appTabChecks
        case .ai: .appTabAI
        case .worktrees: .appTabWorktrees
        case .folders: .appTabFolders
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .menu: "contextualmenu.and.cursorarrow"
        case .checks: "checklist"
        case .ai: "sparkle"
        case .worktrees: "arrow.triangle.branch"
        case .folders: "folder"
        }
    }

    var shortcut: KeyboardShortcut? {
        shortcutDigit.map { KeyboardShortcut(KeyEquivalent($0), modifiers: .command) }
    }
}

/// View-menu commands make the shortcuts discoverable and use the same selection path as the sidebar.
struct SetupCommands: Commands {
    let model: SetupModel
    private let l10n = Localizer.system

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button(l10n.string(.appFindFolders)) { model.findFolders() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!model.canFindFolders)
        }
        CommandGroup(after: .sidebar) {
            ForEach(Array(SetupTab.navigationGroups.enumerated()), id: \.offset) { index, tabs in
                if index > 0 { Divider() }
                ForEach(tabs) { tab in
                    Button(l10n.string(tab.title)) { model.select(tab) }
                        .keyboardShortcut(tab.shortcut)
                }
            }
            Divider()
            Button(l10n.string(.appRefresh)) { Task { await model.refresh() } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isRefreshing || model.isWorking)
        }
    }
}
