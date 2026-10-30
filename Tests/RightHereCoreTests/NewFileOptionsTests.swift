import Foundation
import Testing
@testable import RightHereCore

private func config(_ text: String) -> Config { ConfigParser.parse(text).config }

@Suite("NewFileOptions: the new-file templates as lines to edit")
struct NewFileOptionsTests {
    private let facts = FakeSystemFacts(applications: ["com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app"), "com.apple.Terminal": URL(fileURLWithPath: "/Applications/Terminal.app")])

    private let own = """
    [new_file]
    then = "open"

    [[new_file.template]]
    id = "py"
    title = "Python Script"
    extension = "py"
    base_name = "script"
    contents = "#!/usr/bin/env python3\\n"
    open_with = "vscode"

    [[new_file.template]]
    id = "txt"
    title = "Notes"
    extension = "txt"
    """ + "\n"

    private func state(_ text: String? = nil, entries: [String: EntryLocation]? = nil) -> NewFileState {
        NewFileOptions.state(config: config(text ?? own), entries: entries ?? ["py": EntryLocation(target: .shared, position: 1), "txt": EntryLocation(target: .shared, position: 2)], facts: facts, localizer: .english)
    }

    private func apply(_ change: FileChange, to text: String) throws -> Config {
        var document = ConfigDocument(text)
        for operation in change.operations { document = try operation.apply(to: document) }
        return config(document.text)
    }

    @Test func theRowsAreTheBuiltInTemplatesWhileTheConfigDefinesNoneAndTheConfigsOwnAfterwards() throws {
        let builtIn = state("[general]\nterminal = \"ghostty\"\n", entries: [:])
        #expect(builtIn.isBuiltIn && builtIn.rows.map(\.id) == ["txt", "md", "docx", "xlsx", "pptx"] && builtIn.rows.allSatisfy { $0.entry == nil } && builtIn.rows[0].title == "Text Document" && builtIn.rows[0].baseName == "untitled")
        let mine = state()
        #expect(!mine.isBuiltIn && mine.rows.map(\.id) == ["py", "txt"] && mine.then == .open)
        #expect(mine.rows[0].contents == "#!/usr/bin/env python3\n" && mine.rows[0].openWith == "vscode" && mine.rows[0].baseName == "script" && mine.rows[0].entry == EntryLocation(target: .shared, position: 1))
        #expect(mine.rows[1].title == "Notes" && mine.rows[1].baseName == "untitled", "a template of the config that has the id of a built-in one is the config's")
        #expect(mine.apps.map(\.id).contains("vscode") && !mine.apps.map(\.id).contains("terminal"), "a terminal would run the file, and an app that is not installed is not offered")
    }

    @Test func theBuiltInTemplatesAreWrittenOutAsTheConfigsOwnAndThenBehaveAsThey_Did() throws {
        let plain = "[general]\nterminal = \"ghostty\"\n"
        let builtIn = state(plain, entries: [:])
        let customize = try #require(NewFileOptions.customizing(builtIn))
        let made = try apply(customize, to: plain)
        #expect(made.newFile.templates.map(\.id) == ["txt", "md", "docx", "xlsx", "pptx"] && made.newFile.templates.map(\.fileExtension) == ["txt", "md", "docx", "xlsx", "pptx"]
                && made.newFile.templates[0].title == "Text Document")
        #expect(made.newFile.templates.map(\.format) == [nil, nil, .docx, .xlsx, .pptx], "written out, the Office templates still make Office documents")
        #expect(NewFileOptions.customizing(state()) == nil, "once they are the config's there is nothing to write out")
    }

    @Test func aTemplateIsWrittenOutWithEverythingItHasAndWithNothingThatIsTheDefault() throws {
        let keys = { (change: FileChange) in change.operations.compactMap { operation -> [String]? in if case .addEntry(_, let fields, _) = operation { fields.map(\.key) } else { nil } } }
        let builtIn = try #require(NewFileOptions.customizing(state("[general]\nterminal = \"ghostty\"\n", entries: [:])))
        #expect(keys(builtIn) == [["id", "title", "extension"], ["id", "title", "extension"], ["id", "title", "extension", "format"], ["id", "title", "extension", "format"],
                                  ["id", "title", "extension", "format"]], "the built-in templates say nothing that is the default: no file name, no contents, no app; the Office ones their format")
        let row = TemplateRowState(id: "a", title: "A", baseName: "notes", fileExtension: "md", contents: "# x\n", openWith: "vscode", entry: nil)
        let custom = NewFileState(rows: [row], isBuiltIn: true, then: .reveal, apps: [])
        #expect(keys(try #require(NewFileOptions.customizing(custom))) == [["id", "title", "extension", "base_name", "contents", "open_with"]])
    }

    @Test func aNewTemplateWritesOutTheBuiltInOnesFirstSoThatTheyAreNotReplacedAndOnceTheyAreItDoesNot() throws {
        let plain = "[general]\nterminal = \"ghostty\"\n"
        let builtIn = state(plain, entries: [:])
        let first = try #require(NewFileOptions.creating(title: "Python Script", fileExtension: ".py", in: builtIn))
        #expect(first.id == "python-script" && first.change.operations.count == 6)
        let made = try apply(first.change, to: plain)
        #expect(made.newFile.templates.map(\.id) == ["txt", "md", "docx", "xlsx", "pptx", "python-script"], "the built-in templates are still there")
        #expect(made.newFile.templates.last?.fileExtension == "py", "the dot of an extension is not part of it")
        let second = try #require(NewFileOptions.creating(title: "Go File", fileExtension: "go", in: state()))
        #expect(second.change.operations.count == 1 && second.id == "go-file")
        #expect(try apply(second.change, to: own).newFile.templates.map(\.id) == ["py", "txt", "go-file"])
        #expect(NewFileOptions.creating(title: "Notes", fileExtension: "txt", in: state())?.id == "notes")
        #expect(NewFileOptions.creating(title: "Txt", fileExtension: "txt", in: state())?.id == "txt-2", "the id of a template that is there is taken")
        #expect(NewFileOptions.creating(title: " ", fileExtension: "x", in: state()) == nil && NewFileOptions.creating(title: "A", fileExtension: " . ", in: state()) == nil)
    }

    @Test func eachFieldIsOneChangeInTheFileThatHoldsTheEntryUnderTheCheckOfItsPlace() throws {
        let py = state().rows[0]
        let title = try #require(NewFileOptions.changing(title: " Python ", of: py))
        #expect(title.operations == [.expectEntry("py", at: 1, in: "new_file.template"), .set("new_file.template.1.title", .string("Python"))] && title.target == .shared)
        #expect(try apply(title, to: own).newFile.templates[0].title == "Python")
        #expect(NewFileOptions.changing(title: "Python Script", of: py) == nil && NewFileOptions.changing(title: " ", of: py) == nil)
        let base = try #require(NewFileOptions.changing(baseName: "main", of: py))
        #expect(try apply(base, to: own).newFile.templates[0].baseName == "main")
        #expect(NewFileOptions.changing(baseName: "untitled", of: py)?.operations.last == .unset("new_file.template.1.base_name"), "the default name is the setting taken out")
        let ext = try #require(NewFileOptions.changing(fileExtension: "pyw", of: py))
        #expect(try apply(ext, to: own).newFile.templates[0].fileExtension == "pyw")
        #expect(NewFileOptions.changing(fileExtension: "  ", of: py) == nil && NewFileOptions.changing(fileExtension: "py", of: py) == nil, "an extension is never empty")
        #expect(NewFileOptions.changing(fileExtension: ".pyw", of: py)?.operations.last == .set("new_file.template.1.extension", .string("pyw")) && NewFileOptions.changing(fileExtension: ".py", of: py) == nil, "the dot of an extension is not part of it, as when a template is made")
        #expect(NewFileOptions.changing(baseName: " ", of: py)?.operations.last == .unset("new_file.template.1.base_name"), "a field that was emptied says the name is the default one")
        #expect(NewFileOptions.changing(baseName: "", of: state().rows[1]) == nil, "and a template that has the default name has nothing to change")
        let contents = try #require(NewFileOptions.changing(contents: "line one\nline two\n", of: py))
        #expect(try apply(contents, to: own).newFile.templates[0].contents == "line one\nline two\n", "a line break is part of what a new file holds")
        #expect(NewFileOptions.changing(contents: "", of: py)?.operations.last == .unset("new_file.template.1.contents"))
        #expect(NewFileOptions.changing(contents: "#!/usr/bin/env python3", of: py) != nil && NewFileOptions.changing(contents: py.contents + "\n", of: py) != nil, "a line break at the end is part of what a new file holds")
        #expect(NewFileOptions.changing(contents: py.contents, of: py) == nil)
        let app = try #require(NewFileOptions.changing(openWith: nil, of: py))
        #expect(app.operations.last == .unset("new_file.template.1.open_with"))
        #expect(try apply(app, to: own).newFile.templates[0].openWith == nil)
        #expect(NewFileOptions.changing(openWith: "vscode", of: py) == nil)
    }

    @Test func everyInstalledAppThatCanOpenAFileIsOfferedAndNoTerminalIs() throws {
        let text = "[[app]]\nid = \"mdviewer\"\nname = \"MD Viewer\"\nbundle_id = \"com.microsoft.VSCode\"\n\n[[new_file.template]]\nid = \"md\"\ntitle = \"M\"\nextension = \"md\"\nopen_with = \"mdviewer\"\n"
        let offered = state(text, entries: ["md": EntryLocation(target: .shared, position: 1)]).apps.map(\.id)
        #expect(offered.contains("mdviewer") && offered.contains("vscode") && !offered.contains("terminal"), "\(offered)")
        #expect(state(text, entries: [:]).apps.allSatisfy { $0.id != "terminal" })
    }

    @Test func aBuiltInTemplateHasNoEntryToChangeAndATemplateInThisMacsFileIsChangedThere() throws {
        let builtIn = state("[general]\nterminal = \"ghostty\"\n", entries: [:]).rows[0]
        #expect(NewFileOptions.changing(title: "x", of: builtIn) == nil && NewFileOptions.removing(builtIn) == nil)
        #expect(NewFileOptions.changing(baseName: "x", of: builtIn) == nil && NewFileOptions.changing(fileExtension: "x", of: builtIn) == nil)
        #expect(NewFileOptions.changing(contents: "x", of: builtIn) == nil && NewFileOptions.changing(openWith: "vscode", of: builtIn) == nil)
        let local = state(entries: ["py": EntryLocation(target: .local, position: 4), "txt": EntryLocation(target: .shared, position: 2)]).rows[0]
        let change = try #require(NewFileOptions.changing(title: "x", of: local))
        #expect(change.target == .local && change.operations.first == .expectEntry("py", at: 4, in: "new_file.template"))
    }

    @Test func whatHappensAfterAFileIsMadeAndTakingATemplateOut() throws {
        let current = state()
        let reveal = NewFileOptions.operations(settingThen: .reveal, in: current)
        #expect(reveal == [.unset("new_file.then")])
        #expect(try apply(FileChange(target: .shared, operations: reveal), to: own).newFile.then == .reveal)
        let nothing = NewFileOptions.operations(settingThen: .nothing, in: current)
        #expect(try apply(FileChange(target: .shared, operations: nothing), to: own).newFile.then == .nothing)
        #expect(NewFileOptions.operations(settingThen: .open, in: current).isEmpty)
        let removed = try #require(NewFileOptions.removing(current.rows[0]))
        #expect(try apply(removed, to: own).newFile.templates.map(\.id) == ["txt"])
        // The last one gives the built-in templates back.
        let one = "[[new_file.template]]\nid = \"py\"\ntitle = \"Python Script\"\nextension = \"py\"\n"
        let lonely = try #require(NewFileOptions.removing(state(one, entries: ["py": EntryLocation(target: .shared, position: 1)]).rows[0]))
        #expect(try apply(lonely, to: one).newFile.templates == NewFileTemplate.builtIn)
    }

    @Test func aTemplateTheConfigWouldRefuseIsRefusedWhereItIsWritten() throws {
        let py = state().rows[0]
        for bad in ["a.b", "a/b", ""] {
            if let change = NewFileOptions.changing(fileExtension: bad, of: py) {
                #expect(throws: ConfigDocument.EditError.self, "\(bad.debugDescription)") { try apply(change, to: own) }
            }
        }
        let name = try #require(NewFileOptions.changing(baseName: "a/b", of: py))
        #expect(throws: ConfigDocument.EditError.self) { try apply(name, to: own) }
        let unknownApp = try #require(NewFileOptions.changing(openWith: "nothing-like-it", of: py))
        #expect(throws: ConfigDocument.EditError.self) { try apply(unknownApp, to: own) }
    }
}

@Suite("NewFileTemplate: the words of the menu item of a built-in template that was written out")
struct NewFileTemplateWordsTests {
    @Test("a built-in template written out as the config's own keeps the phrase of its menu item in every language", arguments: ["fr", "es", "ru", "zh-Hans", "ar", "ur", "de", "it"])
    func theWrittenOutTemplateSaysWhatTheBuiltInOneSays(language: String) {
        let localizer = Localizer(languages: [language])
        for builtIn in NewFileTemplate.builtIn {
            let written = NewFileTemplate(id: builtIn.id, title: builtIn.localizedTitle(localizer), baseName: builtIn.localizedBaseName(localizer), fileExtension: builtIn.fileExtension)
            #expect(written.localizedNewTitle(localizer) == builtIn.localizedNewTitle(localizer), "\(language) \(builtIn.id)")
        }
    }

    @Test func aTemplateOfTheConfigWithAnotherTitleComposesItsOwn() {
        let localizer = Localizer(languages: ["fr"])
        let renamed = NewFileTemplate(id: "txt", title: "Notes", fileExtension: "txt")
        #expect(renamed.localizedNewTitle(localizer) == localizer.newFile("Notes") && renamed.localizedNewTitle(localizer) != NewFileTemplate.text.localizedNewTitle(localizer))
        let other = NewFileTemplate(id: "py", title: NewFileTemplate.text.localizedTitle(localizer), fileExtension: "py")
        #expect(other.localizedNewTitle(localizer) == localizer.newFile(other.title), "only a built-in id has a built-in phrase")
    }
}
