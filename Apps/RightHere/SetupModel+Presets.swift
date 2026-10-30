import Foundation
import RightHereCore
import RightHereKit

// Changing the prompt presets (ADR 0026): the lines of the Agents page and the page of one preset. A preset is an entry of a file, so a change names the entry by its place under the
// check that it is still the one that was shown (`PresetOptions`), and goes to the file that holds it. A field that holds one value is worked out from the preset as it is when the
// change is made, after the change that is running has ended (`settled`), as the options of an agent are.

extension SetupModel {
    /// The presets as lines to edit; `nil` while the config cannot be edited.
    var presets: PresetsState? { snapshot?.presets }

    func preset(_ id: String) -> PresetRowState? { snapshot?.presets?.row(id: id) }

    /// Writes what `build` makes of the preset as it is now, to the file that holds it. Nothing to change is done; a preset that is not there is not.
    @discardableResult
    private func changePreset(_ id: String, _ build: (PresetRowState) -> PresetOptions.Change?) async -> Bool {
        guard await settled(on: .agents, key: "preset.\(id)"), let row = preset(id) else { return false }
        guard let change = build(row) else { return true }
        return await edit(change.operations, deciding: "preset.\(id)", target: change.target, saying: .appAgentEdited(row.title), on: .agents)
    }

    @discardableResult
    func setPresetTitle(_ id: String, _ title: String) async -> Bool {
        await changePreset(id) { PresetOptions.changing(title: title, of: $0) }
    }

    @discardableResult
    func setPresetPrompt(_ id: String, _ prompt: String) async -> Bool {
        await changePreset(id) { PresetOptions.changing(prompt: prompt, of: $0) }
    }

    /// The agent that runs it; `nil` is the first agent of the menu.
    @discardableResult
    func setPresetAgent(_ id: String, _ agent: String?) async -> Bool {
        await changePreset(id) { PresetOptions.changing(agent: agent, of: $0) }
    }

    @discardableResult
    func setPresetMaxFiles(_ id: String, _ count: Int) async -> Bool {
        await changePreset(id) { PresetOptions.changing(maxFiles: count, of: $0) }
    }

    /// A built-in preset made the person's own, so that its words can be changed.
    func customizePreset(_ id: String) async {
        await changePreset(id) { PresetOptions.customizing($0) }
    }

    /// A preset of one's own taken out, or a customized built-in one put back as it was built in; its page closes with it when it is gone.
    func removePreset(_ id: String) async {
        // The row is read after the change that is running has ended: a second click on the button finds the preset gone and does nothing, instead of a note of success and a refusal. It is the entry
        // that the page showed that is taken out: with an entry of that id in the other file as well, the second click would find that one.
        let shown = preset(id)?.entry
        guard await settled(on: .agents, key: "preset.\(id)"), let row = preset(id), row.origin != .builtIn, let change = PresetOptions.removing(row) else { return }
        guard row.entry == shown else {
            say(.listChanged)
            return
        }
        await edit(change.operations, deciding: "preset.\(id)", target: change.target, saying: .appMenuEditedRemoved(row.title), on: .agents)
    }

    /// A new preset with its title and its prompt, put at the end. Whether it was made; its id is shown on the line it makes.
    @discardableResult
    func createPreset(title: String, prompt: String) async -> Bool {
        let used = await actions.presetIDsInUse()
        guard await settled(on: .agents, key: "preset"), let presets else { return false }
        guard let made = PresetOptions.creating(title: title, prompt: prompt, in: presets, alsoTaken: used) else { return false }
        await edit(made.change.operations, deciding: "preset.\(made.id)", target: made.change.target, saying: .appMenuEditedAdded(title.trimmingCharacters(in: .whitespaces)), on: .agents)
        return preset(made.id) != nil
    }
}
