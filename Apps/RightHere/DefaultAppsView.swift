import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// The settings of the Overview (ADR 0026): the default terminal, where its sessions open, the default editor and the language, as one group of
// rows. When the config can be edited the values are menus: choosing writes `general.terminal`, `general.editor` or `general.language` at once,
// and "Automatic" or "Same as macOS" takes the setting out again, so the first app that is installed, or the Mac's language, is used.

/// Which of the two apps a row is about.
enum DefaultAppRole {
    case terminal, editor
}

/// A row of the Overview's settings: the setting's tile and name at the leading edge, notes under the name, and its value at the trailing edge.
struct SettingRow<Value: View, Notes: View>: View {
    let symbol: String?
    var tint: Color = .gray
    let title: String
    @ViewBuilder let value: () -> Value
    @ViewBuilder let notes: () -> Notes

    /// The size of the sidebar's tiles: a setting's tile larger than its section's looked like the bigger thing.
    static var tileSize: CGFloat { 22 }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let symbol {
                SectionTile(symbol: symbol, tint: tint, size: Self.tileSize)
            } else {
                Color.clear
                    .frame(width: Self.tileSize, height: 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.body)
                notes()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            value()
                .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 46)
        .accessibilityElement(children: .contain)
    }
}

/// The language of what the person reads: the window, the Finder menu, the alerts and the names of the Quick Actions. Choosing writes `general.language`; "Same as macOS" takes it
/// out again.
struct LanguageRow: View {
    let model: SetupModel
    @Environment(\.localizer) private var l10n

    /// A language by its own name, as the person who reads it knows it: "Deutsch", "简体中文".
    static func name(_ code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code).map { $0.capitalized(with: locale) } ?? code
    }

    var body: some View {
        SettingRow(symbol: "globe", tint: .blue, title: l10n.string(.appLanguageTitle)) {
            ChoiceMenu(shown: shown, font: .body, accessibilityLabel: l10n.string(.appLanguageTitle)) {
                Picker(selection: Binding(get: { model.snapshot?.language ?? "" }, set: { code in Task { await model.setLanguage(code.isEmpty ? nil : code) } })) {
                    Text(l10n.render(.appLanguageSystem(Self.name(Localizer.system.resolvedLanguage)))).tag("")
                    ForEach(Localizer.supportedLanguages, id: \.self) { code in
                        Text(verbatim: Self.name(code)).tag(code)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            }
            .disabled(model.isWorking)
        } notes: {
            Text(l10n.string(.appLanguageCaption))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shown: String {
        model.snapshot?.language.map(Self.name) ?? l10n.render(.appLanguageSystem(Self.name(Localizer.system.resolvedLanguage)))
    }
}

/// The default terminal or editor.
struct DefaultAppRow: View {
    let model: SetupModel
    let role: DefaultAppRole
    @Environment(\.localizer) private var l10n

    private var title: LocalizationKey { role == .terminal ? .appCheckTerminal : .appCheckEditor }
    private var symbol: String { role == .terminal ? "terminal.fill" : "chevron.left.forwardslash.chevron.right" }

    var body: some View {
        SettingRow(symbol: symbol, tint: role == .terminal ? Color(white: 0.3) : .indigo, title: l10n.string(title)) {
            if let general = model.general {
                chooser(general)
            } else if model.checks.isEmpty {
                Spinner()
            } else {
                // What the doctor found, when the config cannot be edited (it has an error).
                Text((role == .terminal ? model.summary.terminal : model.summary.editor) ?? l10n.string(.appNoneFound))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } notes: {
            if role == .terminal, let general = model.general { terminalNotes(general) }
        }
    }

    // MARK: The app

    private func apps(_ general: GeneralSettingsState) -> [GeneralSettingsState.App] { role == .terminal ? general.terminals : general.editors }

    /// The app that is used now: the one chosen, or the best one that is installed.
    private func used(_ general: GeneralSettingsState) -> GeneralSettingsState.App? {
        let used = role == .terminal ? general.usedTerminal : general.usedEditor
        return apps(general).first { $0.id == used }
    }

    private func usedName(_ general: GeneralSettingsState) -> String? { used(general)?.name }

    private func choice(_ general: GeneralSettingsState) -> String { (role == .terminal ? general.terminal : general.editor) ?? "" }

    private func choose(_ id: String) {
        let chosen = id.isEmpty ? nil : id
        Task { if role == .terminal { await model.setTerminal(chosen) } else { await model.setEditor(chosen) } }
    }

    private func label(_ app: GeneralSettingsState.App) -> String {
        app.installed ? app.name : l10n.render(.appChooseNotInstalled(app.name))
    }

    private func chooser(_ general: GeneralSettingsState) -> some View {
        let automatic = role == .terminal ? general.automaticTerminalName : general.automaticEditorName
        return ChoiceMenu(shown: usedName(general) ?? l10n.string(.appNoneFound), icon: model.image(for: used(general)?.icon), font: .body,
                          accessibilityLabel: l10n.string(title)) {
            Picker(selection: Binding(get: { choice(general) }, set: choose)) {
                Text(automatic.map { l10n.render(.appTerminalAutomatic($0)) } ?? l10n.string(.appNoneFound)).tag("")
                ForEach(apps(general)) { app in
                    Group {
                        if let image = model.image(for: app.icon) {
                            Label { Text(label(app)) } icon: { Image(nsImage: image) }
                        } else {
                            Text(label(app))
                        }
                    }
                    .tag(app.id)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        }
        .disabled(model.isWorking)
    }

    // MARK: What the terminal cannot do

    @ViewBuilder private func terminalNotes(_ general: GeneralSettingsState) -> some View {
        let used = usedName(general) ?? ""
        if let fallback = general.placementFallback, !used.isEmpty {
            switch fallback {
            case .windowOnly: note(l10n.render(.appPlacementWindowOnly(used)))
            case .noSplits: note(l10n.render(.appPlacementNoSplits(used)))
            }
        }
        if !general.usedTerminalRunsCommands, !used.isEmpty {
            note(l10n.render(.appTerminalNoAgents(used)))
        }
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Where a session of the default terminal opens, when it can open in more than a new window: under the terminal's row.
struct PlacementRow: View {
    let model: SetupModel
    let general: GeneralSettingsState
    @Environment(\.localizer) private var l10n

    static func title(_ placement: TerminalPlacement, _ l10n: Localizer) -> String {
        switch placement {
        case .newWindow: l10n.string(.appPlacementWindow)
        case .newTab: l10n.string(.appPlacementTab)
        case .splitRight: l10n.string(.appPlacementSplitRight)
        case .splitDown: l10n.string(.appPlacementSplitDown)
        }
    }

    var body: some View {
        // A tile of its own like every row of the group: a row without one read as missing its icon.
        SettingRow(symbol: "macwindow.on.rectangle", tint: .teal, title: l10n.string(.appPlacementLabel)) {
            // The label says what a session does: a split the config asks of Warp, which has none, is a window, and the note under the
            // terminal says why. The selection stays what the config says, so that choosing New window then writes it.
            ChoiceMenu(shown: Self.title(general.effectivePlacement, l10n), font: .body, accessibilityLabel: l10n.string(.appPlacementLabel)) {
                Picker(selection: Binding(get: { general.placement }, set: { placement in Task { await model.setPlacement(placement) } })) {
                    ForEach(general.placements, id: \.self) { placement in
                        Text(Self.title(placement, l10n)).tag(placement)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            }
            .disabled(model.isWorking)
        } notes: {
            EmptyView()
        }
    }
}

/// What is chosen, with the chevrons of a menu after it; the choices open when it is clicked. SwiftUI draws all of it, so `script/preview_setup.sh` draws it as the window does.
struct ChoiceMenu<Choices: View>: View {
    let shown: String
    /// The icon of the app that is chosen, before its name, as the pop-up of a default app in System Settings has it.
    var icon: NSImage?
    let font: Font
    let accessibilityLabel: String
    @ViewBuilder let choices: () -> Choices
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    private var label: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(nsImage: icon)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 4) {
                Text(verbatim: shown)
                    .font(font)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    var body: some View {
        // Not `.borderlessButton`: that is an AppKit pop-up button, which keeps the label's text and its first image and draws the image first, so the
        // chevrons stood before what is chosen (measured in a window that was never put on screen, ADR 0029). A plain button draws the label as it is.
        Menu {
            choices()
        } label: {
            label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        // A light ground under the pointer, as a pop-up button of System Settings has: words and chevrons alone do not look like something to click.
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(hovering && isEnabled ? 0.07 : 0)).padding(-4))
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(shown)
    }
}
