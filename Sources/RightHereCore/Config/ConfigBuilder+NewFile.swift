import Foundation

/// `[new_file]` and its `[[new_file.template]]` entries.
extension ConfigBuilder {
    func readNewFile(_ root: ConfigReader, into config: inout Config) {
        guard let newFile = root.subtable("new_file") else { return }
        newFile.checkKnownKeys()
        if let then = newFile.checkAllowed(newFile.string("then"), key: "then", allowed: Config.AfterNewFile.allCases.map(\.rawValue)) {
            config.newFile.then = Config.AfterNewFile(rawValue: then) ?? .reveal
        }
        let templates = readUnique(newFile.tableArray("template"), kind: "template", id: \.id, read: template)
        if !templates.isEmpty {
            config.newFile.templates = templates
            config.newFile.definesTemplates = true
        }
        if let hidden = newFile.stringArray("hidden") {
            for (index, id) in hidden.enumerated() where !config.newFile.templates.contains(where: { $0.id == id }) {
                sink.warning(["new_file", "hidden", String(index + 1)], "no template \"\(id)\"", suggestion: Suggestion.didYouMean(id, in: config.newFile.templates.map { ($0.id, $0.title) }))
            }
            config.newFile.hidden = hidden
            config.newFile.writesHidden = true
        }
    }

    /// Runs after the apps are read: a template's `open_with` has to name an app that is not a terminal.
    func checkTemplateApps(_ config: inout Config) {
        for (index, template) in config.newFile.templates.enumerated() {
            guard let app = template.openWith else { continue }
            let path = ["new_file", "template", String(index + 1), "open_with"]
            guard let found = config.app(id: app) else {
                sink.error(path, "unknown app \"\(app)\"", suggestion: Suggestion.didYouMean(app, in: config.allApps.filter { $0.role != .terminal }.map { ($0.id, $0.name) }))
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

    /// The most bytes a template's contents have.
    static let largestContents = 64 * 1024

    private func template(_ reader: ConfigReader) -> NewFileTemplate? {
        reader.checkKnownKeys()
        guard let id = reader.string("id"), let title = reader.string("title"), let ext = reader.string("extension") else {
            reportMissing("a template", needs: ["id", "title", "extension"], in: reader)
            return nil
        }
        guard isValidID(id, at: reader.path + ["id"]) else { return nil }
        guard isPlainName(title, at: reader.path + ["title"], noun: "title") else { return nil }
        if ext.containsAnyScalar(of: [".", "/", "\0"]) || ext.isEmpty {
            sink.error(reader.path + ["extension"], "write the extension without a dot or slash, and not empty")
            return nil
        }
        // The name and the extension become the name of a file that Finder shows and that an agent may be handed, so they are held to what every other name is.
        guard isPlainName(ext, at: reader.path + ["extension"], noun: "extension", limit: 240) else { return nil }
        let baseName = reader.string("base_name") ?? "untitled"
        if baseName.isEmpty || baseName == "." || baseName == ".." || baseName.containsAnyScalar(of: ["/", "\0"]) {
            sink.error(reader.path + ["base_name"], "a file name cannot be empty, \".\" or \"..\", or contain a slash")
            return nil
        }
        guard isPlainName(baseName, at: reader.path + ["base_name"], noun: "file name", limit: 240) else { return nil }
        // APFS allows 255 bytes in a name; a number is added to avoid a clash (`name 2.md`), so leave room for it.
        if baseName.utf8.count + 1 + ext.utf8.count > 240 {
            sink.error(reader.path + ["base_name"], "base_name and extension together are too long for a file name (at most 240 bytes)")
            return nil
        }
        // A new file starts small: what a template holds is written in one change, which the window waits for, and a text of hundreds of kilobytes keeps it busy for seconds.
        let contents = reader.string("contents") ?? ""
        if contents.utf8.count > Self.largestContents {
            sink.error(reader.path + ["contents"], "the contents are longer than \(Self.largestContents / 1024) KB; a new file starts small")
            return nil
        }
        var format: OfficeFormat?
        if let name = reader.checkAllowed(reader.string("format"), key: "format", allowed: OfficeFormat.allCases.map(\.rawValue)) {
            format = OfficeFormat(rawValue: name)
            // The file is a package of that format: under another extension nothing opens it as one, and the text would not be in it.
            if name != ext {
                sink.error(reader.path + ["format"], "a \(name) document has the extension \"\(name)\", not \"\(ext)\"")
                return nil
            }
            if !contents.isEmpty {
                sink.error(reader.path + ["contents"], "a template with a format makes a blank \(name) document; it has no contents")
                return nil
            }
        }
        return NewFileTemplate(
            id: id, title: title, baseName: baseName,
            fileExtension: ext, contents: contents, format: format, openWith: reader.string("open_with")
        )
    }
}
