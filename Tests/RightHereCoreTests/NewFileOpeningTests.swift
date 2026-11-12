import Foundation
import Testing
@testable import RightHereCore

/// Where a new file is made and what opens it, as an independent review (2026-11-12) found them.
@Suite("New File: where and with what")
struct NewFileOpeningTests {
    private let folder = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code"))

    private func machine(_ installed: [String] = ["com.microsoft.VSCode"]) -> FakeSystemFacts {
        FakeSystemFacts(directories: ["/Users/tester/code"],
                        applications: Dictionary(uniqueKeysWithValues: installed.map { ($0, URL(fileURLWithPath: "/Applications/\($0).app")) }))
    }

    /// A blank Word, Excel or PowerPoint document goes to the app this Mac opens that kind with, not to the code editor: Right Here chose both its extension and its bytes.
    @Test("a blank Office document opens with the app the system opens its kind with", arguments: ["docx", "xlsx", "pptx"])
    func anOfficeDocumentIsNotOpenedInACodeEditor(id: String) throws {
        var config = Config()
        config.newFile.then = .open
        let plan = try Planner(config: config, facts: machine()).plan(.newFile(id), context: folder)
        #expect(plan.steps.last == .open(OpenStep(bundleID: nil, targets: ["/Users/tester/code/untitled.\(id)"])), "\(plan.steps)")
        // A text file of the config's own is never handed to whatever the system picks.
        let text = try Planner(config: config, facts: machine()).plan(.newFile("md"), context: folder)
        #expect(text.steps.last == .open(OpenStep(bundleID: "com.microsoft.VSCode", targets: ["/Users/tester/code/untitled.md"])))
    }

    /// The app a template names opens the file; when it cannot (it is not installed, or it would run the file), what opens it instead is said.
    @Test func aTemplatesOwnAppThatCannotOpenTheFileIsReplacedWithANote() throws {
        var config = Config()
        config.newFile.then = .open
        config.newFile.templates = [NewFileTemplate(id: "md", title: "Markdown", fileExtension: "md", openWith: "typora")]
        let plan = try Planner(config: config, facts: machine()).plan(.newFile("md"), context: folder)
        #expect(plan.steps.last == .open(OpenStep(bundleID: "com.microsoft.VSCode", targets: ["/Users/tester/code/untitled.md"])))
        #expect(plan.notices.contains { $0.contains("Typora cannot open the new file") && $0.contains("Visual Studio Code opens it") }, "\(plan.notices)")
    }

    /// The window offers no app under "Opens with" that the planner would never use: one that says it runs shell scripts is a terminal.
    @Test func theWindowOffersNoAppThatANewFileIsNeverOpenedWith() throws {
        let result = ConfigParser.parse("[[app]]\nid = \"hyper\"\nname = \"Hyper\"\nbundle_id = \"co.zeit.hyper\"\n\n[[new_file.template]]\nid = \"md\"\ntitle = \"Markdown\"\nextension = \"md\"\nopen_with = \"hyper\"\n\n[new_file]\nthen = \"open\"\n")
        #expect(!result.hasErrors, "\(result.diagnostics)")
        var facts = machine(["com.microsoft.VSCode", "co.zeit.hyper"])
        facts.shellApps = ["co.zeit.hyper"]
        #expect(!NewFileOptions.state(config: result.config, entries: [:], facts: facts, localizer: .english).apps.contains { $0.id == "hyper" })
        let plan = try Planner(config: result.config, facts: facts).plan(.newFile("md"), context: folder)
        #expect(plan.steps.last == .open(OpenStep(bundleID: "com.microsoft.VSCode", targets: ["/Users/tester/code/untitled.md"])))
        #expect(plan.notices.contains { $0.contains("Hyper cannot open the new file") }, "\(plan.notices)")
    }

    /// A selected package is one item, as Finder shows it: a new file goes next to it, not into it (inside an app it broke the signature), and so does a terminal.
    /// A package one has opened (the viewed folder) is where the new file goes.
    @Test func aSelectedPackageIsOneItemAndAnOpenedOneIsAFolder() throws {
        var facts = FakeSystemFacts(directories: ["/Users/tester/code", "/Users/tester/code/Foo.app", "/Users/tester/code/Notes.rtfd"],
                                    applications: ["com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")])
        facts.packages = ["/Users/tester/code/Foo.app", "/Users/tester/code/Notes.rtfd"]
        var config = Config()
        config.newFile.then = .nothing
        for package in ["Foo.app", "Notes.rtfd"] {
            let selected = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/" + package)])
            #expect(selected.workingDirectory(facts: facts)?.path == "/Users/tester/code")
            let made = try Planner(config: config, facts: facts).plan(.newFile("txt"), context: selected)
            #expect(made.steps.first == .createFile(CreateFileStep(path: "/Users/tester/code/untitled.txt", contents: "")), "\(made.steps)")
        }
        let opened = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code/Foo.app"))
        #expect(opened.workingDirectory(facts: facts)?.path == "/Users/tester/code/Foo.app")
        // A plain folder that is selected is still the folder itself.
        #expect(HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code")]).workingDirectory(facts: facts)?.path == "/Users/tester/code")
    }

    /// A template without an extension (a Dockerfile, a .gitignore) is named by its base name alone, and the window can take the extension away.
    @Test func aTemplateWithoutAnExtensionIsNamedByItsBaseName() throws {
        let result = ConfigParser.parse("[[new_file.template]]\nid = \"docker\"\ntitle = \"Dockerfile\"\nextension = \"\"\nbase_name = \"Dockerfile\"\n[new_file]\nthen = \"nothing\"\n")
        #expect(!result.hasErrors, "\(result.diagnostics.map(\.message))")
        var facts = machine()
        let plan = try Planner(config: result.config, facts: facts).plan(.newFile("docker"), context: folder)
        #expect(plan.steps.first == .createFile(CreateFileStep(path: "/Users/tester/code/Dockerfile", contents: "")), "\(plan.steps)")
        facts.files = ["/Users/tester/code/Dockerfile"]
        let second = try Planner(config: result.config, facts: facts).plan(.newFile("docker"), context: folder)
        #expect(second.steps.first == .createFile(CreateFileStep(path: "/Users/tester/code/Dockerfile 2", contents: "")))
        #expect(ConfigParser.parse("[[new_file.template]]\nid = \"x\"\ntitle = \"X\"\nextension = \".x\"\n").hasErrors, "a dot is still refused")
        let row = TemplateRowState(id: "md", title: "Markdown", baseName: "untitled", fileExtension: "md", contents: "", openWith: nil, entry: EntryLocation(target: .shared, position: 1), format: nil, shown: true)
        #expect(NewFileOptions.changing(fileExtension: "", of: row) != nil)
    }
}
