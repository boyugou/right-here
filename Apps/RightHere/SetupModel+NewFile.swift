import Foundation
import RightHereCore
import RightHereKit

// Changing the new-file templates (ADR 0026): their lines on the Finder menu page and the page of one of them. A template is an entry of a file, so a change names the entry by its place
// under the check that it is still the one that was shown, and goes to the file that holds it (`NewFileOptions`, as `PresetOptions` does for the presets). The built-in templates are
// written out as the config's own by the first change, since a config that defines one replaces them.

extension SetupModel {
    /// The templates as lines to edit; `nil` while the config cannot be edited.
    var newFile: NewFileState? { snapshot?.newFile }

    func template(_ id: String) -> TemplateRowState? { snapshot?.newFile?.row(id: id) }

    /// Writes what `build` makes of the template as it is now, to the file that holds it. Nothing to change is done; a template that is not there is not.
    @discardableResult
    private func changeTemplate(_ id: String, announcing: Bool = true, _ build: (TemplateRowState) -> FileChange?) async -> Bool {
        guard await settled(on: .menu, key: "new_file.template.\(id)"), let row = template(id) else { return false }
        guard let change = build(row) else { return true }
        return await edit(change.operations, deciding: "new_file.template.\(id)", target: change.target, saying: .appAgentEdited(row.title), on: .menu, announcing: announcing)
    }

    @discardableResult
    func setTemplateTitle(_ id: String, _ title: String) async -> Bool {
        await changeTemplate(id) { NewFileOptions.changing(title: title, of: $0) }
    }

    @discardableResult
    func setTemplateBaseName(_ id: String, _ name: String) async -> Bool {
        await changeTemplate(id) { NewFileOptions.changing(baseName: name, of: $0) }
    }

    @discardableResult
    func setTemplateExtension(_ id: String, _ fileExtension: String) async -> Bool {
        await changeTemplate(id) { NewFileOptions.changing(fileExtension: fileExtension, of: $0) }
    }

    /// What the new file holds. A block that rests while it is typed in is written without VoiceOver being told (`announcing`); the change that ends the typing is told.
    @discardableResult
    func setTemplateContents(_ id: String, _ contents: String, announcing: Bool = true) async -> Bool {
        await changeTemplate(id, announcing: announcing) { NewFileOptions.changing(contents: contents, of: $0) }
    }

    /// The app that opens the new file; `nil` is the default editor.
    @discardableResult
    func setTemplateOpensWith(_ id: String, _ app: String?) async -> Bool {
        await changeTemplate(id) { NewFileOptions.changing(openWith: app, of: $0) }
    }

    /// What happens after a file is made.
    /// Whether the New File submenu offers a template (`new_file.hidden`).
    func setTemplateShown(_ row: TemplateRowState, shown: Bool) async {
        guard await settled(on: .menu, key: NewFileOptions.hiddenKey), let state = newFile, let current = state.row(id: row.id) else { return }
        await edit(NewFileOptions.operations(settingShown: shown, of: current, in: state), deciding: NewFileOptions.hiddenKey, saying: .appEditSaved, on: .menu)
    }

    func setNewFileThen(_ then: Config.AfterNewFile) async {
        guard await settled(on: .menu, key: "new_file.then"), let state = newFile else { return }
        await edit(NewFileOptions.operations(settingThen: then, in: state), deciding: "new_file.then", saying: .appEditSaved, on: .menu)
    }

    /// The built-in templates made the config's own, so that they can be changed.
    func customizeTemplates() async {
        guard await settled(on: .menu, key: "new_file.template"), let state = newFile, let change = NewFileOptions.customizing(state) else { return }
        await edit(change.operations, deciding: "new_file.template", target: change.target, saying: .appEditSaved, on: .menu)
    }

    /// A template taken out; its page closes with it.
    func removeTemplate(_ id: String) async {
        let shown = template(id)?.entry
        guard await settled(on: .menu, key: "new_file.template.\(id)"), let row = template(id), let change = NewFileOptions.removing(row) else { return }
        guard row.entry == shown else {
            say(.listChanged)
            return
        }
        await edit(change.operations, deciding: "new_file.template.\(id)", target: change.target, saying: .appMenuEditedRemoved(row.title), on: .menu)
    }

    /// A new template with a title and an extension. Whether it was made. It stands after the others of its file; when it goes to the shared file while this Mac's own file has templates, the merged list
    /// has it before this Mac's.
    @discardableResult
    func createTemplate(title: String, fileExtension: String) async -> Bool {
        // The ids of the three kinds that `disabled` names (an app, a template and an agent of one id are all turned off by that id).
        let used = await actions.disableableIDsInUse()
        guard await settled(on: .menu, key: "new_file.template"), let newFile else { return false }
        guard let made = NewFileOptions.creating(title: title, fileExtension: fileExtension, in: newFile, alsoTaken: used) else { return false }
        await edit(made.change.operations, deciding: "new_file.template.\(made.id)", target: made.change.target, saying: .appMenuEditedAdded(title.trimmingCharacters(in: .whitespaces)), on: .menu)
        return template(made.id) != nil
    }
}
