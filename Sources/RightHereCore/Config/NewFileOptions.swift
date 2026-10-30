import Foundation

/// One new-file template as a line to edit in the window (ADR 0026).
public struct TemplateRowState: Sendable, Equatable, Identifiable {
    public var id: String
    /// As it is shown: the built-in titles are in the person's language.
    public var title: String
    public var baseName: String
    public var fileExtension: String
    public var contents: String
    /// The app that opens the new file; `nil` is the default editor.
    public var openWith: String?
    /// Where the config writes it; `nil` for a built-in template (the config defines none).
    public var entry: EntryLocation?
    /// A blank Office document instead of a text.
    public var format: OfficeFormat?
    /// The New File submenu offers it (`new_file.hidden` does not name it).
    public var shown: Bool

    public init(id: String, title: String, baseName: String, fileExtension: String, contents: String, openWith: String?, entry: EntryLocation?, format: OfficeFormat? = nil, shown: Bool = true) {
        self.id = id
        self.title = title
        self.baseName = baseName
        self.fileExtension = fileExtension
        self.contents = contents
        self.openWith = openWith
        self.entry = entry
        self.format = format
        self.shown = shown
    }
}

/// The "New File" templates of the config as lines to edit, and what happens after a file is made.
///
/// A config that defines any template replaces the two built-in ones (text and Markdown), so the built-in rows are read as they are and the first change writes them out as the config's own;
/// from then on every row is an entry that can be changed, and taking the last one out gives the built-in ones back.
public struct NewFileState: Sendable, Equatable {
    /// An app that can open a new file: not a terminal, which would run it.
    public struct App: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public var rows: [TemplateRowState]
    /// The config defines no template: the rows are the built-in ones (less any that this Mac turns off).
    public var isBuiltIn: Bool
    public var then: Config.AfterNewFile
    public var apps: [App]
    /// The built-in templates in full, which the first change writes out as the config's own: this Mac may turn one of them off, and the shared file is read by Macs that do not.
    public var seed: [TemplateRowState]
    /// The shared file, which every Mac reads, defines templates. While it does not, a template written to it replaces the built-in ones on every Mac, so they are written out with it; and what only
    /// this Mac's own file defines stays there. (A Mac that turns off all the templates of the shared file shows the built-in ones although the shared file defines some.)
    public var sharedDefinesTemplates: Bool
    /// The ids `new_file.hidden` names, and whether the config writes that list at all.
    public var hidden: [String]
    public var writesHidden: Bool

    public init(rows: [TemplateRowState], isBuiltIn: Bool, then: Config.AfterNewFile, apps: [App], seed: [TemplateRowState]? = nil, sharedDefinesTemplates: Bool? = nil,
                hidden: [String] = [], writesHidden: Bool = false) {
        self.hidden = hidden
        self.writesHidden = writesHidden
        self.rows = rows
        self.isBuiltIn = isBuiltIn
        self.then = then
        self.apps = apps
        self.seed = seed ?? rows
        self.sharedDefinesTemplates = sharedDefinesTemplates ?? !isBuiltIn
    }

    public func row(id: String) -> TemplateRowState? { rows.first { $0.id == id } }
}

public enum NewFileOptions {
    private static let table = "new_file.template"

    /// - Parameter entries: Where each template the config writes is (`ConfigService.entryLocations(of: "new_file.template")`).
    /// - Parameter sharedDefinesTemplates: The shared file alone defines templates (`ConfigStore.sharedConfig`); by default whatever the config defines.
    public static func state(config: Config, entries: [String: EntryLocation], facts: any SystemFacts, localizer: Localizer, sharedDefinesTemplates: Bool? = nil) -> NewFileState {
        let isBuiltIn = !config.newFile.definesTemplates
        func row(_ template: NewFileTemplate, entry: EntryLocation?) -> TemplateRowState {
            TemplateRowState(id: template.id, title: template.localizedTitle(localizer), baseName: template.localizedBaseName(localizer), fileExtension: template.fileExtension,
                             contents: template.contents, openWith: template.openWith, entry: entry, format: template.format, shown: !config.newFile.hidden.contains(template.id))
        }
        let rows = config.newFile.templates.map { row($0, entry: isBuiltIn ? nil : entries[$0.id]) }
        // Every installed app that can open a file, which is what the config accepts for `open_with` (a terminal would run the file): the editors, and the apps of the config's own of any other role.
        let apps = config.allApps.filter { $0.role != .terminal && $0.installedBundleID(facts: facts) != nil }.map { NewFileState.App(id: $0.id, name: $0.name) }
        return NewFileState(rows: rows, isBuiltIn: isBuiltIn, then: config.newFile.then, apps: apps, seed: NewFileTemplate.builtIn.map { row($0, entry: nil) },
                            sharedDefinesTemplates: sharedDefinesTemplates, hidden: config.newFile.hidden, writesHidden: config.newFile.writesHidden)
    }

    /// The entries that write the templates in `state` as the config's own, which is what the first change of a config that defines none comes to.
    private static func writtenOut(_ rows: [TemplateRowState]) -> [ConfigOperation] {
        rows.map { row in
            var fields = [ConfigField("id", .string(row.id)), ConfigField("title", .string(row.title)), ConfigField("extension", .string(row.fileExtension))]
            if row.baseName != "untitled" { fields.append(ConfigField("base_name", .string(row.baseName))) }
            if !row.contents.isEmpty { fields.append(ConfigField("contents", .string(row.contents))) }
            if let app = row.openWith { fields.append(ConfigField("open_with", .string(app))) }
            // Without it, a Word template written out would make an empty file named .docx, which Word cannot open.
            if let format = row.format { fields.append(ConfigField("format", .string(format.rawValue))) }
            return .addEntry(to: table, fields: fields, at: nil)
        }
    }

    /// The entries that write the built-in templates out as the config's own, in the words of `localizer`: a config that defines any template replaces them, so the first template that is added to a
    /// config that defines none has to come with them, whoever adds it (the window does, and so does `rh config add new_file.template`).
    public static func builtInEntries(localizer: Localizer) -> [ConfigOperation] {
        writtenOut(NewFileTemplate.builtIn.map { template in
            TemplateRowState(id: template.id, title: template.localizedTitle(localizer), baseName: template.localizedBaseName(localizer), fileExtension: template.fileExtension,
                             contents: template.contents, openWith: template.openWith, entry: nil, format: template.format)
        })
    }

    /// The built-in templates made the person's own, so that they can be changed. `nil` once they are. They go to the shared file, which every Mac reads, unless that file defines templates (this Mac
    /// turns them all off): written there they would be added to every other Mac, so they go to this Mac's own file.
    public static func customizing(_ state: NewFileState) -> FileChange? {
        guard state.isBuiltIn else { return nil }
        return FileChange(target: state.sharedDefinesTemplates ? .local : .shared, operations: writtenOut(state.seed))
    }

    private static func change(_ row: TemplateRowState, at entry: EntryLocation, _ operations: [ConfigOperation]) -> FileChange {
        FileChange(target: entry.target, operations: [.expectEntry(row.id, at: entry.position, in: table)] + operations)
    }

    private static func key(_ position: Int, _ field: String) -> String { "new_file.template.\(position).\(field)" }

    public static func changing(title: String, of row: TemplateRowState) -> FileChange? {
        let text = title.trimmingCharacters(in: .whitespaces)
        guard let entry = row.entry, !text.isEmpty, text != row.title else { return nil }
        return change(row, at: entry, [.set(key(entry.position, "title"), .string(text))])
    }

    /// The file name a template has when it says none.
    static let defaultBaseName = "untitled"

    /// The file name without its extension. Nothing typed, and the default (`untitled`), are the setting taken out: a field that was emptied says the name is the default one.
    public static func changing(baseName: String, of row: TemplateRowState) -> FileChange? {
        let typed = baseName.trimmingCharacters(in: .whitespaces)
        let text = typed.isEmpty ? defaultBaseName : typed
        guard let entry = row.entry, text != row.baseName else { return nil }
        return change(row, at: entry, [text == defaultBaseName ? .unset(key(entry.position, "base_name")) : .set(key(entry.position, "base_name"), .string(text))])
    }

    public static func changing(fileExtension: String, of row: TemplateRowState) -> FileChange? {
        let text = fileExtension.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let entry = row.entry, !text.isEmpty, text != row.fileExtension else { return nil }
        return change(row, at: entry, [.set(key(entry.position, "extension"), .string(text))])
    }

    /// What a new file holds. Not trimmed, and a line break is part of it; empty is the setting taken out.
    public static func changing(contents: String, of row: TemplateRowState) -> FileChange? {
        guard let entry = row.entry, contents != row.contents else { return nil }
        return change(row, at: entry, [contents.isEmpty ? .unset(key(entry.position, "contents")) : .set(key(entry.position, "contents"), .string(contents))])
    }

    /// The app that opens a new file after it is made; `nil` is the default editor, which is the setting taken out.
    public static func changing(openWith: String?, of row: TemplateRowState) -> FileChange? {
        guard let entry = row.entry, openWith != row.openWith else { return nil }
        return change(row, at: entry, [openWith.map { .set(key(entry.position, "open_with"), .string($0)) } ?? .unset(key(entry.position, "open_with"))])
    }

    /// What happens after a file is made; "select it in Finder" is what happens when nothing is said, so that is the setting taken out.
    /// It is a setting like the others: the file that decides it on this Mac is the one it is written to.
    public static let hiddenKey = "new_file.hidden"

    /// Whether the New File submenu offers a template: its id taken out of `new_file.hidden`, or added. The list as the window showed it is expected, so that a change made meanwhile is refused.
    public static func operations(settingShown shown: Bool, of row: TemplateRowState, in state: NewFileState) -> [ConfigOperation] {
        guard shown != row.shown else { return [] }
        let guardList: ConfigOperation = .expect(state.hidden.isEmpty && !state.writesHidden ? nil : state.hidden, in: hiddenKey)
        if shown {
            guard let index = state.hidden.firstIndex(of: row.id) else { return [] }
            return [guardList, .remove(at: index + 1, from: hiddenKey)]
        }
        return [guardList, .insert(row.id, into: hiddenKey)]
    }

    public static func operations(settingThen then: Config.AfterNewFile, in state: NewFileState) -> [ConfigOperation] {
        guard then != state.then else { return [] }
        return [then == .reveal ? .unset("new_file.then") : .set("new_file.then", .string(then.rawValue))]
    }

    /// The entry taken out. The last one gives the built-in templates back.
    public static func removing(_ row: TemplateRowState) -> FileChange? {
        guard let entry = row.entry else { return nil }
        return change(row, at: entry, [.removeEntry(at: entry.position, from: table)])
    }

    /// A new template with a title and an extension. The id is made from the title and is not one that a template shown or a file has. While the templates are the built-in ones, they are
    /// written out first: the first template that a config defines would otherwise take their place.
    public static func creating(title: String, fileExtension: String, in state: NewFileState, alsoTaken: Set<String> = []) -> (id: String, change: FileChange)? {
        let name = title.trimmingCharacters(in: .whitespaces), ext = fileExtension.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !name.isEmpty, !ext.isEmpty else { return nil }
        // This Mac shows the built-in templates: one of the config's own replaces them wherever it is written, so they are written out with it. The config defines templates: a new one goes to the file
        // that every Mac reads when that file defines some, and to this Mac's own file when only that one does, so that nothing changes on the other Macs.
        let writesBuiltIn = state.isBuiltIn
        let intoLocal = writesBuiltIn ? state.sharedDefinesTemplates : !state.sharedDefinesTemplates
        let taken = Set(state.rows.map(\.id) + (writesBuiltIn ? state.seed.map(\.id) : [])).union(alsoTaken)
        let id = IDSlug.unique(IDSlug.make(from: name) ?? "template") { taken.contains($0) }
        let seed = writesBuiltIn ? writtenOut(state.seed) : []
        let new = ConfigOperation.addEntry(to: table, fields: [ConfigField("id", .string(id)), ConfigField("title", .string(name)), ConfigField("extension", .string(ext))], at: nil)
        return (id, FileChange(target: intoLocal ? .local : .shared, operations: seed + [new]))
    }
}
