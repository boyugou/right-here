import AppKit
import Foundation
import RightHereCore
import RightHereKit
import UniformTypeIdentifiers

// Changing the apps that the config adds (ADR 0026): a line on the Overview for each, and the page of one. An app is an entry of a file, so a change names the entry by its place under the check
// that it is still the one that was shown, and goes to the file that holds it (`AppOptions`, as `PresetOptions` does for the presets).

extension SetupModel {
    /// The apps the config adds as lines to edit; `nil` while the config cannot be edited.
    var apps: AppsState? { snapshot?.apps }

    func app(_ id: String) -> AppRowState? { snapshot?.apps?.row(id: id) }

    /// Writes what `build` makes of the app as it is now, to the file that holds it. Nothing to change is done; an app that is not there is not.
    @discardableResult
    private func changeApp(_ id: String, _ build: (AppRowState) -> FileChange?) async -> Bool {
        guard await settled(on: .overview, key: "app.\(id)"), let row = app(id) else { return false }
        guard let change = build(row) else { return true }
        return await edit(change.operations, deciding: "app.\(id)", target: change.target, saying: .appAgentEdited(row.name), on: .overview)
    }

    @discardableResult
    func setAppName(_ id: String, _ name: String) async -> Bool {
        await changeApp(id) { AppOptions.changing(name: name, of: $0) }
    }

    @discardableResult
    func setAppRole(_ id: String, _ role: AppDescriptor.Role) async -> Bool {
        await changeApp(id) { AppOptions.changing(role: role, of: $0) }
    }

    /// An app taken out; its page closes with it, and a built-in app that it replaced is the built-in one again. It is the entry that the page showed that is taken out: a second click, made while the
    /// first is written, finds another entry with the id (the shared file's) and takes none out.
    func removeApp(_ id: String) async {
        let shown = app(id)?.entry
        guard await settled(on: .overview, key: "app.\(id)"), let row = app(id), let change = AppOptions.removing(row) else { return }
        guard row.entry == shown else {
            say(.listChanged)
            return
        }
        await edit(change.operations, deciding: "app.\(id)", target: change.target, saying: .appMenuEditedRemoved(row.name), on: .overview)
    }

    /// Lets the person choose an application, and says what it says of itself; `nil` when none was chosen, or when the one chosen cannot be added (it is available already, or it has no bundle
    /// identifier), which is said.
    func chooseApp() -> AppBundleInfo? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = localizer.string(.appAppsChooseMessage)
        panel.prompt = localizer.string(.appChooseFolderPrompt)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return pickedApp(at: url)
    }

    /// Says under the apps, where the person pressed Add App…, why the application cannot be added.
    private func refuseApp(_ notice: SetupNotice) {
        refuse(notice, on: .overview, key: "app")
    }

    /// What the window does with the application that was chosen, apart from the panel that chose it.
    func pickedApp(at url: URL) -> AppBundleInfo? {
        guard let info = AppBundleInfo.read(at: url), AppOptions.isBundleID(info.bundleID) else {
            refuseApp(.appNotFound(url.deletingPathExtension().lastPathComponent))
            return nil
        }
        if let apps {
            // A built-in app that this Mac turns off is known: it is not added again under another id (as an editor, whatever it is).
            if let name = AppOptions.turnedOff(bundleID: info.bundleID, in: apps) {
                refuseApp(.appTurnedOff(name))
                return nil
            }
            if let name = AppOptions.alreadyAvailable(bundleID: info.bundleID, in: apps) {
                refuseApp(.appAlreadyAvailable(name))
                return nil
            }
        }
        clearRefusal(key: "app")
        return info
    }

    /// A new app with a name, a bundle identifier and what it opens, put at the end. The id of the one that was made; `nil` when it was not (nothing typed, a bundle identifier the config would
    /// refuse, an app that is available already). An app that says it is a shell (`runsShellScripts`) is a terminal whatever role is asked for: handed a file, it would run it.
    @discardableResult
    func createApp(name: String, bundleID: String, role asked: AppDescriptor.Role, runsShellScripts: Bool = false) async -> String? {
        let role = runsShellScripts ? AppDescriptor.Role.terminal : asked
        // What the files already hold is asked before the wait: a change that starts in a gap after it would find the window busy and drop this one without a word. The ids are those of the three kinds
        // that `disabled` names, and the apps are those the files offer now, which the window's own reading may not know yet (something else added the same app meanwhile).
        let used = await actions.disableableIDsInUse()
        let offered = await actions.appsAvailable()
        guard await settled(on: .overview, key: "app"), let apps else { return nil }
        if let name = AppOptions.turnedOff(bundleID: bundleID, in: apps) {
            refuseApp(.appTurnedOff(name))
            return nil
        }
        if let name = offered[bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] {
            refuseApp(.appAlreadyAvailable(name))
            return nil
        }
        guard let made = AppOptions.creating(name: name, bundleID: bundleID, role: role, in: apps, alsoTaken: used) else { return nil }
        await edit(made.change.operations, deciding: "app.\(made.id)", target: made.change.target, saying: .appMenuEditedAdded(name.trimmingCharacters(in: .whitespaces)), on: .overview)
        return app(made.id) != nil ? made.id : nil
    }
}
