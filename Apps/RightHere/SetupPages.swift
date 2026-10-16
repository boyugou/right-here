import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// The sections of the setup window. Each is written from the model's answers; the words are catalog entries (`Localizer`), and what
// is only a name, a path or a command is `Text(verbatim:)`, so that a literal that a translation would miss does not get in.

extension View {
    /// A panel of the window: the control background with a hairline edge, which holds up in both appearances.
    func panel(cornerRadius: CGFloat = 10) -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

/// The sentence that says how the setup stands.
func statusTitle(_ state: SetupSummary.State) -> LocalizationKey {
    switch state {
    case .checking: .appChecking
    case .allSet: .appAllSet
    case .needsAttention: .appNeedsAttention
    }
}

/// What the doctor says, written for the window: a command between backticks is code, and a path starts from `~`.
enum DoctorText {
    static func styled(_ text: String, home: String) -> AttributedString {
        var result = AttributedString()
        for (index, part) in PathDisplay.abbreviatingHome(text, home: home).split(separator: "`", omittingEmptySubsequences: false).enumerated() {
            var piece = AttributedString(String(part))
            if index % 2 == 1 { piece.font = .system(.callout, design: .monospaced) }
            result += piece
        }
        return result
    }
}

/// A sentence of the catalog that may name a command between backticks: the command is written as code, as the doctor's are.
struct Prose: View {
    let key: LocalizationKey
    let home: String

    var body: some View {
        Text(DoctorText.styled(Localizer.system.string(key), home: home))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A line that says what is happening, with a spinner.
struct ProgressRow: View {
    let message: LocalizationKey

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(Localizer.system.string(message))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// What the last action said: a confirmation, or why it did not work (with the symbol that says which).
struct NoticeLine: View {
    let notice: SetupNotice
    var font: Font = .caption2
    private let l10n = Localizer.system

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: notice.isProblem ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isProblem ? Color.orange : Color.green)
                .accessibilityHidden(true)
            Text(l10n.render(notice.message, isolatingValues: true))
                .font(font)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

/// A block of text that a person can copy: a JSON snippet or the commands of a plugin.
struct CodeBlock: View {
    let code: String

    var body: some View {
        Text(verbatim: code)
            .font(.system(size: 11, design: .monospaced))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .textSelection(.enabled)
    }
}

// MARK: Overview

/// How the setup stands, and the first steps while the Finder extension is off.
struct OverviewPage: View {
    let model: SetupModel
    private let l10n = Localizer.system

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.needsFirstRunChoice {
                // No config file yet: what is installed, to choose from, before anything is written.
                FirstRunChooser(model: model)
                // A Set Up that did not come out leaves no config, so the chooser stays: what went wrong is said here, where the person is
                // looking, and not only in the footnote of the sidebar. A refusal that started nothing (the app runs from a disk image) has
                // no report, only the notice.
                if let report = model.setupReport {
                    SetupDonePanel(report: report, home: model.homePath, extensionIsOn: !model.summary.extensionNeedsSetup)
                } else if let notice = model.notice, notice.isProblem {
                    NoticeLine(notice: notice, font: .callout)
                }
            } else {
                if let report = model.setupReport, model.summary.state != .allSet || report.hasNews {
                    SetupDonePanel(report: report, home: model.homePath, extensionIsOn: !model.summary.extensionNeedsSetup)
                }

                if model.summary.extensionNeedsSetup {
                    FirstRunCard(model: model)
                } else {
                    StatusCard(model: model)
                }

                HStack(alignment: .top, spacing: 14) {
                    defaultApp(.appCheckTerminal, icon: "terminal", name: model.summary.terminal)
                    defaultApp(.appCheckEditor, icon: "chevron.left.forwardslash.chevron.right", name: model.summary.editor)
                }
            }
        }
    }

    private func defaultApp(_ title: LocalizationKey, icon: String, name: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.string(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.checks.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(name ?? l10n.string(.appNoneFound))
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .accessibilityElement(children: .combine)
    }
}

/// The status once the Finder extension is on: a line that says whether anything needs the person, and which checks.
struct StatusCard: View {
    let model: SetupModel
    private let l10n = Localizer.system

    var body: some View {
        let state = model.summary.state
        HStack(alignment: .top, spacing: 16) {
            symbol(state)
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.string(statusTitle(state)))
                    .font(.headline)
                if state == .allSet {
                    Text(l10n.string(.appAllSetHint))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if state == .needsAttention {
                    Text(model.summary.openTitles(in: l10n).formatted(.list(type: .and, width: .narrow)))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(l10n.string(.appOpenChecksHint))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(l10n.string(.appShowChecks)) { model.select(.checks) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    @ViewBuilder private func symbol(_ state: SetupSummary.State) -> some View {
        switch state {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 40, height: 40)
        case .allSet:
            Image(systemName: "checkmark.seal.fill")
                .font(.title)
                .foregroundStyle(Color.green)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
        case .needsAttention:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(Color.orange)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
        }
    }
}

/// The three steps of a first run, in order, and a way around the extension. Shown until the extension is switched on.
struct FirstRunCard: View {
    let model: SetupModel
    private let l10n = Localizer.system

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(l10n.string(.appOnboardTitle))
                .font(.headline)

            step(1, title: .appStepOneTitle, body: .appStepOneBody,
                 done: model.check(.terminalDefault)?.status == .ok && model.check(.editorDefault)?.status == .ok) {
                ForEach([CheckID.terminalDefault, .editorDefault], id: \.self) { id in
                    if let detail = model.check(id)?.detail {
                        Text(DoctorText.styled(l10n.render(detail, isolatingValues: true), home: model.homePath))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                Button(l10n.string(.appOpenConfig)) { Task { await model.openConfig() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isWorking)
            }

            step(2, title: .appStepTwoTitle, body: .appStepTwoBody, done: false) {
                Button(l10n.string(.appExtensionSettings)) { model.showExtensionSettings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            step(3, title: .appStepThreeTitle, body: .appStepThreeBody, done: false) {
                Button(l10n.string(.appTestLaunch)) { Task { await model.testLaunch() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isWorking || model.isRefreshing)
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.string(.appQuickActionsTitle))
                    .font(.callout.weight(.medium))
                Text(l10n.string(.appQuickActionsBody))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1.5))
    }

    private func step<Actions: View>(_ number: Int, title: LocalizationKey, body: LocalizationKey, done: Bool,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.accentColor)
                if done {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text(number.formatted())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.string(title))
                    .font(.body.weight(.medium))
                Text(l10n.string(body))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n.render(.appStepLabel(number.formatted(), l10n.string(title))))
    }
}

// MARK: Finder menu

/// The menu Finder shows for a folder, built by the code the extension runs: the lines it would show, with the submenus that open
/// in place.
struct MenuPage: View {
    let model: SetupModel
    private let l10n = Localizer.system

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.string(.appMenuCaption))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.snapshot == nil {
                ProgressRow(message: .appChecking)
            } else if model.menuRows.isEmpty {
                Text(l10n.string(.appMenuEmpty))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.menuRows) { row in
                        MenuLine(row: row, image: model.image(for: row.icon)) {
                            model.toggleSubmenu(row.id)
                        }
                    }
                }
                .panel()
            }
        }
    }
}

/// One line of the Finder menu preview: what Finder's menu line looks like, and nothing that acts. A submenu opens and closes in
/// place; an entry does nothing when it is clicked.
struct MenuLine: View {
    let row: MenuPreviewRow
    let image: NSImage?
    let toggle: () -> Void
    private let l10n = Localizer.system

    var body: some View {
        switch row.kind {
        case .separator:
            Divider()
                .padding(.horizontal, 14)
                .accessibilityHidden(true)
        case .submenu where row.hasChildren:
            Button(action: toggle) { line }
                .buttonStyle(.plain)
                .accessibilityValue(l10n.string(row.isExpanded ? .appMenuSubmenuExpanded : .appMenuSubmenuCollapsed))
        case .action, .submenu:
            line.accessibilityElement(children: .combine)
        }
    }

    private var line: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(row.title)
                .font(.body)
            Spacer(minLength: 8)
            if row.hasChildren {
                // Not a rotated chevron: the forward one is drawn mirrored in a right-to-left language, the down one is not.
                Image(systemName: row.isExpanded ? "chevron.down" : "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 14 + CGFloat(row.level) * 24)
        .padding(.trailing, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        if let image {
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary)
        }
    }
}

// MARK: Checks

/// Every check of the doctor, with what it found and what to do. The launch test is here, where its answer goes.
struct ChecksPage: View {
    let model: SetupModel
    private let l10n = Localizer.system

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text(l10n.string(statusTitle(model.summary.state)))
                    .font(.body.weight(.medium))
                Spacer(minLength: 12)
                Button {
                    Task { await model.testLaunch() }
                } label: {
                    Label(l10n.string(.appTestLaunch), systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isWorking || model.isRefreshing)
            }

            if model.isTestingLaunch {
                ProgressRow(message: .appTesting)
            }

            if model.checks.isEmpty {
                ProgressRow(message: .appChecking)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.checks.enumerated()), id: \.element.id) { index, check in
                        CheckRow(check: check, home: model.homePath)
                        if index < model.checks.count - 1 {
                            Divider()
                                .padding(.horizontal, 14)
                        }
                    }
                }
                .panel()
            }
        }
    }
}

/// One check: its title, what was found, its notes and what to do. The status is spoken once, as the value of the row.
struct CheckRow: View {
    let check: DoctorCheck
    let home: String
    private let l10n = Localizer.system

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(check.title(in: l10n))
                    .font(.body.weight(.medium))
                if let detail = check.detail {
                    line(detail, .secondary)
                }
                ForEach(Array(check.notes.enumerated()), id: \.offset) { _, note in
                    line(note, .secondary)
                }
                if let fix = check.fix {
                    line(fix, .primary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // One stop for VoiceOver per check (title, detail and fix read together) instead of three.
        .accessibilityElement(children: .combine)
        .accessibilityValue(l10n.string(statusKey))
    }

    /// One line of what the doctor says, in the system language, as long as it needs to be. A path or a command in a right-to-left
    /// sentence stays in one piece, and the text stays selectable (a fix is a command a person copies).
    private func line(_ message: LocalizedMessage, _ style: HierarchicalShapeStyle) -> some View {
        Text(DoctorText.styled(l10n.render(message, isolatingValues: true), home: home))
            .font(.callout)
            .foregroundStyle(style)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private var statusKey: LocalizationKey {
        switch check.status {
        case .ok: .appStatusOK
        case .warn: .appStatusWarning
        case .fail: .appStatusProblem
        case .needsUser: .appStatusNeedsYou
        }
    }

    private var symbol: String {
        switch check.status {
        case .ok: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.octagon.fill"
        case .needsUser: "hand.raised.fill"
        }
    }

    private var color: Color {
        switch check.status {
        case .ok: .green
        case .warn: .orange
        case .fail: .red
        case .needsUser: .blue
        }
    }
}

// MARK: AI assistants

/// What to give an AI assistant: the prompt that sets Right Here up, the MCP server it can connect to, the Claude Code plugin.
struct AIPage: View {
    let model: SetupModel
    private let l10n = Localizer.system

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            section(.appAiPromptTitle) {
                Prose(key: .appAiPromptBody, home: model.homePath)
                Button(l10n.string(.appCopySetupPrompt)) { model.copySetupPrompt() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            section(.appAiMCPTitle) {
                Prose(key: .appAiMCPBody, home: model.homePath)
                CodeBlock(code: SetupSnippets.mcpConfiguration(command: model.mcpCommand))
                Button(l10n.string(.appCopyMCPConfig)) { model.copyMCPConfiguration() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            section(.appAiPluginTitle) {
                Prose(key: .appAiPluginBody, home: model.homePath)
                CodeBlock(code: SetupSnippets.pluginCommands)
                Button(l10n.string(.appCopyPluginCommands)) { model.copyPluginCommands() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func section<Content: View>(_ title: LocalizationKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.string(title))
                .font(.headline)
            content()
        }
    }
}

// MARK: Worktrees

/// The git worktrees Right Here made for agents, in one repository. Only those can be removed here, never forced.
struct WorktreesPage: View {
    let model: SetupModel
    @State private var pending: WorktreeRow?
    private let l10n = Localizer.system

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Prose(key: .appWorktreesIntro, home: model.homePath)

            repositoryBar

            listing
        }
        .confirmationDialog(l10n.string(.appRemoveWorktreeTitle), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button(l10n.string(.appRemoveWorktreeConfirm), role: .destructive) {
                if let row = pending { Task { await model.remove(row) } }
                pending = nil
            }
            Button(l10n.string(.appCancel), role: .cancel) {
                pending = nil
            }
        } message: {
            if let row = pending {
                Text(l10n.render(.appRemoveWorktreeMessage(PathDisplay.folder(row.entry.path, home: model.homePath)), isolatingValues: true))
            }
        }
    }

    private var repositoryBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(l10n.string(.appWorktreesRepository))
                .font(.callout.weight(.medium))

            if model.repositories.count > 1, let repository = model.repository {
                Menu {
                    ForEach(model.repositories, id: \.path) { root in
                        Button(PathDisplay.folder(root.path, home: model.homePath)) { model.selectRepository(root) }
                    }
                } label: {
                    Text(verbatim: PathDisplay.folder(repository.path, home: model.homePath))
                        .font(.system(size: 11, design: .monospaced))
                        .environment(\.layoutDirection, .leftToRight)
                }
                .fixedSize()
            } else if let repository = model.repository {
                Text(verbatim: PathDisplay.folder(repository.path, home: model.homePath))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                .environment(\.layoutDirection, .leftToRight)
            }

            Spacer(minLength: 8)

            Button {
                Task { await model.chooseRepository() }
            } label: {
                Label(l10n.string(.appWorktreesChoose), systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isWorking)
        }
    }

    @ViewBuilder private var listing: some View {
        switch model.worktrees {
        case .idle:
            Text(l10n.string(.appWorktreesNoRepository))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .loading:
            ProgressRow(message: .appLoading)
        case .failed(let text):
            Text(verbatim: text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .loaded(let rows):
            VStack(spacing: 8) {
                ForEach(rows) { row in
                    WorktreeLine(row: row, home: model.homePath, disabled: model.isWorking) {
                        pending = row
                    }
                }
            }
        }
    }
}

/// One worktree of the list: its branch, where it is, and the one action the window offers for it.
struct WorktreeLine: View {
    let row: WorktreeRow
    let home: String
    let disabled: Bool
    let onRemove: () -> Void
    private let l10n = Localizer.system

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: row.isMainWorkingCopy ? "house" : "arrow.triangle.branch")
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(verbatim: row.branchTitle ?? l10n.string(.appWorktreeDetached))
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if row.isMainWorkingCopy {
                        tag(.appWorktreeMain)
                    } else if row.canBeRemoved {
                        tag(.appWorktreeMadeHere)
                    }
                }
                Text(verbatim: PathDisplay.folder(row.entry.path, home: home))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                .environment(\.layoutDirection, .leftToRight)
            }

            Spacer(minLength: 8)

            if row.canBeRemoved {
                Button(l10n.string(.appRemoveWorktree), action: onRemove)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(disabled)
                    .accessibilityLabel(l10n.render(.appRemoveWorktreeNamed(row.entry.path.split(separator: "/").last.map(String.init) ?? "")))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(cornerRadius: 8)
    }

    private func tag(_ key: LocalizationKey) -> some View {
        Text(l10n.string(key))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
    }
}

// MARK: Folders

/// The folders Right Here remembers: the pinned ones and the recent ones, kept on this Mac and readable only by its user.
struct FoldersPage: View {
    let model: SetupModel
    private let l10n = Localizer.system

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(l10n.string(.appFoldersNote))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            pinned

            recent
        }
    }

    private var pinned: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.string(.appPinnedFolders))
                .font(.headline)
            if model.folders.pins.isEmpty {
                Prose(key: .appNoPinned, home: model.homePath)
            } else {
                VStack(spacing: 6) {
                    ForEach(model.folders.pins, id: \.self) { path in
                        folderLine(path, icon: "pin.fill") {
                            Button(l10n.string(.appUnpin)) { Task { await model.unpin(path) } }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(model.isWorking || model.isRefreshing)
                                .accessibilityLabel(l10n.render(.appUnpinFolder(PathDisplay.folder(path, home: model.homePath)), isolatingValues: true))
                        }
                    }
                }
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(l10n.string(.appRecentFolders))
                    .font(.headline)
                Spacer(minLength: 8)
                if !model.folders.recents.isEmpty {
                    Button(l10n.string(.appClearRecents)) { Task { await model.clearRecents() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.isWorking || model.isRefreshing)
                }
            }
            if model.folders.recents.isEmpty {
                Text(l10n.string(.appNoRecents))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(model.folders.recents, id: \.self) { path in
                        folderLine(path, icon: "clock") { EmptyView() }
                    }
                }
            }
        }
    }

    private func folderLine<Trailing: View>(_ path: String, icon: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(verbatim: PathDisplay.folder(path, home: model.homePath))
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .environment(\.layoutDirection, .leftToRight)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(cornerRadius: 8)
    }
}
