import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// The apps that the config adds, on the Overview (ADR 0026): their lines under the default terminal and editor, the page of one of them, and the form that adds the application the person chose. An
// app is an entry of a file: a change is written to the config file that holds it at once, in the smallest way, and can be undone from the note below.

/// What an app is used as, in the words of the menu.
private func roleTitle(_ role: AppDescriptor.Role, _ l10n: Localizer) -> String {
    switch role {
    case .editor: l10n.string(.appAppRoleEditor)
    case .terminal: l10n.string(.appAppRoleTerminal)
    case .general: l10n.string(.appAppRoleOther)
    }
}

/// The lines of the apps the config adds, and the button that adds another, under the default terminal and editor.
struct AppsPanel: View {
    let model: SetupModel
    let apps: AppsState
    @Environment(\.localizer) private var l10n

    /// The settings of this panel, as the page says which editor a change was made in.
    static func concerns(_ key: String) -> Bool { key == "app" || key.hasPrefix("app.") }

    var body: some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            Text(l10n.string(.appAppsHeading))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(l10n.string(.appAppsCaption))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !apps.rows.isEmpty {
                LinedRows {
                    ForEach(apps.rows) { row in
                        AppRowLine(model: model, row: row)
                    }
                }
            }
            NewAppForm(model: model)
            ConfigEditBanner(model: model, tab: .overview, concerning: Self.concerns)
        }
    }
}

/// One app as a line: its icon, its name with what it is used as, and the chevron that opens it.
private struct AppRowLine: View {
    let model: SetupModel
    let row: AppRowState
    @Environment(\.localizer) private var l10n

    private var detail: String {
        row.installed ? roleTitle(row.role, l10n) : l10n.render(.appChooseNotInstalled(roleTitle(row.role, l10n)))
    }

    var body: some View {
        PlainButton(action: { model.openApp(row.id) }) {
            HStack(spacing: 10) {
                RowIcon(image: model.image(for: row.icon))
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.name)
                        .font(.body)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: detail)
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
        .accessibilityLabel(row.name)
        .accessibilityValue(detail)
    }
}

/// An app as a page: its name, what it is used as, the identifier it is found by, and "Remove App".
struct AppPage: View {
    let model: SetupModel
    let id: String
    @Environment(\.localizer) private var l10n

    var body: some View {
        // The way back and the app's name stand in the window's header (`SetupModel.detailHeader`).
        VStack(alignment: .leading, spacing: PageRhythm.section) {
            if let row = model.app(id) {
                if row.entry == nil {
                    // The config writes it in a form that has no place to change it by (an inline array): it is shown, and said so.
                    readOnly(row)
                    caption(.appEntryNotEditable)
                    nextSteps(row)
                } else {
                    editor(row)
                }
                // Only what was done to this app: the refusal of Add App and the notes of the other apps are under the list of apps.
                ConfigEditBanner(model: model, tab: .overview, concerning: { $0 == "app.\(id)" })
            }
        }
    }

    /// What the Overview says an app of one's own can be: the default terminal or editor, and a line of the Finder menu. Each is a button here, while it is
    /// not so already.
    @ViewBuilder private func nextSteps(_ row: AppRowState) -> some View {
        let entry = row.role == .terminal ? "open.terminal@\(row.id)" : "open.app.\(row.id)"
        let canAdd = model.menuEditor?.choices.contains { $0.entry == entry } == true
        let current = row.role == .terminal ? model.general?.terminal : model.general?.editor
        let canBeDefault = row.installed && (row.role == .terminal || row.role == .editor) && current != row.id
        if canAdd || canBeDefault {
            HStack(spacing: 8) {
                if canBeDefault {
                    Button(l10n.string(.appAppMakeDefault)) {
                        Task { if row.role == .terminal { await model.setTerminal(row.id) } else { await model.setEditor(row.id) } }
                    }
                    .help(l10n.string(row.role == .terminal ? .appCheckTerminal : .appCheckEditor))
                }
                if canAdd {
                    Button(l10n.string(.appMenuAdd)) { Task { await model.addMenuItem(entry) } }
                        .help(l10n.string(.appMenuTitle))
                }
            }
            .controlSize(.small)
            .disabled(model.isWorking)
        }
    }

    private func caption(_ key: LocalizationKey) -> some View {
        Text(l10n.string(key))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func identifiers(_ row: AppRowState) -> some View {
        Text(verbatim: row.bundleIDs.joined(separator: ", "))
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func readOnly(_ row: AppRowState) -> some View {
        VStack(spacing: 0) {
            OptionRow(label: l10n.string(.appAgentName)) { Text(verbatim: row.name) }
            RowDivider()
            OptionRow(label: l10n.string(.appAppUseAs)) { Text(verbatim: roleTitle(row.role, l10n)) }
            RowDivider()
            OptionRow(label: l10n.string(.appAppBundleID)) { identifiers(row) }
        }
        .panel()
    }

    @ViewBuilder private func editor(_ row: AppRowState) -> some View {
        VStack(spacing: 0) {
            OptionRow(label: l10n.string(.appAgentName)) {
                EditableText(label: l10n.string(.appAgentName), prompt: l10n.string(.appAgentName), current: { model.app(id)?.name ?? "" },
                             commit: { typed, _ in await model.setAppName(id, typed) })
            }
            RowDivider()
            OptionRow(label: l10n.string(.appAppUseAs)) {
                ChoiceMenu(shown: roleTitle(row.role, l10n), font: .body, accessibilityLabel: l10n.string(.appAppUseAs)) {
                    Picker(selection: Binding(get: { row.role }, set: { role in Task { await model.setAppRole(id, role) } })) {
                        ForEach(AppOptions.roles, id: \.self) { role in
                            Text(roleTitle(role, l10n)).tag(role)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                }
                // A terminal that the config starts through templates, and one that comes with Right Here, stay terminals.
                .disabled(row.rolePinned)
            }
            RowDivider()
            OptionRow(label: l10n.string(.appAppBundleID)) { identifiers(row) }
        }
        .panel()
        if row.usesTemplates { caption(.appAppUsesTemplates) }
        if row.isKnownTerminal, !row.usesTemplates { caption(.appAppIsTerminal) }
        if row.origin == .replacesBuiltIn { caption(.appAppReplacesBuiltIn) }
        nextSteps(row)
        RemoveButton(title: l10n.string(.appAppRemove)) { await model.removeApp(id) }
    }
}

/// An app that is added: a button that opens the panel to choose it, and then a form for its name and what it is used as.
struct NewAppForm: View {
    let model: SetupModel
    @State private var picked: AppBundleInfo?
    @State private var name = ""
    @State private var role = AppDescriptor.Role.editor
    @Environment(\.localizer) private var l10n

    /// An app that says it is a shell is a terminal, and a terminal handed a file runs it (CLAUDE.md rule 3): it is not offered as anything else.
    private var pinnedToTerminal: Bool { picked?.runsShellScripts == true }

    private var canAdd: Bool {
        guard let picked, let apps = model.apps else { return false }
        return AppOptions.creating(name: name, bundleID: picked.bundleID, role: pinnedToTerminal ? .terminal : role, in: apps) != nil
    }

    private func close() {
        picked = nil
        name = ""
        role = .editor
    }

    var body: some View {
        if let picked {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 0) {
                    OptionRow(label: l10n.string(.appAgentName)) {
                        DraftField(label: l10n.string(.appAgentName), prompt: l10n.string(.appAgentName), text: $name)
                    }
                    RowDivider()
                    OptionRow(label: l10n.string(.appAppUseAs)) {
                        ChoiceMenu(shown: roleTitle(pinnedToTerminal ? .terminal : role, l10n), font: .body, accessibilityLabel: l10n.string(.appAppUseAs)) {
                            Picker(selection: $role) {
                                ForEach(AppOptions.roles, id: \.self) { role in
                                    Text(roleTitle(role, l10n)).tag(role)
                                }
                            } label: {
                                EmptyView()
                            }
                            .pickerStyle(.inline)
                        }
                        .disabled(pinnedToTerminal)
                    }
                    if pinnedToTerminal {
                        Text(l10n.string(.appAppIsTerminal))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                    }
                    RowDivider()
                    OptionRow(label: l10n.string(.appAppBundleID)) {
                        Text(verbatim: picked.bundleID)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .panel()
                HStack {
                    Spacer()
                    Button(l10n.string(.appCancel)) { close() }
                        .keyboardShortcut(.cancelAction)
                    Button(l10n.string(.appAppAddConfirm)) { Task { if await model.createApp(name: name, bundleID: picked.bundleID, role: role, runsShellScripts: picked.runsShellScripts) != nil { close() } } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canAdd || model.isWorking)
                }
            }
        } else {
            Button(l10n.string(.appAppsAdd)) {
                if let info = model.chooseApp() {
                    name = info.name
                    // An app that says it is a shell is a terminal, and a terminal handed a file runs it: the form starts there.
                    role = info.runsShellScripts ? .terminal : .editor
                    picked = info
                }
            }
            .disabled(model.isWorking)
            .atTrailingEdge()
        }
    }
}
