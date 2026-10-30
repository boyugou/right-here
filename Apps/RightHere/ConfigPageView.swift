import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// The Config page (ADR 0026): the settings file as text, with what the config says about the text as it is typed; the changes an AI assistant proposed that wait for the person;
// and the changes that can be taken back. Everything written here goes through the same editor as `rh config`, so a change is checked, atomic and kept for undo.

struct ConfigPage: View {
    let model: SetupModel
    @Environment(\.localizer) private var l10n
    #if STANDINS
    @Environment(\.colorScheme) private var colorScheme
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: PageRhythm.section) {
            Text(DoctorText.styled(l10n.string(.appConfigCaption), home: model.homePath))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.snapshot == nil {
                ProgressRow(message: .appChecking)
            } else if !model.configIsThere {
                Text(l10n.string(.appConfigNone))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let page = model.configPage {
                ForEach(page.proposals) { preview in
                    ProposalCard(model: model, preview: preview)
                }
                // The file, what is wrong in it and the buttons that save it: one section.
                VStack(alignment: .leading, spacing: PageRhythm.inSection) {
                    filePicker
                    // What the file shown is for, under both: the two names alone did not say which one to change.
                    Text(verbatim: l10n.string(page.target == .local ? .appConfigLocalNote : .appConfigSharedNote))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let problem = page.problem {
                        Text(verbatim: problem)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        if page.fileMovedUnderDraft {
                            movedUnderDraft
                        }
                        editor
                        // What the check of the text says at the leading edge, the buttons that save it at the trailing edge, on one row.
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            problems
                            Spacer(minLength: 0)
                            buttons
                        }
                    }
                }
                HistoryList(model: model, history: page.history)
            } else {
                ProgressRow(message: .appChecking)
            }
        }
    }

    /// config.toml, or this Mac's own file. Not while there is text that is not saved: switching would throw it away.
    @ViewBuilder private var filePicker: some View {
        #if STANDINS
        // A segmented control is drawn by AppKit, which `ImageRenderer` shows as a "not allowed" sign. The stand-in has the control's measures on macOS 27.2
        // (`preview_setup.sh --real-controls`): a capsule 24 points tall, the chosen segment a capsule of the track's height, raised.
        HStack(spacing: 0) {
            ForEach([ConfigTarget.shared, .local], id: \.self) { target in
                Text(verbatim: tabTitle(target))
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .frame(height: 23)
                    .background {
                        if model.configTarget == target {
                            // Raised and light, as in a window in front: white, or in dark lighter than the track.
                            Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.white).shadow(color: Color.black.opacity(0.15), radius: 1.5, y: 0.5)
                        }
                    }
            }
        }
        .padding(0.5)
        .background(Color.primary.opacity(0.08), in: Capsule())
        #else
        Picker("", selection: Binding(get: { model.configTarget }, set: { target in Task { await model.chooseConfigFile(target) } })) {
            Text(verbatim: tabTitle(.shared)).tag(ConfigTarget.shared)
            Text(verbatim: tabTitle(.local)).tag(ConfigTarget.local)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(model.textHasChanges || model.isWorking)
        #endif
    }

    /// A file by what it is for, then its name: Shared (config.toml), This Mac Only (config.local.toml).
    private func tabTitle(_ target: ConfigTarget) -> String {
        target == .shared ? l10n.render(.appConfigTabShared("config.toml")) : l10n.render(.appConfigTabLocal("config.local.toml"))
    }

    /// Something else changed the file after the person began to type: a save is refused until they have looked.
    private var movedUnderDraft: some View {
        Label {
            Text(l10n.string(.appConfigMovedUnderDraft))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
        }
    }

    private var editor: some View {
        // A field of text, as the contents of a template are: the ground and the edge of a text field. On the group's grey it read as a picture of text, as
        // the snippets of the AI Assistants page are (a design review of 0.3.21).
        ConfigTextEditor(text: Binding(get: { model.draftText }, set: { model.draftText = $0 }), label: l10n.string(.appConfigEditorLabel))
            .frame(height: 320)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
    }

    /// What the config says about the text as it is, a line each; warnings are the person's to read and do not stop a save, errors do.
    @ViewBuilder private var problems: some View {
        let found = model.draftProblems
        VStack(alignment: .leading, spacing: 4) {
            if found.isEmpty {
                Label(l10n.string(.appConfigNoProblems), systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(l10n.string(.appConfigProblemsHeading))
                    .font(.headline)
                ForEach(Array(found.prefix(12).enumerated()), id: \.offset) { _, problem in
                    Label {
                        Text(verbatim: Self.line(of: problem))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: problem.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(problem.severity == .error ? Color.red : Color.orange)
                    }
                }
                if found.count > 12 {
                    Text(verbatim: "+\(found.count - 12)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// `line 4 [general.terminal]: unknown terminal ...`: the config's own words, which are English.
    static func line(of problem: ConfigDiagnostic) -> String {
        (problem.line.map { "line \($0) " } ?? "") + (problem.path.isEmpty ? "" : "[\(problem.path)] ") + problem.message
    }

    /// The buttons at the trailing edge, the one that saves last, as a sheet of macOS has them and as every other page of the window does; what is not saved
    /// yet is said before them.
    private var buttons: some View {
        HStack(spacing: 10) {
            if model.textHasChanges {
                Text(l10n.string(.appConfigUnsaved))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button(l10n.string(.appConfigRevert)) { Task { await model.revertConfigText() } }
                .disabled(!model.textHasChanges || model.isWorking)
            Button(l10n.string(.appConfigSave)) { Task { await model.saveConfigText() } }
                .keyboardShortcut("s", modifiers: .command)
                .modifier(DefaultButton(enabled: model.textHasChanges && !model.isWorking && !model.draftProblems.contains { $0.severity == .error }))
        }
    }
}

/// A change an assistant proposed: what it is, why it waits, what it would change in the file as it is now, and the two ways to answer.
private struct ProposalCard: View {
    let model: SetupModel
    let preview: ProposalPreview
    @Environment(\.localizer) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The card says it is a warning by its colour and the symbol's; orange words on it were hard to read.
            Label {
                Text(l10n.string(.appConfigProposalHeading))
            } icon: {
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(Color.orange)
            }
            .font(.headline)
            Text(l10n.string(.appConfigProposalExplain))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: preview.proposal.summary)
                .font(.system(.callout, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, .leftToRight)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(preview.proposal.approvals, id: \.key) { approval in
                Text(verbatim: "\(approval.key): " + (approval.reasonKey.map { l10n.string($0) + (approval.effect.map { ": " + $0 } ?? "") } ?? approval.reason))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let change = preview.change {
                DiffLines(lines: change.diff)
            } else if let problem = preview.problem {
                Text(verbatim: problem)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(l10n.string(.appConfigDismiss)) { Task { await model.dismissProposal(preview.id) } }
                    .disabled(model.isWorking)
                Button(l10n.string(.appConfigApply)) { Task { await model.approveProposal(preview.id) } }
                    .modifier(DefaultButton(enabled: preview.change != nil && !model.isWorking))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .callout(.orange)
        .accessibilityElement(children: .contain)
    }
}

/// A unified diff: removed lines red, added lines green, the rest as it is. The lines are the config's own, as it holds them.
private struct DiffLines: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line.isEmpty ? " " : line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(color(of: line))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        // Code reads from the left in every language.
        .environment(\.layoutDirection, .leftToRight)
    }

    private func color(of line: String) -> Color {
        switch line.first {
        case "+": return .green
        case "-": return .red
        case "@": return .secondary
        default: return .primary
        }
    }
}

/// The latest changes of the file, newest first; the newest has Undo.
private struct HistoryList: View {
    let model: SetupModel
    let history: [ConfigService.HistoryItem]
    @Environment(\.localizer) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            Text(l10n.string(.appConfigHistoryHeading))
                .font(.headline)
            if history.isEmpty {
                EmptyList { Text(l10n.string(.appConfigNoHistory)) }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(history.prefix(8).enumerated()), id: \.offset) { index, item in
                        if index > 0 { RowDivider() }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: item.summary)
                                    .font(.system(.callout, design: .monospaced))
                                    .lineLimit(2)
                                    .environment(\.layoutDirection, .leftToRight)
                                Text(l10n.render(.appConfigBy(who(item.actor))) + " · " + when(item.time))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if index == 0 {
                                Button(l10n.string(.appMenuUndo)) { Task { await model.undoConfigChange() } }
                                    .disabled(model.isWorking)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    }
                }
                .panel()
            }
        }
    }

    /// "2 hours ago" in the language of the system; the preview, whose dates are canned, writes the date, so that the picture is the same whenever it is made.
    private func when(_ date: Date) -> String {
        #if PREVIEW
        date.formatted(date: .abbreviated, time: .shortened)
        #else
        date.formatted(.relative(presentation: .named))
        #endif
    }

    private func who(_ actor: ConfigActor) -> String {
        switch actor {
        case .window: l10n.string(.appConfigWhoWindow)
        case .cli: l10n.string(.appConfigWhoCLI)
        case .mcp: l10n.string(.appConfigWhoAssistant)
        }
    }
}

/// A plain-text editor for the config: a monospaced `NSTextView` with every automatic substitution off (smart quotes would turn the quotes of TOML into ones it cannot read),
/// undo, and no rich text. In the preview, which draws nothing for a view that AppKit draws, it is the text itself.
private struct ConfigTextEditor: View {
    @Binding var text: String
    let label: String

    var body: some View {
        #if STANDINS
        Text(verbatim: text)
            .font(.system(size: 12, design: .monospaced))
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.layoutDirection, .leftToRight)
        #else
        PlainTextView(text: $text, label: label)
        #endif
    }
}


/// On the Overview, a line that says changes wait for the person, with the way to the page where they are.
struct ProposalsNotice: View {
    let model: SetupModel
    @Environment(\.localizer) private var l10n

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield")
                .font(.title3)
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            Text(l10n.string(.appProposalsWaiting))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(l10n.string(.appProposalsReview)) { model.select(.config) }
        }
        .padding(14)
        .callout(.orange)
        .accessibilityElement(children: .combine)
    }
}
