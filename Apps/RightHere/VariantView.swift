import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// The start options of an agent (ADR 0026): their lines on the page of the agent, the page of one of them, and the form for a new one. A start option is an entry of a file that adds arguments
// to the agent's command (`Use Opus` adds `--model opus`); the ones an agent has built in are only shown. A change is written to the config file that holds the entry at once, in the smallest way.

/// One start option as a line: its title, its arguments, and the chevron that opens its page when the config writes it.
struct VariantLine: View {
    let model: SetupModel
    let agent: String
    let title: String
    let arguments: [String]
    let tag: String?
    /// The page the line opens; `nil` for a start option that is only shown.
    let opens: VariantRef?
    @Environment(\.localizer) private var l10n

    private var content: some View {
        HStack(spacing: 10) {
            // A start option is a way to start the agent; the branch symbol is the worktrees'.
            Image(systemName: "play.circle")
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(verbatim: title)
                        .font(.body)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let tag {
                        Tag(text: tag)
                    }
                }
                if !arguments.isEmpty {
                    Text(verbatim: arguments.joined(separator: " "))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if opens != nil {
                Image(systemName: "chevron.forward")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(minHeight: 46)
        .contentShape(Rectangle())
    }

    var body: some View {
        if let opens {
            PlainButton(action: { model.openVariant(opens) }) { content }
                .accessibilityLabel(title)
                .accessibilityValue(arguments.joined(separator: " "))
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }
}

/// A start option as a page: its title, and the arguments it adds to the command.
struct VariantPage: View {
    let model: SetupModel
    let agent: String
    let id: String
    @Environment(\.localizer) private var l10n

    private func caption(_ key: LocalizationKey) -> some View {
        Text(l10n.string(key))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        // The way back and the start option's title stand in the window's header (`SetupModel.detailHeader`).
        VStack(alignment: .leading, spacing: PageRhythm.section) {
            if let row = model.variant(agent, id) {
                VStack(spacing: 0) {
                    OptionRow(label: l10n.string(.appPresetTitle)) {
                        EditableText(label: l10n.string(.appPresetTitle), prompt: l10n.string(.appPresetTitle), current: { model.variant(agent, id)?.title ?? "" },
                                     commit: { typed, _ in await model.setVariantTitle(agent, id, typed) })
                    }
                }
                .panel()
                VStack(alignment: .leading, spacing: PageRhythm.inSection) {
                    Text(l10n.string(.appAgentArguments))
                        .font(.headline)
                    ArgumentListPanel(model: model, owner: .variant(agent: agent, id: id), list: row.arguments)
                    caption(.appVariantArgumentsHelp)
                    if !row.arguments.isExact { caption(.appAgentArgumentsInexactNote) }
                }
                RemoveButton(title: l10n.string(.appVariantRemove)) { await model.removeVariant(agent, id) }
                ConfigEditBanner(model: model, tab: .agents, concerning: { $0.hasPrefix("agent.") })
            }
        }
        // Off while something that is not a change of the config runs (an install), as the page of an agent is: a change by place would be dropped.
        .disabled(model.isWorking && !model.isEditingConfig)
    }
}

/// A start option of one's own: a button that opens a form for its title; its arguments are added on its page.
struct NewVariantForm: View {
    let model: SetupModel
    let agent: String
    @State private var isOpen = false
    @State private var title = ""
    @Environment(\.localizer) private var l10n

    private func close() {
        isOpen = false
        title = ""
    }

    var body: some View {
        if isOpen {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 0) {
                    OptionRow(label: l10n.string(.appPresetTitle)) {
                        DraftField(label: l10n.string(.appPresetTitle), prompt: l10n.string(.appPresetTitle), text: $title)
                    }
                }
                .panel()
                Text(l10n.string(.appVariantNewCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(l10n.string(.appCancel)) { close() }
                        .keyboardShortcut(.cancelAction)
                    Button(l10n.string(.appVariantNewAdd)) {
                        Task {
                            let name = title
                            if let made = await model.createVariant(agent: agent, title: name) {
                                close()
                                // The page of what was just made, where its arguments are added.
                                model.openVariant(VariantRef(agent: agent, id: made))
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || model.isWorking)
                }
            }
        } else {
            Button(l10n.string(.appVariantNew)) { isOpen = true }
                .disabled(model.isWorking)
                .atTrailingEdge()
        }
    }
}
