import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// The sections of the setup window. Each is written from the model's answers; the words are catalog entries (`Localizer`), and what
// is only a name, a path or a command is `Text(verbatim:)`, so that a literal that a translation would miss does not get in.

/// The sentence that says how the setup stands.
func statusTitle(_ state: SetupSummary.State) -> LocalizationKey { state.titleKey }

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
        .accessibilityElement(children: .combine)
    }
}

/// A block of text that a person can copy: a JSON snippet or the commands of a plugin.
struct CodeBlock: View {
    let code: String

    var body: some View {
        Text(verbatim: code)
            .font(.system(size: 11, design: .monospaced))
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .textSelection(.enabled)
            // Code keeps its indentation and reading direction inside a mirrored interface.
            .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: Overview

/// How the setup stands, with the remaining task before an ordinary installation record.
struct OverviewPage: View {
    let model: SetupModel
    @State private var showSetupDetails = false
    private let l10n = Localizer.system

    private static let resultID = "setup-result"

    init(model: SetupModel, expandSetupDetails: Bool = false) {
        self.model = model
        _showSetupDetails = State(initialValue: expandSetupDetails)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 28) {
                if model.locationProblem != nil {
                    LocationCard()
                }
                if model.needsFirstRunChoice {
                    // A failed setup keeps the chooser and its report. A refusal that started nothing uses the window's feedback banner.
                    if let report = model.setupReport {
                        setupResult(report)
                            .id(Self.resultID)
                    }
                    // No config file yet: what is installed, to choose from, before anything is written.
                    FirstRunChooser(model: model)
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        if let report = model.setupReport, report.hasNews {
                            setupResult(report)
                        }
                        if model.summary.extensionNeedsSetup {
                            FinderSetupCard(model: model)
                        } else {
                            StatusCard(model: model)
                        }
                    }
                    .id(Self.resultID)

                    if let report = model.setupReport, !report.hasNews, model.summary.state != .allSet {
                        DisclosureGroup(isExpanded: $showSetupDetails) {
                            setupResult(report, showsTitle: false).padding(.top, 8)
                        } label: {
                            Text(l10n.string(.appSetupDoneTitle))
                                .font(.callout)
                        }
                    }

                    if model.snapshot != nil {
                        VStack(spacing: 18) {
                            Divider()
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 24) { defaults }
                                VStack(spacing: 18) { defaults }
                            }
                            Divider()
                        }
                    }
                }
            }
            // The button that was pressed may be far down the page; the answer is at the top.
            .onChange(of: model.setupAttempt) {
                proxy.scrollTo(Self.resultID, anchor: .top)
            }
        }
    }

    private func setupResult(_ report: SetupReport, showsTitle: Bool = true) -> some View {
        SetupDonePanel(report: report, home: model.homePath, extensionCheck: model.check(.finderExtension), showsTitle: showsTitle)
    }

    @ViewBuilder private var defaults: some View {
        defaultApp(.appCheckTerminal, icon: "terminal", name: model.summary.terminal)
        defaultApp(.appCheckEditor, icon: "chevron.left.forwardslash.chevron.right", name: model.summary.editor)
    }

    private func defaultApp(_ title: LocalizationKey, icon: String, name: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 28)
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The status once the Finder extension is on: a line that says whether anything needs the person, and which checks.
struct StatusCard: View {
    let model: SetupModel
    @Environment(\.setupPalette) private var palette
    private let l10n = Localizer.system

    var body: some View {
        let state = model.summary.state
        if state == .allSet {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    readyMessage.frame(minWidth: 244, idealWidth: 250, maxWidth: .infinity, alignment: .leading)
                    if model.menuState == .ready { menuSnapshot.frame(width: 260) }
                }
                VStack(alignment: .leading, spacing: 24) {
                    readyMessage
                    if model.menuState == .ready { menuSnapshot }
                }
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                symbol(state)
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.string(statusTitle(state)))
                        .font(.system(size: 22, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    if state == .needsAttention {
                        Text(model.summary.openTitles(in: l10n).formatted(.list(type: .and, width: .narrow)))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(l10n.string(.appOpenChecksHint))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(l10n.string(.appShowChecks)) { model.select(.checks) }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 8)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
        }
    }

    private var readyMessage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.string(.appAllSet))
                .font(.system(size: 25, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(l10n.string(.appAllSetHint))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(l10n.string(.appPreviewMenu)) { model.select(.menu) }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .padding(.top, 6)
    }

    private var menuSnapshot: some View {
        let rows = MenuPreview.rows(model.snapshot?.menu ?? []).filter { $0.kind != .separator }
        return VStack(alignment: .leading, spacing: 12) {
            Label(l10n.string(.appPreviewMenu), systemImage: "contextualmenu.and.cursorarrow")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 15) {
                ForEach(Array(rows.prefix(5))) { row in
                    HStack(spacing: 10) {
                        if let icon = model.image(for: row.icon) {
                            Image(nsImage: icon)
                                .renderingMode(icon.isTemplate ? .template : .original)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .accessibilityHidden(true)
                        }
                        Text(verbatim: row.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .help(row.title)
                        Spacer(minLength: 0)
                        if row.hasChildren {
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.rule, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n.string(.appPreviewMenu))
    }

    @ViewBuilder private func symbol(_ state: SetupSummary.State) -> some View {
        switch state {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
        case .allSet:
            EmptyView()
        case .needsAttention:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Color.orange)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        }
    }
}


/// The remaining Finder task, after the person has chosen their tools and the config exists.
struct FinderSetupCard: View {
    let model: SetupModel
    private let l10n = Localizer.system

    var body: some View {
        let check = model.check(.finderExtension)
        let action = check?.setupAction(firstRun: false)
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text(l10n.string(action == .extensionSettings ? .appStepTwoTitle : .appCheckExtension))
                    .font(.system(size: 22, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if action == .extensionSettings {
                    Text(l10n.string(.appStepTwoBody))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let detail = check?.detail {
                    Text(DoctorText.styled(l10n.render(detail, isolatingValues: true), home: model.homePath))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let action {
                    Button(l10n.string(action.title)) { Task { await model.perform(action) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isWorking || (action == .repair && model.locationProblem != nil))
                } else {
                    Button(l10n.string(.appShowChecks)) { model.select(.checks) }
                        .buttonStyle(.borderedProminent)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.string(.appStepThreeTitle))
                    .font(.callout.weight(.medium))
                Text(l10n.string(.appStepThreeBody))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if action != nil {
                    Button(l10n.string(.appShowChecks)) { model.select(.checks) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
            if model.menuState == .ready {
                Text(l10n.string(.appMenuCaption))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch model.menuState {
            case .loading:
                ProgressRow(message: .appChecking)
            case .needsSetup:
                emptyState(.appMenuNeedsSetup, symbol: "slider.horizontal.3", action: .appSetupButton) { model.select(.overview) }
            case .invalidConfig:
                emptyState(.appMenuConfigError, symbol: "exclamationmark.triangle", action: .appShowChecks) { model.select(.checks) }
            case .empty:
                emptyState(.appMenuEmpty, symbol: "contextualmenu.and.cursorarrow", action: .appShowChecks) { model.select(.checks) }
            case .ready:
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

    private func emptyState(_ message: LocalizationKey, symbol: String, action: LocalizationKey, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(l10n.string(message))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button(l10n.string(action), action: perform)
                .buttonStyle(.bordered)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
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
                .buttonStyle(SetupQuietButtonStyle())
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
                .foregroundStyle(.primary)
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
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .accessibilityElement(children: .contain)
    }
}
