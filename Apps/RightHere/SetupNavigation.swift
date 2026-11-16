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

/// Open the diagnosed file directly, or let the person choose when both configuration layers exist.
struct OpenConfigControl: View {
    let snapshot: SetupSnapshot?
    var preferred: SetupConfigFile? = nil
    var showIcon = false
    let open: (SetupConfigFile?) -> Void
    private let l10n = Localizer.system

    var body: some View {
        if let preferred, let snapshot {
            Button(l10n.render(.appOpenConfigFile(name(preferred, in: snapshot)), isolatingValues: true)) {
                open(preferred)
            }
        } else if let snapshot, snapshot.configFiles.count > 1 {
            #if PREVIEW
            // ImageRenderer cannot draw a native menu. Its closed label stands in for it in canned previews.
            HStack(spacing: 4) {
                label
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .fixedSize()
            #else
            Menu {
                ForEach(snapshot.configFiles) { file in
                    Button { open(file) } label: {
                        Text(verbatim: name(file, in: snapshot))
                    }
                    .help(PathDisplay.abbreviatingHome(file.url(relativeTo: snapshot.configFile).path.withControlCharactersEscaped,
                                                     home: snapshot.home.path))
                }
            } label: {
                label
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            #endif
        } else {
            Button { open(snapshot?.configFiles.first) } label: {
                label
            }
        }
    }

    @ViewBuilder private var label: some View {
        if showIcon {
            Label(l10n.string(.appOpenConfig), systemImage: "square.and.pencil")
        } else {
            Text(l10n.string(.appOpenConfig))
        }
    }

    private func name(_ file: SetupConfigFile, in snapshot: SetupSnapshot) -> String {
        file.url(relativeTo: snapshot.configFile).lastPathComponent.withControlCharactersEscaped
    }
}
