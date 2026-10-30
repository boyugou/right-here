import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// The prompt presets on the Agents page (ADR 0026): their lines under the agents, the page of one of them, and the form for a new one. A preset that comes with the app is read as it is and
// made the person's own with "Customize"; a change of a preset of one's own is written to the config file that holds it at once, in the smallest way, and can be undone from the note below.

/// The most files a preset takes can be chosen among these, and the one it has.
private let maxFilesChoices = [1, 2, 3, 5, 10, 20, 30, 50]

/// The lines of the presets and the button for a new one, under the agents of the Agents page.
struct PresetsPanel: View {
    let model: SetupModel
    let presets: PresetsState
    @Environment(\.localizer) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            Text(l10n.string(.groupPresets))
                .font(.headline)
            Text(l10n.string(.appPresetsCaption2))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LinedRows {
                ForEach(presets.rows) { row in
                    PresetRowLine(model: model, row: row)
                }
            }
            NewPresetForm(model: model)
            // A change of the presets is said under them, where it was made.
            ConfigEditBanner(model: model, tab: .agents, concerning: Self.concerns)
        }
    }

    static func concerns(_ key: String) -> Bool { key.hasPrefix("preset.") }
}

/// One preset as a line: its title with what it is (built in, customized), the start of its prompt, and the chevron that opens it.
private struct PresetRowLine: View {
    let model: SetupModel
    let row: PresetRowState
    @Environment(\.localizer) private var l10n

    private var tag: String? {
        switch row.origin {
        case .builtIn: l10n.string(.appPresetTagBuiltIn)
        case .customized: l10n.string(.appPresetTagCustomized)
        case .own: nil
        }
    }

    var body: some View {
        PlainButton(action: { model.openPreset(row.id) }) {
            HStack(spacing: 10) {
                Image(systemName: "text.quote")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(verbatim: row.title)
                            .font(.body)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let tag {
                            Tag(text: tag)
                        }
                    }
                    Text(verbatim: row.prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(row.title)
        .accessibilityValue([tag, row.prompt].compactMap { $0 }.joined(separator: ". "))
    }
}

/// A preset as a page: its title, its prompt, the agent that runs it and the most files it takes.
struct PresetPage: View {
    let model: SetupModel
    let id: String
    @Environment(\.localizer) private var l10n

    var body: some View {
        // The way back and the preset's title stand in the window's header (`SetupModel.detailHeader`).
        VStack(alignment: .leading, spacing: PageRhythm.section) {
            if let row = model.preset(id), let presets = model.presets {
                if row.origin == .builtIn {
                    VStack(alignment: .leading, spacing: PageRhythm.inSection) {
                        readOnly(row, presets)
                        caption(.appPresetBuiltInNote)
                        Button(l10n.string(.appPresetCustomize)) { Task { await model.customizePreset(row.id) } }
                            .buttonStyle(.bordered)
                    }
                } else if row.entry == nil {
                    // The config writes it in a form that has no place to change it by (an inline array): it is shown, and said so.
                    VStack(alignment: .leading, spacing: PageRhythm.inSection) {
                        readOnly(row, presets)
                        caption(.appEntryNotEditable)
                    }
                } else {
                    editable(row, presets)
                }
                ConfigEditBanner(model: model, tab: .agents, concerning: { $0.hasPrefix("preset.") })
            }
        }
    }

    private func caption(_ key: LocalizationKey) -> some View {
        Text(l10n.string(key))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func agentName(_ row: PresetRowState, _ presets: PresetsState) -> String {
        row.agent.map { id in presets.agents.first { $0.id == id }?.name ?? id } ?? l10n.string(.appPresetAgentFirst)
    }

    // MARK: A preset that comes with the app

    @ViewBuilder private func readOnly(_ row: PresetRowState, _ presets: PresetsState) -> some View {
        VStack(spacing: 0) {
            OptionRow(label: l10n.string(.appPresetTitle)) { Text(verbatim: row.title) }
            RowDivider()
            OptionRow(label: l10n.string(.appPresetPrompt), stacked: true) {
                Text(verbatim: row.prompt)
                    .fixedSize(horizontal: false, vertical: true)
            }
            RowDivider()
            OptionRow(label: l10n.string(.appPresetAgent)) { Text(verbatim: agentName(row, presets)) }
            RowDivider()
            OptionRow(label: l10n.string(.appPresetMaxFiles)) { Text(verbatim: "\(row.maxFiles)") }
        }
        .panel()
    }

    // MARK: A preset the person can change

    @ViewBuilder private func editable(_ row: PresetRowState, _ presets: PresetsState) -> some View {
        let unknownAgent = row.agent.flatMap { id in presets.agents.contains { $0.id == id } ? nil : id }
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            VStack(spacing: 0) {
                OptionRow(label: l10n.string(.appPresetTitle)) {
                    EditableText(label: l10n.string(.appPresetTitle), prompt: l10n.string(.appPresetTitle), current: { model.preset(id)?.title ?? "" },
                                 commit: { typed, _ in await model.setPresetTitle(id, typed) })
                }
                RowDivider()
                OptionRow(label: l10n.string(.appPresetPrompt), stacked: true) {
                    EditableText(label: l10n.string(.appPresetPrompt), prompt: l10n.string(.appPresetPrompt), wraps: true, current: { model.preset(id)?.prompt ?? "" },
                                 commit: { typed, _ in await model.setPresetPrompt(id, typed) })
                }
                RowDivider()
                OptionRow(label: l10n.string(.appPresetAgent)) {
                    ChoiceMenu(shown: agentName(row, presets), font: .body, accessibilityLabel: l10n.string(.appPresetAgent)) {
                        Picker(selection: Binding(get: { row.agent ?? "" }, set: { agent in Task { await model.setPresetAgent(id, agent.isEmpty ? nil : agent) } })) {
                            Text(l10n.string(.appPresetAgentFirst)).tag("")
                            ForEach(presets.agents) { agent in
                                Text(verbatim: agent.name).tag(agent.id)
                            }
                            // An agent the config names that cannot take a prompt, or is not known, is shown as the choice.
                            if let unknownAgent { Text(verbatim: unknownAgent).tag(unknownAgent) }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.inline)
                    }
                }
                RowDivider()
                OptionRow(label: l10n.string(.appPresetMaxFiles)) {
                    ChoiceMenu(shown: "\(row.maxFiles)", font: .body, accessibilityLabel: l10n.string(.appPresetMaxFiles)) {
                        Picker(selection: Binding(get: { row.maxFiles }, set: { count in Task { await model.setPresetMaxFiles(id, count) } })) {
                            ForEach(Array(Set(maxFilesChoices + [row.maxFiles])).sorted(), id: \.self) { count in
                                Text(verbatim: "\(count)").tag(count)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.inline)
                    }
                }
            }
            .panel()
            // The two notes on the rows above are one footnote, nearer to each other than to the rest of the page.
            VStack(alignment: .leading, spacing: 4) {
                caption(.appPresetPlaceholders)
                caption(.appPresetMaxFilesHelp)
            }
        }
        // A customized built-in preset goes back to the built-in one: that is no deletion, and is not red.
        RemoveButton(title: l10n.string(row.origin == .customized ? .appPresetReset : .appPresetRemove), tint: row.origin == .customized ? .accentColor : .red) {
            await model.removePreset(id)
        }
    }
}

/// A preset of one's own: a button that opens a form for its title and its prompt.
struct NewPresetForm: View {
    let model: SetupModel
    @State private var isOpen = false
    @State private var title = ""
    @State private var prompt = ""
    @Environment(\.localizer) private var l10n

    private var canAdd: Bool {
        guard let presets = model.presets else { return false }
        return PresetOptions.creating(title: title, prompt: prompt, in: presets) != nil
    }

    private func close() {
        isOpen = false
        title = ""
        prompt = ""
    }

    var body: some View {
        if isOpen {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 0) {
                    OptionRow(label: l10n.string(.appPresetTitle)) {
                        DraftField(label: l10n.string(.appPresetTitle), prompt: l10n.string(.appPresetTitle), text: $title)
                    }
                    RowDivider()
                    OptionRow(label: l10n.string(.appPresetPrompt), stacked: true) {
                        DraftField(label: l10n.string(.appPresetPrompt), prompt: l10n.string(.appPresetPrompt), text: $prompt, wraps: true)
                    }
                }
                .panel()
                Text(l10n.string(.appPresetNewCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(l10n.string(.appCancel)) { close() }
                        .keyboardShortcut(.cancelAction)
                    Button(l10n.string(.appPresetNewAdd)) { Task { if await model.createPreset(title: title, prompt: prompt) { close() } } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canAdd || model.isWorking)
                }
            }
        } else {
            Button(l10n.string(.appPresetNew)) { isOpen = true }
                .disabled(model.isWorking)
                .atTrailingEdge()
        }
    }
}
