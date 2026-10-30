import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// The two lists of choices on the Finder menu page (ADR 0026): the forms that Copy Path offers, and the Quick Actions. A line is a grip, a check that takes it out, and its name; a drag moves it,
// and a right click, VoiceOver's actions and Option with the arrow keys move it up and down. Each change is written to the config file at once, in the smallest way, and can be undone.

/// A line of a list of choices.
private struct ChoiceRow: Identifiable {
    var id: String
    var title: String
    var icon: Icon?
    var isAvailable = true
}

/// The lines of one list and, when there are some, the lines of what it does not offer.
private struct ChoiceListPanel: View {
    let model: SetupModel
    let owner: ChoiceListOwner
    let rows: [ChoiceRow]
    let others: [ChoiceRow]
    @State private var dropTarget: Int?
    @Environment(\.localizer) private var l10n

    var body: some View {
        let locked = model.isWorking || model.choiceList(owner)?.isExact == false
        VStack(alignment: .leading, spacing: 10) {
            if !rows.isEmpty {
                LinedRows {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        OfferedLine(model: model, owner: owner, row: row, index: index, count: rows.count, locked: locked, dropTarget: $dropTarget)
                    }
                }
            }
            if !others.isEmpty {
                // Nearer the list it heads than the list above it.
                Text(l10n.string(.appMenuHiddenHeading))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)
                LinedRows {
                    ForEach(others) { row in
                        OtherLine(model: model, owner: owner, row: row, locked: locked)
                    }
                }
            }
        }
    }
}

extension ChoiceListOwner {
    /// The Quick Actions are of apps and agents, which have icons; the forms of Copy Path have none, and leave no empty place for one, so that
    /// the titles of the lines in the menu and of the lines out of it stand in one column.
    fileprivate var showsIcons: Bool { self == .quickActions }
}

private struct OfferedLine: View {
    let model: SetupModel
    let owner: ChoiceListOwner
    let row: ChoiceRow
    let index: Int
    let count: Int
    let locked: Bool
    @Binding var dropTarget: Int?
    @Environment(\.localizer) private var l10n

    private var position: Int { index + 1 }
    /// What taking the line out is called: a form leaves the menu of Copy Path, an action leaves the Quick Actions.
    private var removeText: String {
        switch owner {
        case .copyPath: l10n.render(.appMenuRemoveItem(row.title))
        case .quickActions: l10n.render(.appQuickActionRemoveItem(row.title))
        }
    }

    /// An action that cannot run (its app is not installed) says so in words, which Install or Repair leaves out of the Quick Actions.
    private var shownTitle: String { row.isAvailable ? row.title : l10n.render(.appChooseNotInstalled(row.title)) }

    var body: some View {
        HStack(spacing: 10) {
            RowGrip()
            RowCheck(isOn: true, label: removeText) { Task { await model.removeChoice(owner, at: position) } }
            if owner.showsIcons {
                RowIcon(image: model.listImage(for: row.icon))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
            Text(verbatim: shownTitle)
                .font(.body)
                .foregroundStyle(row.isAvailable ? Color.primary : Color.secondary)
            Spacer(minLength: 8)
        }
        .disabled(locked)
        .padding(.horizontal, 14)
        .frame(height: editorLineHeight)
        .overlay(alignment: .top) { if dropTarget == index { DropLine() } }
        .overlay(alignment: .bottom) { if dropTarget == index + 1, index == count - 1 { DropLine() } }
        .contentShape(Rectangle())
        .reorderable(model: model, token: "choice:\(owner.key):\(position)", scope: "choice:\(owner.key)", row: position, index: index, height: editorLineHeight, dropTarget: $dropTarget, enabled: !locked,
                     move: { from, destination in await model.moveChoices(owner, from: IndexSet(integer: from - 1), to: destination) },
                     moveBy: { offset in await model.moveChoice(owner, position, by: offset) })
        .contextMenu {
            Button(l10n.string(.appMenuMoveUp)) { Task { await model.moveChoice(owner, position, by: -1) } }.disabled(index == 0 || locked)
            Button(l10n.string(.appMenuMoveDown)) { Task { await model.moveChoice(owner, position, by: 1) } }.disabled(index == count - 1 || locked)
            Divider()
            Button(removeText) { Task { await model.removeChoice(owner, at: position) } }.disabled(locked)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shownTitle)
        .accessibilityAction(named: Text(l10n.string(.appMenuMoveUp))) { if index > 0, !locked { Task { await model.moveChoice(owner, position, by: -1) } } }
        .accessibilityAction(named: Text(l10n.string(.appMenuMoveDown))) { if index < count - 1, !locked { Task { await model.moveChoice(owner, position, by: 1) } } }
        .accessibilityAction(named: Text(removeText)) { if !locked { Task { await model.removeChoice(owner, at: position) } } }
    }
}

private struct OtherLine: View {
    let model: SetupModel
    let owner: ChoiceListOwner
    let row: ChoiceRow
    let locked: Bool

    var body: some View {
        HStack(spacing: 10) {
            RowGripSpace()
            RowCheck(isOn: false, label: row.title) { Task { await model.addChoice(owner, row.id) } }
            if owner.showsIcons {
                RowIcon(image: model.listImage(for: row.icon))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
            // In the text's colour, as the agents not in the menu are: a grey name looked switched off, and a tick puts it in the menu.
            Text(verbatim: row.title)
                .font(.body)
            Spacer(minLength: 8)
        }
        .disabled(locked)
        .padding(.horizontal, 14)
        .frame(height: editorLineHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !locked { Task { await model.addChoice(owner, row.id) } } }
    }
}

/// The forms of Copy Path, and the title of its entry, under the New File templates of the Finder menu page.
struct CopyPathPanel: View {
    let model: SetupModel
    let state: CopyPathState
    @Environment(\.localizer) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            Text(l10n.string(.groupCopyPath))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(l10n.string(.appCopyPathCaption))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                OptionRow(label: l10n.string(.appPresetTitle)) {
                    EditableText(label: l10n.string(.appPresetTitle), prompt: l10n.string(.groupCopyPath), current: { model.copyPath?.title ?? "" },
                                 commit: { typed, _ in await model.setCopyPathTitle(typed) })
                }
            }
            .panel()
            if !state.list.isExact { Text(l10n.string(.appCopyPathInexactNote)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            ChoiceListPanel(model: model, owner: .copyPath, rows: state.offered.map { ChoiceRow(id: $0.id, title: $0.title, icon: nil) },
                            others: state.others.map { ChoiceRow(id: $0.id, title: $0.title, icon: nil) })
            ConfigEditBanner(model: model, tab: .menu, concerning: { $0.hasPrefix("copy_path.") })
        }
    }
}

/// The Quick Actions: the actions that Finder lists as Quick Actions, and a menu that adds one.
struct QuickActionsPanel: View {
    let model: SetupModel
    let state: QuickActionsState
    @Environment(\.localizer) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: PageRhythm.inSection) {
            Text(l10n.string(.appQuickActionsHeading))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(l10n.string(.appQuickActionsCaption))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !state.list.isExact { Text(l10n.string(.appQuickActionsInexactNote)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            ChoiceListPanel(model: model, owner: .quickActions, rows: state.rows.map { ChoiceRow(id: $0.id, title: $0.title, icon: $0.icon, isAvailable: $0.isAvailable) }, others: [])
            AddQuickActionButton(model: model, state: state)
                .disabled(!state.list.isExact)
                .atTrailingEdge()
            ConfigEditBanner(model: model, tab: .menu, concerning: { $0.hasPrefix("services.") })
        }
    }
}

private struct AddQuickActionButton: View {
    let model: SetupModel
    let state: QuickActionsState
    @Environment(\.localizer) private var l10n

    private enum Section: CaseIterable { case direct, openWith, agents, copyPath, newFile, presets }

    private func section(_ id: String) -> Section {
        if id == "open.terminal" || id == "open.editor" || id == "reveal" { return .direct }
        if id.hasPrefix("open.") { return .openWith }
        if id.hasPrefix("agent.") { return .agents }
        if id.hasPrefix("copy-path.") { return .copyPath }
        if id.hasPrefix("new-file.") { return .newFile }
        if id.hasPrefix("preset.") { return .presets }
        return .direct
    }

    private func title(_ section: Section) -> String {
        switch section {
        case .direct: ""
        case .openWith: l10n.string(.groupOpenWith)
        case .agents: l10n.string(.appTabAgents)
        case .copyPath: l10n.string(.groupCopyPath)
        case .newFile: l10n.string(.groupNewFile)
        case .presets: l10n.string(.groupPresets)
        }
    }

    private func choices(_ section: Section) -> [QuickActionsState.Choice] { state.choices.filter { self.section($0.id) == section } }

    var body: some View {
        Menu {
            ForEach(choices(.direct)) { choice in entry(choice) }
            ForEach(Section.allCases.filter { $0 != .direct }, id: \.self) { section in
                let items = choices(section)
                if !items.isEmpty {
                    Menu(title(section)) {
                        ForEach(items) { choice in entry(choice) }
                    }
                }
            }
        } label: {
            Label(l10n.string(.appQuickActionsAdd), systemImage: "plus")
        }
        .menuStyle(.button)
        .fixedSize()
        .disabled(model.isWorking || state.choices.isEmpty)
    }

    private func entry(_ choice: QuickActionsState.Choice) -> some View {
        Button {
            Task { await model.addChoice(.quickActions, choice.id) }
        } label: {
            if let image = model.listImage(for: choice.icon) {
                Label { Text(verbatim: choice.title) } icon: { Image(nsImage: image) }
            } else {
                Text(verbatim: choice.title)
            }
        }
    }
}
