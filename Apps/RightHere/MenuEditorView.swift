import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// The Finder menu page while it is edited (ADR 0026): the lines of the menu as they are, which can be dragged to another place, taken out with the minus button and added to
// with a menu of what the menu lacks. Each change is written to the config file at once, in the smallest way, and can be undone.

struct MenuEditorView: View {
    let model: SetupModel
    let editor: MenuEditorState
    /// The place (from 0, in the list as it is) a dragged row would go to, while one is over the list.
    @State private var dropTarget: Int?
    @Environment(\.localizer) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editor.usesDefaults { note(.appMenuDefaultNote) }
            if model.menuIsMachineOwn { note(.appMenuMachineNote) }
            if !editor.isExact { note(.appMenuInexactNote) }
            VStack(spacing: 0) {
                ForEach(Array(editor.rows.enumerated()), id: \.element.id) { index, row in
                    MenuEditorRowView(model: model, row: row, index: index, count: editor.rows.count, dropTarget: $dropTarget)
                }
            }
            .panel()
            .disabled(model.isWorking || !editor.isExact)
            let hidden = editor.choices.filter { $0.section == .group || $0.section == .reveal }
            if !hidden.isEmpty {
                // What the menu could have and does not: a check puts it in, as a check on a line above takes it out.
                Text(l10n.string(.appMenuHiddenHeading))
                    .font(.headline)
                VStack(spacing: 0) {
                    ForEach(hidden) { choice in
                        HiddenChoiceRow(model: model, choice: choice)
                    }
                }
                .panel()
                .disabled(model.isWorking || !editor.isExact)
            }
            AddToMenuButton(model: model, editor: editor)
                .disabled(!editor.isExact)
                .atTrailingEdge()
            ConfigEditBanner(model: model, tab: .menu, concerning: { $0 == MenuEditorState.key })
        }
    }

    private func note(_ key: LocalizationKey) -> some View {
        Text(l10n.string(key))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One line of the editor: a grip, what the item makes in the menu, and the minus button. Dragging it moves the item; a right click, and VoiceOver's actions, move it up and down.
private struct MenuEditorRowView: View {
    let model: SetupModel
    let row: MenuEditorRow
    let index: Int
    let count: Int
    @Binding var dropTarget: Int?
    @Environment(\.localizer) private var l10n

    private var shown: [MenuNode] { row.nodes.filter { $0.kind != .separator } }
    private var height: CGFloat { editorLineHeight * CGFloat(max(1, shown.count)) }
    private var name: String { shown.map(\.title).joined(separator: ", ") }
    private var label: String { row.isSeparator ? l10n.string(.appMenuSeparator) : (shown.isEmpty ? row.fallbackTitle : name) }

    var body: some View {
        // An item that makes several lines (the agents) has its grip, its check and its link on its first line, where a person looks for them; centred,
        // they stood on its middle line and the lines above and below it looked like items that could not be checked.
        HStack(alignment: .top, spacing: 10) {
            RowGrip()
                .frame(height: editorLineHeight)
            if !row.isSeparator {
                RowCheck(isOn: true, label: removeText) { Task { await model.removeMenuRow(row.position) } }
                    .frame(height: editorLineHeight)
            }
            content
            Spacer(minLength: 8)
            // One row is every agent of the menu: which agents, and in what order, is the Agents page's, a click away.
            if row.entry == "agents" {
                PlainButton(action: { model.select(.agents) }) {
                    Label(l10n.string(.appTabAgents), systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .help(l10n.string(.appAgentsCaption))
                .frame(height: editorLineHeight)
            }
            if row.isSeparator {
                Button {
                    Task { await model.removeMenuRow(row.position) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(removeText)
                .accessibilityLabel(removeText)
                .frame(height: editorLineHeight)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        .overlay(alignment: .top) { if dropTarget == index { DropLine() } }
        .overlay(alignment: .bottom) { if dropTarget == index + 1, index == count - 1 { DropLine() } }
        .contentShape(Rectangle())
        .reorderable(model: model, token: row.id, scope: "menu", row: row.position, index: index, height: height, dropTarget: $dropTarget,
                     move: { from, destination in await model.moveMenuRows(from: IndexSet(integer: from - 1), to: destination) },
                     moveBy: { offset in await model.moveMenuRow(row.position, by: offset) })
        .contextMenu {
            Button(l10n.string(.appMenuMoveUp)) { Task { await model.moveMenuRow(row.position, by: -1) } }.disabled(index == 0)
            Button(l10n.string(.appMenuMoveDown)) { Task { await model.moveMenuRow(row.position, by: 1) } }.disabled(index == count - 1)
            Divider()
            Button(removeText) { Task { await model.removeMenuRow(row.position) } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAction(named: Text(l10n.string(.appMenuMoveUp))) { Task { await model.moveMenuRow(row.position, by: -1) } }
        .accessibilityAction(named: Text(l10n.string(.appMenuMoveDown))) { Task { await model.moveMenuRow(row.position, by: 1) } }
        .accessibilityAction(named: Text(removeText)) { Task { await model.removeMenuRow(row.position) } }
        .modifier(AgentsPageAction(model: model, shown: row.entry == "agents"))
    }

    private var removeText: String { l10n.render(.appMenuRemoveItem(label)) }

    @ViewBuilder private var content: some View {
        if row.isSeparator {
            // Not `Divider`: in a row of a stack it is drawn upright.
            Rectangle()
                .fill(Color.primary.opacity(0.18))
                .frame(height: 1)
                .accessibilityHidden(true)
        } else if shown.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.fallbackTitle)
                    .font(.system(.body, design: .monospaced))
                Text(l10n.string(.appMenuNothingHere))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, node in
                    HStack(spacing: 10) {
                        RowIcon(image: model.image(for: node.icon))
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                        Text(node.title)
                            .font(.body)
                        Spacer(minLength: 8)
                        if node.kind == .submenu {
                            Image(systemName: "chevron.forward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(height: editorLineHeight, alignment: .leading)
                }
            }
            // The lines of one item on one ground, so that they read as the one item the check and the grip move.
            .padding(.horizontal, shown.count > 1 ? 8 : 0)
            .background {
                if shown.count > 1 { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.045)) }
            }
            .padding(.leading, shown.count > 1 ? -8 : 0)
        }
    }
}

/// A group the menu does not have, as a line with an empty check: checking it puts it at the end of the menu.
private struct HiddenChoiceRow: View {
    let model: SetupModel
    let choice: MenuEditorChoice
    @Environment(\.localizer) private var l10n

    var body: some View {
        HStack(spacing: 10) {
            // The grip's place, so that the checks and the icons of these lines stand under those of the lines above.
            RowGripSpace()
            RowCheck(isOn: false, label: choice.title) { Task { await model.addMenuItem(choice.entry) } }
            RowIcon(image: model.listImage(for: choice.icon))
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(choice.title)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .frame(height: editorLineHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { Task { await model.addMenuItem(choice.entry) } }
    }
}

/// The menu of what can be added: the groups of the menu itself, then a submenu for each kind of action, then a separator.
private struct AddToMenuButton: View {
    let model: SetupModel
    let editor: MenuEditorState
    @Environment(\.localizer) private var l10n

    private func choices(_ section: MenuEditorChoice.Section) -> [MenuEditorChoice] { editor.choices.filter { $0.section == section } }

    private func title(of section: MenuEditorChoice.Section) -> String {
        switch section {
        case .copyPath: l10n.string(.groupCopyPath)
        case .presets: l10n.string(.groupPresets)
        case .newFile: l10n.string(.groupNewFile)
        case .openApp: l10n.string(.groupOpenWith)
        case .agents: l10n.string(.groupMoreAgents)
        case .group, .reveal: ""
        }
    }

    var body: some View {
        Menu {
            ForEach(choices(.group) + choices(.reveal)) { choice in entry(choice) }
            Divider()
            Button(l10n.string(.appMenuSeparator)) { Task { await model.addMenuItem("-") } }
            ForEach([MenuEditorChoice.Section.copyPath, .newFile, .presets, .agents, .openApp], id: \.self) { section in
                let items = choices(section)
                if !items.isEmpty {
                    Menu(title(of: section)) {
                        ForEach(items) { choice in entry(choice) }
                    }
                }
            }
        } label: {
            Label(l10n.string(.appMenuAdd), systemImage: "plus")
        }
        .menuStyle(.button)
        .fixedSize()
        .disabled(model.isWorking)
    }

    private func entry(_ choice: MenuEditorChoice) -> some View {
        Button {
            Task { await model.addMenuItem(choice.entry) }
        } label: {
            if let image = model.listImage(for: choice.icon).map(Self.small) {
                Label { Text(choice.title) } icon: { Image(nsImage: image) }
            } else {
                Text(choice.title)
            }
        }
    }

    /// A menu draws an image at its own size, and an app's icon is large.
    private static func small(_ image: NSImage) -> NSImage {
        let drawn = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
        drawn.isTemplate = image.isTemplate
        return drawn
    }
}

/// The agents' row of the menu editor opens the Agents page; VoiceOver reads the row as one element, so it is an action of it.
private struct AgentsPageAction: ViewModifier {
    let model: SetupModel
    let shown: Bool
    @Environment(\.localizer) private var l10n

    func body(content: Content) -> some View {
        if shown { content.accessibilityAction(named: Text(l10n.string(.appTabAgents))) { model.select(.agents) } } else { content }
    }
}
