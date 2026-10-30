import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// A list of arguments as rows (ADR 0026): an agent's own, or the arguments of one of its start options. Every row is a grip that picks it up, the argument as a field that is changed in place, and a
// minus button; the empty line at the end adds one. A change is written to the config file at once, in the smallest way.

/// The rows of a list of arguments, as a panel. The list is the one `owner` names; it is changed through the model, which holds each change to the list the page showed.
struct ArgumentListPanel: View {
    let model: SetupModel
    let owner: ArgumentListOwner
    let list: ArgumentList
    /// The place (from 0) a dragged argument would go to, while one is over the list.
    @State private var dropTarget: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, argument in
                ArgumentRow(model: model, owner: owner, index: index, count: list.items.count, argument: argument, dropTarget: $dropTarget)
            }
            AddArgumentRow(model: model, owner: owner)
        }
        .panel()
        .disabled(!list.isExact)
    }
}

/// One argument of the list: a grip that picks it up, the argument as a field that is changed in place, and a button that takes it out.
private struct ArgumentRow: View {
    let model: SetupModel
    let owner: ArgumentListOwner
    let index: Int
    let count: Int
    let argument: String
    @Binding var dropTarget: Int?
    @Environment(\.localizer) private var l10n

    private var position: Int { index + 1 }
    private var removeText: String { l10n.render(.appAgentRemoveArgument(argument)) }

    var body: some View {
        HStack(spacing: 10) {
            RowGrip()
                .pickedUp(model: model, token: "argument:\(owner.scope):\(position)", row: position, scope: "argument:\(owner.scope)")
            EditableText(label: l10n.string(.appAgentArguments), prompt: l10n.string(.appAgentAddArgument), monospaced: true,
                         current: { model.argumentList(of: owner)?.items[safe: index] ?? "" }, commit: { typed, shown in await model.setArgument(owner, at: position, from: shown, to: typed) })
            PlainButton(action: { Task { await model.removeArgument(owner, at: position) } }) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .help(removeText)
            .accessibilityLabel(removeText)
        }
        .padding(.horizontal, 14)
        .frame(height: editorLineHeight)
        .overlay(alignment: .top) { if dropTarget == index { DropLine() } }
        .overlay(alignment: .bottom) { if dropTarget == index + 1, index == count - 1 { DropLine() } }
        .reorderable(model: model, token: "argument:\(owner.scope):\(position)", scope: "argument:\(owner.scope)", row: position, index: index, height: editorLineHeight, dropTarget: $dropTarget, wholeRow: false,
                     move: { from, destination in await model.moveArguments(owner, from: IndexSet(integer: from - 1), to: destination) },
                     moveBy: { offset in await model.moveArgument(owner, position, by: offset) })
        .contextMenu {
            Button(l10n.string(.appMenuMoveUp)) { Task { await model.moveArgument(owner, position, by: -1) } }.disabled(index == 0)
            Button(l10n.string(.appMenuMoveDown)) { Task { await model.moveArgument(owner, position, by: 1) } }.disabled(index == count - 1)
            Divider()
            Button(removeText) { Task { await model.removeArgument(owner, at: position) } }
        }
        .accessibilityAction(named: Text(l10n.string(.appMenuMoveUp))) { if index > 0 { Task { await model.moveArgument(owner, position, by: -1) } } }
        .accessibilityAction(named: Text(l10n.string(.appMenuMoveDown))) { if index < count - 1 { Task { await model.moveArgument(owner, position, by: 1) } } }
    }
}

/// The empty line at the end of the list: an argument typed there is added when Return is pressed or the field is left.
private struct AddArgumentRow: View {
    let model: SetupModel
    let owner: ArgumentListOwner
    @Environment(\.localizer) private var l10n

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .foregroundStyle(.tertiary)
                .frame(width: 18)
                .accessibilityHidden(true)
            EditableText(label: l10n.string(.appAgentAddArgument), prompt: l10n.string(.appAgentAddArgument), monospaced: true, current: { "" },
                         commit: { typed, _ in await model.addArgument(owner, typed) })
        }
        .padding(.horizontal, 14)
        .frame(height: editorLineHeight)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
