import Foundation

/// `[new_file]` and its `[[new_file.template]]` entries.
extension ConfigBuilder {
    func readNewFile(_ root: ConfigReader, into config: inout Config) {
        guard let newFile = root.subtable("new_file") else { return }
        newFile.checkKnownKeys()
        if let then = newFile.checkAllowed(newFile.string("then"), key: "then", allowed: Config.AfterNewFile.allCases.map(\.rawValue)) {
            config.newFile.then = Config.AfterNewFile(rawValue: then) ?? .reveal
        }
        var seenTemplates = Set<String>()
        let templates = newFile.tableArray("template").compactMap { reader -> NewFileTemplate? in
            guard let template = template(reader) else { return nil }
            guard seenTemplates.insert(template.id).inserted else {
                sink.error(reader.path + ["id"], "duplicate template id \"\(template.id)\"; the first definition is used")
                return nil
            }
            return template
        }
        if !templates.isEmpty { config.newFile.templates = templates }
    }

    /// Runs after the apps are read: a template's `open_with` has to name an app that is not a terminal.
    func checkTemplateApps(_ config: inout Config) {
        for (index, template) in config.newFile.templates.enumerated() {
            guard let app = template.openWith else { continue }
            let path = ["new_file", "template", String(index + 1), "open_with"]
            guard let found = config.app(id: app) else {
                sink.error(path, "unknown app \"\(app)\"", suggestion: Suggestion.didYouMean(app, in: allAppIDs(config)))
                config.newFile.templates[index].openWith = nil
                continue
            }
            // A terminal handed a file runs it (a `.command` file, say), so it can never be what opens one.
            if found.role == .terminal {
                sink.error(path, "\"\(app)\" is a terminal, and a terminal handed a file runs it; name an editor or viewer")
                config.newFile.templates[index].openWith = nil
            }
        }
    }

    private func template(_ reader: ConfigReader) -> NewFileTemplate? {
        reader.checkKnownKeys()
        guard let id = reader.string("id"), let title = reader.string("title"), let ext = reader.string("extension") else {
            sink.error(reader.path, "a template needs id, title and extension")
            return nil
        }
        guard isValidID(id, at: reader.path + ["id"]) else { return nil }
        if ext.containsAnyScalar(of: [".", "/", "\0"]) || ext.isEmpty {
            sink.error(reader.path + ["extension"], "write the extension without a dot or slash, and not empty")
            return nil
        }
        let baseName = reader.string("base_name") ?? "untitled"
        if baseName.isEmpty || baseName == "." || baseName == ".." || baseName.containsAnyScalar(of: ["/", "\0"]) {
            sink.error(reader.path + ["base_name"], "a file name cannot be empty, \".\" or \"..\", or contain a slash")
            return nil
        }
        // APFS allows 255 bytes in a name; a number is added to avoid a clash (`name 2.md`), so leave room for it.
        if baseName.utf8.count + 1 + ext.utf8.count > 240 {
            sink.error(reader.path + ["base_name"], "base_name and extension together are too long for a file name (at most 240 bytes)")
            return nil
        }
        return NewFileTemplate(
            id: id, title: title, baseName: baseName,
            fileExtension: ext, contents: reader.string("contents") ?? "", openWith: reader.string("open_with")
        )
    }
}
