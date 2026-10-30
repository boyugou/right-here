import Foundation
import RightHereCore
import RightHereKit

// Changing the two lists of choices on the Finder menu page (ADR 0026): the forms that Copy Path offers, and the Quick Actions. Each is a list of text in the config (`copy_path.styles`,
// `services.items`) that the person checks, takes out and drags; while the config writes none, the first change writes the default list, as the menu editor does. A change by place is
// worked out from what the page showed and is dropped while another change is being written.

/// One of the lists of choices.
enum ChoiceListOwner: Hashable, Sendable {
    case copyPath
    case quickActions

    /// The setting that holds the list, which is also what a change of it is said to be about.
    var key: String {
        switch self {
        case .copyPath: CopyPathOptions.stylesKey
        case .quickActions: QuickActionsOptions.key
        }
    }
}

extension SetupModel {
    var copyPath: CopyPathState? { snapshot?.copyPath }
    var quickActions: QuickActionsState? { snapshot?.quickActions }

    func choiceList(_ owner: ChoiceListOwner) -> ArgumentList? {
        switch owner {
        case .copyPath: copyPath?.list
        case .quickActions: quickActions?.list
        }
    }

    /// What a change of the list says it did to the item at `position`: the title of the row, or the id.
    private func title(of owner: ChoiceListOwner, at position: Int) -> String? {
        switch owner {
        case .copyPath: copyPath?.offered[safe: position - 1]?.title
        case .quickActions: quickActions?.rows[safe: position - 1]?.title
        }
    }

    /// An item put in the list, at the end. `id` is a path style (`absolute`) or an action id.
    @discardableResult
    func addChoice(_ owner: ChoiceListOwner, _ id: String) async -> Bool {
        guard await settled(on: .menu, key: owner.key) else { return false }
        let operations: [ConfigOperation], name: String
        switch owner {
        case .copyPath:
            guard let state = copyPath, let style = PathStyle(rawValue: id) else { return false }
            operations = CopyPathOptions.operations(adding: style, to: state)
            name = state.others.first { $0.style == style }?.title ?? id
        case .quickActions:
            guard let state = quickActions else { return false }
            operations = QuickActionsOptions.operations(adding: id, to: state)
            name = state.choices.first { $0.id == id }?.title ?? id
        }
        return await edit(operations, deciding: owner.key, target: choiceList(owner)?.firstChangeTarget, saying: .appMenuEditedAdded(name), on: .menu)
    }

    /// The item at `position` (from 1) taken out of the list.
    @discardableResult
    func removeChoice(_ owner: ChoiceListOwner, at position: Int) async -> Bool {
        guard !isWorking, let name = title(of: owner, at: position) else { return false }
        let operations: [ConfigOperation]
        switch owner {
        case .copyPath: operations = copyPath.map { CopyPathOptions.operations(removingAt: position, from: $0) } ?? []
        case .quickActions: operations = quickActions.map { QuickActionsOptions.operations(removingAt: position, from: $0) } ?? []
        }
        return await edit(operations, deciding: owner.key, target: choiceList(owner)?.firstChangeTarget, saying: .appMenuEditedRemoved(name), on: .menu)
    }

    /// The items, one place up or down; the same drag as the other lists.
    @discardableResult
    func moveChoices(_ owner: ChoiceListOwner, from source: IndexSet, to destination: Int) async -> Bool {
        guard !isWorking, let first = source.first, let name = title(of: owner, at: first + 1) else { return false }
        let operations: [ConfigOperation]
        switch owner {
        case .copyPath: operations = copyPath.map { CopyPathOptions.operations(moving: source, to: destination, in: $0) } ?? []
        case .quickActions: operations = quickActions.map { QuickActionsOptions.operations(moving: source, to: destination, in: $0) } ?? []
        }
        return await edit(operations, deciding: owner.key, target: choiceList(owner)?.firstChangeTarget, saying: .appMenuEditedMoved(name), on: .menu)
    }

    /// The item at `position` (from 1) one place up (`-1`) or down (`1`), for the context menu and for VoiceOver.
    @discardableResult
    func moveChoice(_ owner: ChoiceListOwner, _ position: Int, by offset: Int) async -> Bool {
        guard let count = choiceList(owner)?.items.count, (1...max(count, 1)).contains(position), (1...max(count, 1)).contains(position + offset) else { return false }
        return await moveChoices(owner, from: IndexSet(integer: position - 1), to: offset > 0 ? position + 1 : position - 2)
    }

    /// The title of the Copy Path entry; empty puts back "Copy Path" in the person's language.
    @discardableResult
    func setCopyPathTitle(_ title: String) async -> Bool {
        guard await settled(on: .menu, key: CopyPathOptions.titleKey), let state = copyPath else { return false }
        return await edit(CopyPathOptions.operations(settingTitle: title, in: state), deciding: CopyPathOptions.titleKey, saying: .appEditSaved, on: .menu)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
