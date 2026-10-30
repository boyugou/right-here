import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// The "New File" templates on the Finder menu page (ADR 0026): their lines under the menu, what happens after a file is made, the page of one template and the form for a new one. While the
// templates are the ones that come with the app they are read as they are and made the config's own with "Customize Templates" (a config that defines one replaces them); then a change of a
// template is written to the config file that holds it at once, in the smallest way, and can be undone from the note below.

/// The lines of the templates, what happens after a file is made, and the button for a new template, under the menu of the Finder menu page.
struct NewFilePanel: View {
    let model: SetupModel
    let state: NewFileState
    @Environment(\.localizer) private var l10n

    /// The settings of this panel, as the page says which editor a change was made in.
    static func concerns(_ key: String) -> Bool { key.hasPrefix("new_file.") }

    private func thenTitle(_ then: Config.AfterNewFile) -> String {
        switch then {
        case .reveal: l10n.string(.appNewFileThenReveal)
        case .open: l10n.string(.appNewFileThenOpen)
        case .nothing: l10n.string(.appNewFileThenNothing)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            Text(l10n.string(.groupNewFile))
                .font(.headline)
            Text(l10n.string(.appNewFileCaption))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LinedRows {
                ForEach(state.rows) { row in
                    TemplateRowLine(model: model, row: row, isBuiltIn: state.isBuiltIn)
                }
            }
            if state.isBuiltIn {
                Text(l10n.string(.appNewFileBuiltInNote2))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // What changes the list stands under it, together: Customize Templates (while they are the app's) beside New Template.
            NewTemplateForm(model: model) {
                if state.isBuiltIn {
                    Button(l10n.string(.appNewFileCustomize)) { Task { await model.customizeTemplates() } }
                        .disabled(model.isWorking)
                }
            }
            VStack(spacing: 0) {
                OptionRow(label: l10n.string(.appNewFileThen)) {
                    ChoiceMenu(shown: thenTitle(state.then), font: .body, accessibilityLabel: l10n.string(.appNewFileThen)) {
                        Picker(selection: Binding(get: { state.then }, set: { then in Task { await model.setNewFileThen(then) } })) {
                            ForEach(Config.AfterNewFile.allCases, id: \.self) { then in
                                Text(thenTitle(then)).tag(then)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.inline)
                    }
                }
            }
            .panel()
            // A setting of its own, apart from the buttons of the list above.
            .padding(.top, 8)
            ConfigEditBanner(model: model, tab: .menu, concerning: Self.concerns)
        }
    }
}

/// One template as a line: its title, its extension, and the chevron that opens it. A built-in one is read as it is.
private struct TemplateRowLine: View {
    let model: SetupModel
    let row: TemplateRowState
    let isBuiltIn: Bool
    @Environment(\.localizer) private var l10n

    private var content: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.badge.plus")
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(verbatim: row.title)
                .font(.body)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            // No "Built in" on each line: the templates are all built in or all the config's own, and the note under the list says which.
            Spacer(minLength: 8)
            Text(verbatim: ".\(row.fileExtension)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            if !isBuiltIn {
                Image(systemName: "chevron.forward")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 5)
        .frame(minHeight: 40)
        .contentShape(Rectangle())
    }

    var body: some View {
        // The check says whether the New File submenu offers it (`new_file.hidden`); it stands outside the line's button, which opens the template.
        HStack(spacing: 10) {
            RowCheck(isOn: row.shown, label: l10n.render(.appNewFileShowTemplate(row.title))) {
                Task { await model.setTemplateShown(row, shown: !row.shown) }
            }
            .disabled(model.isWorking)
            if isBuiltIn {
                content
                    .accessibilityElement(children: .combine)
            } else {
                PlainButton(action: { model.openTemplate(row.id) }) { content }
                    .accessibilityLabel(row.title)
                    .accessibilityValue(".\(row.fileExtension)")
            }
        }
        .padding(.horizontal, 14)
        .opacity(row.shown ? 1 : 0.6)
    }
}

/// A template as a page: its title, the name and the extension of its file, what it holds, and the app that opens it.
struct TemplatePage: View {
    let model: SetupModel
    let id: String
    @Environment(\.localizer) private var l10n

    var body: some View {
        // The way back and the template's title stand in the window's header (`SetupModel.detailHeader`).
        VStack(alignment: .leading, spacing: PageRhythm.section) {
            if let row = model.template(id), let state = model.newFile {
                if row.entry == nil {
                    // The config writes it in a form that has no place to change it by (an inline array): it is shown, and said so.
                    readOnly(row, state)
                    caption(.appEntryNotEditable)
                } else {
                    editor(row, state)
                }
                ConfigEditBanner(model: model, tab: .menu, concerning: NewFilePanel.concerns)
            }
        }
    }

    private func caption(_ key: LocalizationKey) -> some View {
        Text(l10n.string(key))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func appName(_ row: TemplateRowState, _ state: NewFileState) -> String {
        row.openWith.map { id in state.apps.first { $0.id == id }?.name ?? id } ?? l10n.string(.appTemplateOpensWithDefault)
    }

    @ViewBuilder private func readOnly(_ row: TemplateRowState, _ state: NewFileState) -> some View {
        VStack(spacing: 0) {
            OptionRow(label: l10n.string(.appPresetTitle)) { Text(verbatim: row.title) }
            RowDivider()
            OptionRow(label: l10n.string(.appTemplateName)) { Text(verbatim: row.baseName) }
            RowDivider()
            OptionRow(label: l10n.string(.appTemplateExtension)) { Text(verbatim: row.fileExtension).font(.system(.body, design: .monospaced)) }
            RowDivider()
            OptionRow(label: l10n.string(.appTemplateContents), stacked: true) {
                Text(verbatim: row.contents)
                    .font(.system(.body, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
            RowDivider()
            OptionRow(label: l10n.string(.appTemplateOpensWith)) { Text(verbatim: appName(row, state)) }
        }
        .panel()
    }

    @ViewBuilder private func editor(_ row: TemplateRowState, _ state: NewFileState) -> some View {
        let unlisted = row.openWith.flatMap { id in state.apps.contains { $0.id == id } ? nil : id }
        VStack(spacing: 0) {
            OptionRow(label: l10n.string(.appPresetTitle)) {
                EditableText(label: l10n.string(.appPresetTitle), prompt: l10n.string(.appPresetTitle), current: { model.template(id)?.title ?? "" },
                             commit: { typed, _ in await model.setTemplateTitle(id, typed) })
            }
            RowDivider()
            OptionRow(label: l10n.string(.appTemplateName), help: l10n.string(.appTemplateFileHelp)) {
                EditableText(label: l10n.string(.appTemplateName), prompt: "untitled", current: { model.template(id)?.baseName ?? "" },
                             commit: { typed, _ in await model.setTemplateBaseName(id, typed) })
            }
            RowDivider()
            OptionRow(label: l10n.string(.appTemplateExtension)) {
                EditableText(label: l10n.string(.appTemplateExtension), prompt: "txt", monospaced: true, current: { model.template(id)?.fileExtension ?? "" },
                             commit: { typed, _ in await model.setTemplateExtension(id, typed) })
            }
            RowDivider()
            OptionRow(label: l10n.string(.appTemplateContents), help: l10n.string(.appTemplateContentsHelp), stacked: true) {
                EditableText(label: l10n.string(.appTemplateContents), prompt: "", monospaced: true, block: true, current: { model.template(id)?.contents ?? "" },
                             commit: { typed, _ in await model.setTemplateContents(id, typed) },
                             restCommit: { typed, _ in await model.setTemplateContents(id, typed, announcing: false) })
            }
            RowDivider()
            OptionRow(label: l10n.string(.appTemplateOpensWith)) {
                ChoiceMenu(shown: appName(row, state), font: .body, accessibilityLabel: l10n.string(.appTemplateOpensWith)) {
                    Picker(selection: Binding(get: { row.openWith ?? "" }, set: { app in Task { await model.setTemplateOpensWith(id, app.isEmpty ? nil : app) } })) {
                        Text(l10n.string(.appTemplateOpensWithDefault)).tag("")
                        ForEach(state.apps) { app in
                            Text(verbatim: app.name).tag(app.id)
                        }
                        // An app the config names that is not installed is shown as the choice.
                        if let unlisted { Text(verbatim: unlisted).tag(unlisted) }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                }
            }
        }
        .panel()
        RemoveButton(title: l10n.string(.appTemplateRemove)) { await model.removeTemplate(id) }
    }
}

/// A template of one's own: a button that opens a form for its title and its extension, with the buttons that stand beside it while it is closed.
struct NewTemplateForm<Beside: View>: View {
    let model: SetupModel
    @ViewBuilder let beside: Beside
    @State private var isOpen = false
    @State private var title = ""
    @State private var fileExtension = ""
    @Environment(\.localizer) private var l10n

    private var canAdd: Bool {
        guard let state = model.newFile else { return false }
        return NewFileOptions.creating(title: title, fileExtension: fileExtension, in: state) != nil
    }

    private func close() {
        isOpen = false
        title = ""
        fileExtension = ""
    }

    var body: some View {
        if isOpen {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 0) {
                    OptionRow(label: l10n.string(.appPresetTitle)) {
                        DraftField(label: l10n.string(.appPresetTitle), prompt: l10n.string(.appPresetTitle), text: $title)
                    }
                    RowDivider()
                    OptionRow(label: l10n.string(.appTemplateExtension)) {
                        DraftField(label: l10n.string(.appTemplateExtension), prompt: "py", text: $fileExtension, monospaced: true)
                    }
                }
                .panel()
                Text(l10n.string(.appNewFileNewCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(l10n.string(.appCancel)) { close() }
                        .keyboardShortcut(.cancelAction)
                    Button(l10n.string(.appNewFileNewAdd)) { Task { if await model.createTemplate(title: title, fileExtension: fileExtension) { close() } } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canAdd || model.isWorking)
                }
            }
        } else {
            HStack(spacing: 8) {
                beside
                Button(l10n.string(.appNewFileNew)) { isOpen = true }
                    .disabled(model.isWorking)
            }
            .atTrailingEdge()
        }
    }
}
