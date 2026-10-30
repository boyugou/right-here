import Foundation
import Synchronization
import Testing
import RightHereCore
@testable import RightHereKit

/// The service changes files in a folder of its own; none of these touch the real home.
@Suite("ConfigService: edits made under the lock, kept for undo")
struct ConfigServiceTests {
    private static let sample = """
    # Mine.
    [general]
    terminal = "ghostty" # keep
    agents = ["claude", "codex"]

    [menu]
    items = ["open-terminal", "open-editor", "-", "agents"]

    # Presets.
    [[preset]]
    id = "alpha"
    title = "Alpha"
    prompt = "Alpha {files}"
    """ + "\n"

    private struct Workspace {
        let root: URL
        let paths: RHPaths
        let service: ConfigService

        init(config: String? = ConfigServiceTests.sample, now: @escaping @Sendable () -> Date = { Date() }) throws {
            root = try makeTemporaryDirectory()
            paths = RHPaths(environment: [:], home: root)
            service = ConfigService(paths: paths, now: now, environment: [:])
            if let config {
                try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
                try config.write(to: paths.configFile, atomically: true, encoding: .utf8)
            }
        }

        var text: String { (try? String(contentsOf: paths.configFile, encoding: .utf8)) ?? "" }
        var localText: String? { try? String(contentsOf: paths.localConfigFile, encoding: .utf8) }
        func clean() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func aChangeOfThisMacsFileThatGivesASettingOfTheSharedFileAnErrorIsRefusedAndNothingIsWritten() throws {
        // The shared file names what this Mac's file defines: an app that is a terminal, an editor, an app that a template opens a file with. Changing or taking out that app in this Mac's file would leave
        // the merged config with an error in the shared file's setting, which no editor is open to show.
        let shared = "[general]\nterminal = \"mt\"\neditor = \"ed\"\nagents = [\"claude\"]\n\n[[new_file.template]]\nid = \"t\"\ntitle = \"T\"\nextension = \"t\"\nopen_with = \"ed\"\n"
        let local = "[[app]]\nid = \"mt\"\nname = \"MT\"\nbundle_id = \"com.example.mt\"\nrole = \"terminal\"\n\n[[app]]\nid = \"ed\"\nname = \"Ed\"\nbundle_id = \"com.example.ed\"\nrole = \"editor\"\n"
        let work = try Workspace(config: shared); defer { work.clean() }
        try local.write(to: work.paths.localConfigFile, atomically: true, encoding: .utf8)
        #expect(!ConfigStore.load(paths: work.paths).result.hasErrors, "it reads before the change")
        for (operation, why) in [(ConfigOperation.set("app.1.role", .string("editor")), "the default terminal is an editor now"),
                                 (.set("app.2.role", .string("terminal")), "the default editor and a template's app is a terminal now"),
                                 (.removeEntry(at: 2, from: "app"), "the default editor is gone")] {
            do { _ = try work.service.apply(operation, target: .local, actor: .cli); Issue.record("expected a refusal: \(why)") } catch let error as ConfigDocument.EditError {
                guard case .wouldBeInvalid = error else { Issue.record("\(error)"); continue }
            }
            #expect(work.localText == local, "nothing was written: \(why)")
        }
        // A change that leaves it reading is made, and so is one of a setting the shared file does not name.
        _ = try work.service.apply(.set("app.2.name", .string("Ed 2")), target: .local, actor: .cli)
        #expect(work.localText?.contains("name = \"Ed 2\"") == true)
        #expect(!ConfigStore.load(paths: work.paths).result.hasErrors)
    }

    @Test func theFirstChangeOfAListSeedsItWithWhatTheReadersOfTheFileItGoesToGet() throws {
        // The shared file lists two agents and this Mac turns one of them off: the Quick Actions' default list is not the same for this Mac and for the others.
        let shared = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\", \"codex\"]\n"
        let work = try Workspace(config: shared); defer { work.clean() }
        try "disabled = [\"claude\"]\n".write(to: work.paths.localConfigFile, atomically: true, encoding: .utf8)
        let others = try work.service.operations(for: ConfigRequest(.add, "services.items", values: ["copy-path.name"]), target: .shared)
        guard case .set(_, .strings(let forOthers))? = others.first else { Issue.record("no list was written first: \(others)"); return }
        #expect(forOthers.contains("agent.claude") && forOthers.contains("agent.codex") && others.last == .insert("copy-path.name", into: "services.items", at: nil),
                "what the other Macs have, which read the shared file alone: \(forOthers)")
        let here = try work.service.operations(for: ConfigRequest(.add, "services.items", values: ["copy-path.name"]), target: .local)
        guard case .set(_, .strings(let forThisMac))? = here.first else { Issue.record("no list was written first: \(here)"); return }
        #expect(!forThisMac.contains("agent.claude") && forThisMac.contains("agent.codex"), "what this Mac shows: \(forThisMac)")
    }

    @Test func aChangeOfThisMacsFileToAListThatOnlyTheSharedFileWritesAddsToThatListAndDoesNotReplaceItWithTheDefault() throws {
        let shared = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n\n[menu]\nitems = [\"open\", \"-\", \"agents\"]\n\n[services]\nitems = [\"open.terminal\"]\n\n[copy_path]\nstyles = [\"name\"]\n"
        let work = try Workspace(config: shared); defer { work.clean() }
        for (key, item) in [("menu.items", "presets"), ("services.items", "copy-path.name"), ("copy_path.styles", "parent")] {
            _ = try work.service.apply(ConfigRequest(.add, key, values: [item]), target: .local, actor: .cli)
        }
        let merged = ConfigStore.load(paths: work.paths).config
        #expect(merged.menuItems == ["open", "-", "agents", "presets"] && merged.serviceItems == ["open.terminal", "copy-path.name"] && merged.copyPathStyles == [.name, .parent],
                "this Mac's list is the shared list and the item: \(work.localText ?? "")")
        #expect(ConfigStore.sharedConfig(paths: work.paths).menuItems == ["open", "-", "agents"], "the shared file is as it was")
    }

    @Test func theFirstTemplateAddedToAConfigThatDefinesNoneComesWithTheBuiltInOnesAndOneOfTheirIdsReplacesThatOne() throws {
        let work = try Workspace(config: "[general]\nterminal = \"ghostty\"\n"); defer { work.clean() }
        _ = try work.service.apply(ConfigRequest(.add, "new_file.template", values: ["id=notes", "title=Notes", "extension=txt"]), actor: .cli)
        #expect(ConfigStore.load(paths: work.paths).config.newFile.templates.map(\.id) == ["txt", "md", "docx", "xlsx", "pptx", "notes"], "the config would otherwise have lost the built-in templates on every Mac")
        // A config that defines templates already gets no more of them.
        _ = try work.service.apply(ConfigRequest(.add, "new_file.template", values: ["id=more", "title=More", "extension=md"]), actor: .cli)
        #expect(ConfigStore.load(paths: work.paths).config.newFile.templates.map(\.id) == ["txt", "md", "docx", "xlsx", "pptx", "notes", "more"])
        let replaced = try Workspace(config: "[general]\nterminal = \"ghostty\"\n"); defer { replaced.clean() }
        _ = try replaced.service.apply(ConfigRequest(.add, "new_file.template", values: ["id=txt", "title=Plain", "extension=txt"]), actor: .cli)
        let templates = ConfigStore.load(paths: replaced.paths).config.newFile.templates
        #expect(templates.map(\.id) == ["md", "docx", "xlsx", "pptx", "txt"] && templates.last?.title == "Plain", "an entry with a built-in id replaces that one, and the other built-in templates stay: \(templates.map(\.id))")
        // The Office templates are written out with their format: without it a Word template made an empty file named .docx.
        #expect(templates.first { $0.id == "docx" }?.format == .docx && templates.first { $0.id == "pptx" }?.format == .pptx)
    }

    @Test func theNoteThatThisMacsFileDecidesAsWellIsAboutTheEntryWithTheSameIdAndNotTheSamePlace() throws {
        func entry(_ id: String, _ name: String) -> String { "[[app]]\nid = \"\(id)\"\nname = \"\(name)\"\nbundle_id = \"com.example.\(id)\"\n" }
        let different = try Workspace(config: "[general]\nterminal = \"ghostty\"\n\n" + entry("aa", "AA")); defer { different.clean() }
        try entry("bb", "BB").write(to: different.paths.localConfigFile, atomically: true, encoding: .utf8)
        let renamed = try different.service.apply(.set("app.1.name", .string("AA 2")), actor: .cli)
        #expect(!renamed.warnings.contains { $0.contains("as well") }, "the first entry of the other file is another entry: \(renamed.warnings)")
        let same = try Workspace(config: "[general]\nterminal = \"ghostty\"\n\n" + entry("pulsar", "Shared")); defer { same.clean() }
        try entry("pulsar", "Here").write(to: same.paths.localConfigFile, atomically: true, encoding: .utf8)
        let renamedSame = try same.service.apply(.set("app.1.name", .string("Shared 2")), actor: .cli, dryRun: true)
        #expect(renamedSame.warnings.contains { $0.contains("an entry \"pulsar\" in [[app]] as well") } && !renamedSame.warnings.contains { $0.contains("sets app.1.name") }, "\(renamedSame.warnings)")
        let removal = try same.service.apply(ConfigRequest(.remove, "app", item: "pulsar"), actor: .cli)
        #expect(removal.warnings.contains { $0.contains("an entry \"pulsar\" in [[app]] as well") }, "this Mac's entry decides here: \(removal.warnings)")
        // A plain setting that this Mac's file sets as well is noted as it was.
        let plain = try Workspace(config: "[general]\nterminal = \"ghostty\"\n"); defer { plain.clean() }
        try "[general]\nterminal = \"terminal\"\n".write(to: plain.paths.localConfigFile, atomically: true, encoding: .utf8)
        let note = try plain.service.apply(.set("general.terminal", .string("iterm")), actor: .cli)
        #expect(note.warnings.contains { $0.contains("sets general.terminal as well") })
    }

    @Test func anEditChangesOnlyTheLineAndKeepsTheComment() throws {
        let work = try Workspace(); defer { work.clean() }
        let change = try work.service.apply(.set("general.terminal", .string("terminal")), actor: .cli)
        #expect(work.text == Self.sample.replacingOccurrences(of: "terminal = \"ghostty\" # keep", with: "terminal = \"terminal\" # keep"))
        #expect(change.changed && change.written)
        #expect(change.summary == "set general.terminal = \"terminal\"")
        #expect(change.diff == ["@@ -1,5 +1,5 @@", " # Mine.", " [general]", "-terminal = \"ghostty\" # keep", "+terminal = \"terminal\" # keep", " agents = [\"claude\", \"codex\"]", " ", ])
        #expect(change.file == work.paths.configFile.path && change.target == .shared)
    }

    @Test func aDryRunSaysWhatWouldChangeAndWritesNothingNotEvenHistory() throws {
        let work = try Workspace(); defer { work.clean() }
        let change = try work.service.apply(.unset("general.terminal"), actor: .mcp, dryRun: true)
        #expect(change.changed && !change.written && !change.diff.isEmpty)
        #expect(work.text == Self.sample)
        #expect(work.service.history().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: work.paths.historyDirectory.path))
    }

    @Test func anEditThatChangesNothingWritesNothing() throws {
        let work = try Workspace(); defer { work.clean() }
        let before = try FileManager.default.attributesOfItem(atPath: work.paths.configFile.path)[.modificationDate] as? Date
        let change = try work.service.apply(.set("general.terminal", .string("ghostty")), actor: .cli)
        #expect(!change.changed && !change.written && change.diff.isEmpty)
        #expect(try FileManager.default.attributesOfItem(atPath: work.paths.configFile.path)[.modificationDate] as? Date == before)
        #expect(work.service.history().isEmpty, "a change that was none is nothing to undo")
        // Unsetting what was never set is the same.
        let unset = try work.service.apply(.unset("general.editor"), actor: .cli)
        #expect(!unset.changed && !unset.written)
    }

    @Test func aRefusedEditLeavesTheFileAndTheHistoryAlone() throws {
        let work = try Workspace(); defer { work.clean() }
        #expect(throws: ConfigDocument.EditError.self) { try work.service.apply(.set("general.terminal", .string("nonsense")), actor: .cli) }
        #expect(throws: ConfigDocument.EditError.self) { try work.service.apply(.set("general.nope", .string("x")), actor: .cli) }
        #expect(work.text == Self.sample)
        #expect(work.service.history().isEmpty)
    }

    @Test func severalChangesAreOneEditAndOneUndo() throws {
        let work = try Workspace(); defer { work.clean() }
        let change = try work.service.apply([.insert("open-with", into: "menu.items", at: 1), .move(from: 1, to: 4, in: "menu.items")], actor: .window)
        #expect(change.summary == "add \"open-with\" to menu.items at 1; move item 1 of menu.items to 4")
        #expect(work.service.history().count == 1)
        _ = try work.service.undo()
        #expect(work.text == Self.sample)
        // One that fails halfway writes none of them.
        #expect(throws: ConfigDocument.EditError.self) {
            try work.service.apply([.insert("open-with", into: "menu.items", at: 1), .remove(at: 99, from: "menu.items")], actor: .window)
        }
        #expect(work.text == Self.sample)
    }

    @Test func aCheckIsNotPartOfTheSummaryAndAFailedOneWritesNothing() throws {
        let work = try Workspace(); defer { work.clean() }
        let change = try work.service.apply([.expect(["claude", "codex"], in: "general.agents"), .remove(at: 1, from: "general.agents")], actor: .window)
        #expect(change.summary == "remove item 1 of general.agents", "the history says what was done, not what was checked")
        #expect(work.service.history().map(\.summary) == ["remove item 1 of general.agents"])
        let afterwards = work.text
        // Another process changed the list after the window read it.
        #expect(throws: ConfigDocument.EditError.changedMeanwhile("general.agents")) {
            try work.service.apply([.expect(["claude", "codex"], in: "general.agents"), .remove(at: 1, from: "general.agents")], actor: .window)
        }
        #expect(work.text == afterwards && work.service.history().count == 1, "refused before anything was written or recorded")
    }

    @Test func theItemsOfAListAreThoseOfTheFileThatDecidesIt() throws {
        let work = try Workspace(); defer { work.clean() }
        #expect(work.service.listed("general.agents") == ["claude", "codex"])
        #expect(work.service.listed("services.items") == nil, "a list nobody writes")
        try "[general]\nagents = [\"gemini\"]\n".write(to: work.paths.localConfigFile, atomically: true, encoding: .utf8)
        #expect(work.service.owner(of: "general.agents") == .local)
        #expect(work.service.listed("general.agents") == ["gemini"], "this Mac's own file decides, and it is the one that is edited")
        #expect(work.service.listed("menu.items") == ["open-terminal", "open-editor", "-", "agents"], "the shared file still decides what the other does not write")
        #expect(work.service.listed("general.terminal") == nil, "a setting that is not a list")
    }

    // MARK: A request is looked at under the lock

    @Test func aListTheFileDoesNotWriteIsChangedAsItIs() throws {
        let work = try Workspace(config: "[general]\nterminal = \"ghostty\"\n"); defer { work.clean() }
        _ = try work.service.apply(ConfigRequest(.add, "menu.items", values: ["presets"]), actor: .cli)
        #expect(try ConfigDocument(work.text).elements(of: "menu.items") == MenuBuilder.defaultItems + ["presets"], "the default menu and a preset, and not a menu of one item")
        _ = try work.service.apply(ConfigRequest(.add, "copy_path.styles", values: ["parent"], at: "first"), actor: .cli)
        #expect(try ConfigDocument(work.text).elements(of: "copy_path.styles") == ["parent"] + Config.defaultCopyPathStyles.map(\.rawValue))
        _ = try work.service.apply(ConfigRequest(.add, "services.items", values: ["copy-path.name"]), actor: .cli)
        #expect(try ConfigDocument(work.text).elements(of: "services.items") == ["open.terminal", "open.editor", "new-file.md", "copy-path.absolute", "copy-path.git-relative", "copy-path.name"])
        #expect(work.text.hasPrefix("[general]\nterminal = \"ghostty\"\n"), "what was there is as it was")
    }

    @Test func anItemOfTheDefaultMenuCanBeTakenOutAndMovedWithoutWritingTheListFirst() throws {
        let work = try Workspace(config: "[general]\nterminal = \"ghostty\"\n"); defer { work.clean() }
        _ = try work.service.apply(ConfigRequest(.remove, "menu.items", item: "agents"), actor: .cli)
        var expected = MenuBuilder.defaultItems
        expected.removeAll { $0 == "agents" }
        #expect(try ConfigDocument(work.text).elements(of: "menu.items") == expected)
        _ = try work.service.apply(ConfigRequest(.move, "menu.items", item: "copy-path", to: "first"), actor: .cli)
        expected.insert(expected.removeLast(), at: 0)
        #expect(try ConfigDocument(work.text).elements(of: "menu.items") == expected)
        // The two are two edits of the history, and the first undo takes back the move only.
        _ = try work.service.undo()
        #expect(try ConfigDocument(work.text).elements(of: "menu.items")?.first == "open-terminal")
    }

    @Test func aListThatIsWrittenIsNotWrittenAgain() throws {
        let work = try Workspace(); defer { work.clean() }
        _ = try work.service.apply(ConfigRequest(.add, "menu.items", values: ["presets"]), actor: .cli)
        #expect(try ConfigDocument(work.text).elements(of: "menu.items") == ["open-terminal", "open-editor", "-", "agents", "presets"])
    }

    @Test func aRequestIsLookedAtOnlyOnceTheLockIsHeld() throws {
        // The lock is held by somebody else while the request arrives; the list changes meanwhile; the request, which names "agents", takes out "agents" and not what stood at its old place.
        let work = try Workspace(config: "[menu]\nitems = [\"open-terminal\", \"open-editor\", \"-\", \"agents\"]\n"); defer { work.clean() }
        let lock = try FileLock.acquireNow(work.paths.configLockFile, timeout: .seconds(1))
        #expect(lock.isHeld)
        let service = work.service
        let failure = Mutex<(any Error)?>(nil)
        let started = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        // A thread of its own: on a busy machine the shared pool of `DispatchQueue.global()` can be full of the sleeping tests around this one, and the request would not start for seconds.
        Thread {
            started.signal()
            do { _ = try service.apply(ConfigRequest(.remove, "menu.items", item: "agents"), actor: .cli) } catch { failure.withLock { $0 = error } }
            done.signal()
        }.start()
        #expect(started.wait(timeout: .now() + 30) == .success)
        // The request is waiting for the lock now: one that had looked at the file first has its answer already.
        Thread.sleep(forTimeInterval: 0.3)
        try "[menu]\nitems = [\"presets\", \"open-terminal\", \"open-editor\", \"-\", \"agents\"]\n".write(to: work.paths.configFile, atomically: true, encoding: .utf8)
        lock.release()
        #expect(done.wait(timeout: .now() + 30) == .success)
        #expect(failure.withLock { $0 } == nil)
        #expect(try ConfigDocument(work.text).elements(of: "menu.items") == ["presets", "open-terminal", "open-editor", "-"], "\(work.text)")
    }

    @Test func twoRequestsMadeAtTheSameTimeEachChangeWhatTheyNamed() throws {
        // `remove menu.items C` and `add menu.items X --at 1`, in either order, leave [X, A, B, D]: the place of C is looked for when the change is made, not before.
        for round in 0..<80 {
            let work = try Workspace(config: "[menu]\nitems = [\"open-terminal\", \"open-editor\", \"-\", \"agents\"]\n"); defer { work.clean() }
            let service = work.service
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                _ = try? service.apply(index == 0 ? ConfigRequest(.remove, "menu.items", item: "-") : ConfigRequest(.add, "menu.items", values: ["presets"], at: "first"), actor: .cli)
            }
            #expect(try ConfigDocument(work.text).elements(of: "menu.items") == ["presets", "open-terminal", "open-editor", "agents"], "round \(round): \(work.text)")
        }
    }

    // MARK: What the files and the folder do to an edit

    @Test func twoConfigsInOneFolderEachHaveTheirOwnHistory() throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("configs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let work = folder.appendingPathComponent("work.toml"), home = folder.appendingPathComponent("home.toml")
        for file in [work, home] { try "[general]\nterminal = \"ghostty\" # \(file.lastPathComponent)\n".write(to: file, atomically: true, encoding: .utf8) }
        let workService = ConfigService(paths: RHPaths(environment: ["RH_CONFIG": work.path], home: root), environment: [:])
        let homeService = ConfigService(paths: RHPaths(environment: ["RH_CONFIG": home.path], home: root), environment: [:])
        _ = try workService.apply(.set("general.terminal", .string("terminal")), actor: .cli)
        #expect(workService.history().count == 1 && homeService.history().isEmpty, "the edit of work.toml is not an edit of home.toml")
        #expect(throws: ConfigService.Failure.nothingToUndo(.shared)) { try homeService.undo(force: true) }
        let homeText = try String(contentsOf: home, encoding: .utf8)
        #expect(homeText.contains("# home.toml"), "home.toml still has its own text")
        _ = try homeService.apply(.set("general.terminal", .string("iterm")), actor: .cli)
        _ = try homeService.undo()
        #expect(try String(contentsOf: home, encoding: .utf8) == homeText && workService.history().count == 1)
    }

    @Test func anEditIsRefusedWhenTheLockCannotBeTaken() throws {
        let work = try Workspace(); defer { work.clean() }
        let elsewhere = work.root.appendingPathComponent("elsewhere.lock")
        try Data().write(to: elsewhere)
        // A link in place of the lock file, as a tool that links the files of a config folder makes it: it is not opened (a link is never followed), so nothing is locked.
        try FileManager.default.createSymbolicLink(at: work.paths.configLockFile, withDestinationURL: elsewhere)
        #expect(throws: ConfigService.Failure.lockUnavailable(work.paths.configLockFile.path)) { try work.service.apply(.set("general.terminal", .string("terminal")), actor: .cli) }
        #expect(work.text == Self.sample && work.service.history().isEmpty)
    }

    @Test func anEditThatCannotBeWrittenCostsNoHistory() throws {
        let work = try Workspace(); defer { work.clean(); try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: work.paths.configDirectory.path) }
        for index in 0..<ConfigHistory.keep { _ = try work.service.apply(.set("general.terminal", .string(index.isMultiple(of: 2) ? "terminal" : "ghostty")), actor: .cli) }
        #expect(work.service.history().count == ConfigHistory.keep)
        let oldest = try FileManager.default.contentsOfDirectory(atPath: work.paths.historyDirectory.path).sorted().first
        // The folder cannot be written to, so the new file cannot be made (the lock and the history are in places that can).
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: work.paths.configDirectory.path)
        #expect(throws: (any Error).self) { try work.service.apply(.set("general.terminal", .string("iterm")), actor: .cli) }
        #expect(work.service.history().count == ConfigHistory.keep, "the edit that failed did not push the oldest out")
        #expect(try FileManager.default.contentsOfDirectory(atPath: work.paths.historyDirectory.path).sorted().first == oldest)
    }

    @Test func aClockBehindTheNewestEntryDoesNotMakeAnEditSpin() throws {
        let work = try Workspace(); defer { work.clean() }
        let ahead = try ConfigService(paths: work.paths, now: { Date().addingTimeInterval(3600) }, environment: [:])
        _ = try ahead.apply(.set("general.terminal", .string("terminal")), actor: .cli)
        let took = try ContinuousClock().measure { _ = try work.service.apply(.set("general.terminal", .string("iterm")), actor: .cli) }
        #expect(took < .seconds(1), "\(took)")
        let names = try FileManager.default.contentsOfDirectory(atPath: work.paths.historyDirectory.path).sorted()
        #expect(names.count == 2)
        _ = try work.service.undo()
        #expect(work.text.contains("terminal = \"terminal\""), "the last edit is the one that is taken back, whatever the clock said")
    }

    @Test func aFileKeepsItsByteOrderMarkThroughAnEditAndItsUndo() throws {
        let work = try Workspace(); defer { work.clean() }
        let original = Data([0xEF, 0xBB, 0xBF]) + Data(Self.sample.utf8)
        try original.write(to: work.paths.configFile)
        _ = try work.service.apply(.set("general.terminal", .string("terminal")), actor: .cli)
        let edited = try Data(contentsOf: work.paths.configFile)
        #expect(edited.starts(with: [0xEF, 0xBB, 0xBF]) && String(decoding: edited.dropFirst(3), as: UTF8.self).contains("terminal = \"terminal\""))
        _ = try work.service.undo()
        #expect(try Data(contentsOf: work.paths.configFile) == original, "byte for byte, the mark included")
    }

    @Test func aFileThatEndsItsLinesWithCRLFKeepsThemThroughEditsAndUndo() throws {
        let work = try Workspace(); defer { work.clean() }
        let text = Self.sample.replacingOccurrences(of: "\n", with: "\r\n").replacingOccurrences(of: "items = [\"open-terminal\"", with: "items = [\r\n    # agents last, always\r\n    \"open-terminal\"")
        let original = Data(text.utf8)
        try original.write(to: work.paths.configFile)
        _ = try work.service.apply(ConfigRequest(.set, "general.editor", values: ["vscode"]), actor: .cli)
        _ = try work.service.apply(ConfigRequest(.remove, "menu.items", item: "open-terminal"), actor: .cli)
        _ = try work.service.apply(ConfigRequest(.add, "menu.items", values: ["presets"], at: "first"), actor: .cli)
        let edited = try String(contentsOf: work.paths.configFile, encoding: .utf8)
        let bare = edited.replacingOccurrences(of: "\r\n", with: "").contains("\n")
        #expect(!bare && edited.contains("\r\n"), "a line feed was put among the CRLF: \(edited.debugDescription)")
        #expect(edited.contains("editor = \"vscode\"") && edited.contains("presets") && !edited.contains("# agents last, always"), "the comment went with the item it belonged to")
        for _ in 0..<3 { _ = try work.service.undo() }
        #expect(try Data(contentsOf: work.paths.configFile) == original, "three undos, and the file is the bytes it was")
        // The diff is lines, not one line.
        let change = try work.service.apply(ConfigRequest(.set, "general.terminal", values: ["terminal"]), actor: .cli, dryRun: true)
        #expect(change.diff.count > 3 && change.diff.contains("-terminal = \"ghostty\" # keep"), "\(change.diff)")
    }

    @Test func aFileThatWasMadeReadOnlyIsLeftAlone() throws {
        let work = try Workspace(); defer { work.clean() }
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: work.paths.configFile.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: work.paths.configFile.path) }
        #expect(throws: ConfigService.Failure.readOnly(work.paths.configFile.path)) { try work.service.apply(.set("general.terminal", .string("terminal")), actor: .cli) }
        #expect(work.text == Self.sample && work.service.history().isEmpty)
    }

    @Test func takingBackTheEditThatMadeThisMacsFileRemovesTheFile() throws {
        let work = try Workspace(); defer { work.clean() }
        #expect(!FileManager.default.fileExists(atPath: work.paths.localConfigFile.path))
        _ = try work.service.apply(.set("general.terminal", .string("terminal")), target: .local, actor: .cli)
        #expect(FileManager.default.fileExists(atPath: work.paths.localConfigFile.path))
        _ = try work.service.undo(target: .local)
        #expect(!FileManager.default.fileExists(atPath: work.paths.localConfigFile.path), "no file, and not an empty one")
        // A file that was there, empty, is put back as it was.
        try "".write(to: work.paths.localConfigFile, atomically: true, encoding: .utf8)
        _ = try work.service.apply(.set("general.terminal", .string("terminal")), target: .local, actor: .cli)
        _ = try work.service.undo(target: .local)
        #expect(FileManager.default.fileExists(atPath: work.paths.localConfigFile.path) && work.localText == "")
    }

    // MARK: The text as the window's editor has it

    @Test func theTextOfAFileComesWithTheDigestThatGuardsASaveOfIt() throws {
        let work = try Workspace(); defer { work.clean() }
        let shared = try work.service.text()
        #expect(shared.text == Self.sample && shared.exists && shared.digest == ConfigHistory.digest(Self.sample))
        let local = try work.service.text(of: .local)
        #expect(local.text == "" && !local.exists && local.digest == ConfigHistory.digest(""))
        try "[general]\nterminal = \"iterm\"\n".write(to: work.paths.localConfigFile, atomically: true, encoding: .utf8)
        #expect(try work.service.text(of: .local).exists)
    }

    @Test func aTextSavedFromTheEditorReplacesTheFileAndCanBeTakenBack() throws {
        let work = try Workspace(); defer { work.clean() }
        let read = try work.service.text()
        let written = "# Mine, in my own order.\n[general]\nagents = [\"codex\", \"claude\"]\nterminal = \"terminal\"\n"
        let change = try work.service.apply([.replaceText(written)], actor: .window, unchangedSince: read.digest)
        #expect(change.written && work.text == written && change.summary == "edit the text of the file")
        #expect(work.service.history().map(\.actor) == [.window])
        _ = try work.service.undo()
        #expect(work.text == Self.sample)
    }

    @Test func aTextIsNotSavedOverAChangeMadeWhileItWasBeingEdited() throws {
        let work = try Workspace(); defer { work.clean() }
        let read = try work.service.text()
        _ = try work.service.apply(.set("general.terminal", .string("terminal")), actor: .cli)
        let error = #expect(throws: ConfigService.Failure.self) {
            try work.service.apply([.replaceText("[general]\nterminal = \"iterm\"\n")], actor: .window, unchangedSince: read.digest)
        }
        #expect(error == .editedMeanwhile(file: work.paths.configFile.path))
        #expect(work.text.contains("terminal = \"terminal\""), "the change made meanwhile is still there")
        #expect(work.service.history().count == 1, "and nothing was kept for the save that was refused")
        // A save of the text that was read, when nothing changed meanwhile, goes through; so does one without a digest (the other edits make none).
        let again = try work.service.text()
        #expect(try work.service.apply([.replaceText(Self.sample)], actor: .window, unchangedSince: again.digest).written)
    }

    @Test func aTextThatDoesNotReadIsRefusedAndTheFileIsLeftAlone() throws {
        let work = try Workspace(); defer { work.clean() }
        #expect(throws: ConfigDocument.EditError.self) { try work.service.apply([.replaceText("[general\n")], actor: .window) }
        #expect(throws: ConfigDocument.EditError.self) { try work.service.apply([.replaceText("[general]\nterminal = \"nonsense\"\n")], actor: .window) }
        #expect(work.text == Self.sample && work.service.history().isEmpty)
    }

    @Test func aFileThatDoesNotReadIsPutRightByTextAndByNothingElse() throws {
        let broken = "[general\nterminal = \"ghostty\"\n"
        let work = try Workspace(config: broken); defer { work.clean() }
        #expect(throws: ConfigDocument.EditError.self) { try work.service.apply(.set("general.terminal", .string("iterm")), actor: .window) }
        let fixed = "[general]\nterminal = \"ghostty\"\n"
        #expect(try work.service.apply([.replaceText(fixed)], actor: .window, unchangedSince: try work.service.text().digest).written)
        #expect(work.text == fixed)
    }

    @Test func theMachinesOwnFileIsReplacedAsTextToo() throws {
        let work = try Workspace(); defer { work.clean() }
        let read = try work.service.text(of: .local)
        let text = "[general]\nterminal = \"tower\"\n"
        // tower is not defined by the shared file: read over it, the overlay is refused.
        #expect(throws: ConfigDocument.EditError.self) { try work.service.apply([.replaceText(text)], target: .local, actor: .window, unchangedSince: read.digest) }
        let fine = "[general]\nterminal = \"terminal\"\n"
        #expect(try work.service.apply([.replaceText(fine)], target: .local, actor: .window, unchangedSince: read.digest).written)
        #expect(work.localText == fine && work.text == Self.sample)
    }

    // MARK: Undo

    @Test func undoPutsBackTheExactTextAndForgetsTheEdit() throws {
        let work = try Workspace(); defer { work.clean() }
        _ = try work.service.apply(.set("general.terminal", .string("terminal")), actor: .cli)
        _ = try work.service.apply(.insert("open-with", into: "menu.items", at: 2), actor: .mcp)
        _ = try work.service.apply(.removeEntry(at: 1, from: "preset"), actor: .window)
        #expect(work.service.history().map(\.actor) == [.window, .mcp, .cli])
        let undone = try work.service.undo()
        #expect(undone.summary == "undo: remove entry 1 of preset" && undone.written && undone.changed)
        #expect(work.text.contains("id = \"alpha\"") && work.text.contains("open-with"))
        _ = try work.service.undo()
        _ = try work.service.undo()
        #expect(work.text == Self.sample, "three undos give back the bytes the file began with")
        #expect(work.service.history().isEmpty)
        #expect(throws: ConfigService.Failure.nothingToUndo(.shared)) { try work.service.undo() }
    }

    @Test func undoRefusesAFileThatWasChangedAfterTheLastEditUnlessForced() throws {
        let work = try Workspace(); defer { work.clean() }
        _ = try work.service.apply(.set("general.terminal", .string("terminal")), actor: .cli)
        // The person edits the file by hand.
        try (work.text + "\n# my note\n").write(to: work.paths.configFile, atomically: true, encoding: .utf8)
        #expect(throws: ConfigService.Failure.changedSince(file: work.paths.configFile.path)) { try work.service.undo() }
        #expect(work.text.hasSuffix("# my note\n"), "nothing was undone")
        #expect(work.service.history().count == 1, "and the edit can still be undone")
        let dry = try work.service.undo(force: true, dryRun: true)
        #expect(!dry.written && work.text.hasSuffix("# my note\n"))
        let forced = try work.service.undo(force: true)
        #expect(forced.written && work.text == Self.sample)
    }

    @Test func undoBringsBackTheTextOfTheOverlayToo() throws {
        let work = try Workspace(); defer { work.clean() }
        _ = try work.service.apply(.set("general.terminal", .string("iterm")), target: .local, actor: .cli)
        #expect(work.localText == "[general]\nterminal = \"iterm\"\n")
        #expect(work.service.history(of: .local).count == 1 && work.service.history(of: .shared).isEmpty)
        _ = try work.service.undo(target: .local)
        #expect(work.localText == nil, "the edit made the file, so taking it back leaves none (and not an empty one that `rh config show` lists)")
        #expect(throws: ConfigService.Failure.nothingToUndo(.shared)) { try work.service.undo() }
    }

    @Test func editsMadeInTheSameMillisecondAreUndoneNewestFirst() throws {
        let frozen = Date(timeIntervalSince1970: 1_800_000_000)
        let work = try Workspace(now: { frozen }); defer { work.clean() }
        let names = ["a", "b", "c", "d", "e", "f"]
        for name in names { _ = try work.service.apply(.insert(name, into: "menu.items"), actor: .cli) }
        #expect(work.service.history().map(\.summary) == names.reversed().map { "add \"\($0)\" to menu.items" })
        for name in names.reversed() {
            let undone = try work.service.undo()
            #expect(undone.summary == "undo: add \"\(name)\" to menu.items")
        }
        #expect(work.text == Self.sample)
    }

    @Test func theHistoryKeepsTheNewestFiftyOfAFile() throws {
        let tick = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        let work = try Workspace(now: { tick.withLock { $0.addTimeInterval(1); return $0 } }); defer { work.clean() }
        for round in 0..<(ConfigHistory.keep + 5) {
            _ = try work.service.apply(.set("copy_path.title", .string("Copy \(round)")), actor: .cli)
        }
        let items = work.service.history()
        #expect(items.count == ConfigHistory.keep)
        #expect(items.first?.summary == "set copy_path.title = \"Copy \(ConfigHistory.keep + 4)\"")
        #expect(items.last?.summary == "set copy_path.title = \"Copy 5\"", "the five oldest were forgotten")
        #expect(items.first!.time > items.last!.time)
    }

    // MARK: The file

    @Test func thereIsNoFirstEditWithoutAConfig() throws {
        let work = try Workspace(config: nil); defer { work.clean() }
        #expect(throws: ConfigService.Failure.noConfig(work.paths.configFile.path)) { try work.service.apply(.set("general.terminal", .string("ghostty")), actor: .cli) }
        #expect(throws: ConfigService.Failure.noConfig(work.paths.configFile.path)) { try work.service.apply(.set("general.terminal", .string("ghostty")), target: .local, actor: .cli) }
        #expect(!FileManager.default.fileExists(atPath: work.paths.configFile.path), "an edit must not stand in for the first run")
        #expect(!FileManager.default.fileExists(atPath: work.paths.localConfigFile.path))
        // Nor is a folder made for the lock of a config that is not there.
        #expect(!FileManager.default.fileExists(atPath: work.paths.configLockFile.path) && !FileManager.default.fileExists(atPath: work.paths.configDirectory.path))
        for call in [{ _ = try work.service.undo() }, { _ = try work.service.submit([.set("agent.claude.args", .strings(["x"]))], actor: .mcp) }, { _ = try work.service.pending() }] as [() throws -> Void] {
            _ = try? call()
        }
        #expect(!FileManager.default.fileExists(atPath: work.paths.configDirectory.path), "undo and a proposal leave the folder alone as well")
    }

    @Test func aFileThatCannotBeReadIsSaidAndNotOverwritten() throws {
        let work = try Workspace(config: ""); defer { work.clean() }
        try Data([0xFF, 0xFE, 0x00, 0x80]).write(to: work.paths.configFile)
        do {
            _ = try work.service.apply(.set("general.terminal", .string("ghostty")), actor: .cli)
            Issue.record("accepted")
        } catch let failure as ConfigService.Failure {
            guard case .unreadable(let file, _) = failure else { Issue.record("\(failure)"); return }
            #expect(file == work.paths.configFile.path)
        }
        #expect(try Data(contentsOf: work.paths.configFile) == Data([0xFF, 0xFE, 0x00, 0x80]))
    }

    @Test func aConfigThatIsALinkStaysALinkAndTheFileItPointsToChanges() throws {
        let work = try Workspace(config: nil); defer { work.clean() }
        let dotfiles = work.root.appendingPathComponent("dotfiles"); try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        let real = dotfiles.appendingPathComponent("right-here.toml")
        try Self.sample.write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: work.paths.configDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: work.paths.configFile, withDestinationURL: real)
        _ = try work.service.apply(.set("general.terminal", .string("terminal")), actor: .cli)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: work.paths.configFile.path)) == real.path, "the link was replaced by a file")
        #expect(try String(contentsOf: real, encoding: .utf8).contains("terminal = \"terminal\" # keep"))
    }

    @Test func aFileKeepsItsPermissions() throws {
        let work = try Workspace(); defer { work.clean() }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: work.paths.configFile.path)
        _ = try work.service.apply(.set("general.terminal", .string("terminal")), actor: .cli)
        #expect((try FileManager.default.attributesOfItem(atPath: work.paths.configFile.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func aWriteThatFailsIsNotKeptInTheHistory() throws {
        let work = try Workspace(); defer { work.clean() }
        // The history is made, and then the folder stops taking files: the edit cannot be written, so it must not be offered for undo.
        try FileManager.default.createDirectory(at: work.paths.historyDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: work.paths.configDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: work.paths.configDirectory.path) }
        #expect(throws: (any Error).self) { try work.service.apply(.set("general.terminal", .string("terminal")), actor: .cli) }
        #expect(work.service.history().isEmpty)
        #expect(work.text == Self.sample)
    }

    @Test func theHistoryKeepsAtMostSomeMegabytesOfTextAndAlwaysTheNewestEdit() throws {
        // A config may be a megabyte, and an edit keeps the whole text it replaced: an edit loop must not be able to fill the disk with fifty of them.
        let work = try Workspace(); defer { work.clean() }
        let big = "# " + String(repeating: "x", count: 1_000_000) + "\n"
        try (Self.sample + big).write(to: work.paths.configFile, atomically: true, encoding: .utf8)
        for index in 1...20 {
            _ = try work.service.apply(.set("general.terminal", .string(index.isMultiple(of: 2) ? "terminal" : "ghostty")), actor: .mcp)
        }
        let kept = work.service.history()
        #expect(kept.count < 20 && kept.count >= 7, "20 edits of a megabyte, of which about \(ConfigHistory.maxBytes / 1_000_000) fit: \(kept.count)")
        let files = try FileManager.default.contentsOfDirectory(at: work.paths.historyDirectory, includingPropertiesForKeys: [.fileSizeKey])
        let bytes = try files.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        #expect(bytes < ConfigHistory.maxBytes + 1_200_000, "\(bytes)")
        _ = try work.service.undo()
        #expect(work.service.history().count == kept.count - 1, "the newest edit is the one that was kept and can be undone")
    }

    @Test func editsMadeAtTheSameTimeAreAllKeptAndAllUndoable() throws {
        // Run again and again: an edit that reads the file before another has written it loses that edit only now and then.
        var lost: [String] = []
        for round in 0..<30 {
            let work = try Workspace(); defer { work.clean() }
            let items = (0..<8).map { "item-\($0)" }
            let failures = Mutex<[String]>([])
            DispatchQueue.concurrentPerform(iterations: items.count) { index in
                do { _ = try work.service.apply(.insert(items[index], into: "menu.items"), actor: .cli) } catch { failures.withLock { $0.append("\(error)") } }
            }
            let document = ConfigDocument(work.text)
            let missing = items.filter { (try? document.position(ofElement: $0, in: "menu.items")) == nil }
            if !failures.withLock({ $0 }).isEmpty || !missing.isEmpty || work.service.history().count != items.count {
                lost.append("round \(round): failed \(failures.withLock { $0 }), missing \(missing), history \(work.service.history().count)")
            }
            for _ in items { _ = try? work.service.undo() }
            if work.text != Self.sample { lost.append("round \(round): the undos did not give back the file") }
        }
        #expect(lost.isEmpty, "\(lost.count) rounds went wrong; the first: \(lost.first ?? "")")
    }

    // MARK: The overlay and what is worth saying

    @Test func theOverlayIsMadeOnFirstUseAndIsCheckedAgainstTheSharedFile() throws {
        let shared = Self.sample + "\n[[app]]\nid = \"tower\"\nname = \"Tower\"\nbundle_id = \"com.fournova.Tower3\"\nrole = \"terminal\"\n"
        let work = try Workspace(config: shared); defer { work.clean() }
        let change = try work.service.apply(.set("general.terminal", .string("tower")), target: .local, actor: .window)
        #expect(change.target == .local && change.file == work.paths.localConfigFile.path)
        #expect(work.localText == "[general]\nterminal = \"tower\"\n")
        #expect(work.text == shared, "the shared file was not touched")
        #expect(throws: ConfigDocument.EditError.self) { try work.service.apply(.set("general.terminal", .string("nonsense")), target: .local, actor: .window) }
    }

    @Test func theFileThatDecidesAKeyIsTheMachinesOwnOnlyWhenItSetsIt() throws {
        let work = try Workspace(); defer { work.clean() }
        #expect(work.service.owner(of: "menu.items") == .shared, "there is no overlay")
        try "[general]\nterminal = \"iterm\"\n".write(to: work.paths.localConfigFile, atomically: true, encoding: .utf8)
        #expect(work.service.owner(of: "general.terminal") == .local)
        #expect(work.service.owner(of: "menu.items") == .shared && work.service.owner(of: "general.agents") == .shared)
        try "[menu]\nitems = []\n".write(to: work.paths.localConfigFile, atomically: true, encoding: .utf8)
        #expect(work.service.owner(of: "menu.items") == .local)
        try Data([0xFF, 0xFE]).write(to: work.paths.localConfigFile)
        #expect(work.service.owner(of: "menu.items") == .shared, "an overlay that cannot be read decides nothing")
    }

    @Test func aSharedEditOfASettingTheOverlayAlsoSetsSaysThatItDoesNotReachThisMac() throws {
        let work = try Workspace(); defer { work.clean() }
        try "[general]\nterminal = \"iterm\"\n".write(to: work.paths.localConfigFile, atomically: true, encoding: .utf8)
        let change = try work.service.apply(.set("general.terminal", .string("terminal")), actor: .cli)
        #expect(change.warnings == ["note: config.local.toml sets general.terminal as well, and it decides on this Mac: the change reaches other Macs, not this one (--local changes this Mac's own setting)."])
        let other = try work.service.apply(.insert("open-with", into: "menu.items"), actor: .cli)
        #expect(other.warnings.isEmpty, "a setting the overlay does not set says nothing: \(other.warnings)")
    }

    @Test func onlyTheWarningsTheChangeBroughtAreSaid() throws {
        // The file has a warning already (an item that is nothing); an edit elsewhere does not repeat it, and one that adds another says only that one.
        let work = try Workspace(config: Self.sample.replacingOccurrences(of: "\"agents\"]", with: "\"nonsense-a\"]")); defer { work.clean() }
        let quiet = try work.service.apply(.set("general.terminal", .string("terminal")), actor: .cli)
        #expect(quiet.warnings.isEmpty, "\(quiet.warnings)")
        let added = try work.service.apply(.insert("nonsense-b", into: "menu.items"), actor: .cli)
        #expect(added.warnings.count == 1 && added.warnings[0].contains("nonsense-b") && added.warnings[0].hasPrefix("warning: config.toml:"), "\(added.warnings)")
    }

    // MARK: Writing under the real home

    @Test func aConfigThatIsALinkIntoTheRealHomeIsNotWrittenByATestEither() throws {
        // The config folder is elsewhere, but the file in it is the person's own, which a dotfiles manager links there.
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let realHome = root.appendingPathComponent("home")
        let real = realHome.appendingPathComponent("dotfiles/right-here.toml")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.sample.write(to: real, atomically: true, encoding: .utf8)
        let folder = root.appendingPathComponent("trial-config")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("config.toml"), withDestinationURL: real)
        let paths = RHPaths(environment: ["RH_CONFIG_DIR": folder.path], home: root.appendingPathComponent("trial-home"))
        let service = ConfigService(paths: paths, environment: ["RH_NO_UI": "1"], realHome: realHome)
        #expect(throws: RealHomeGuard.Refusal()) { try service.apply(.set("general.terminal", .string("terminal")), actor: .cli) }
        #expect(try String(contentsOf: real, encoding: .utf8) == Self.sample)
        #expect(service.history().isEmpty, "the text before an edit that was refused is not kept")
    }

    @Test func aProcessATestStartedDoesNotWriteTheRealConfig() throws {
        let work = try Workspace(); defer { work.clean() }
        let guarded = ConfigService(paths: work.paths, environment: ["RH_NO_UI": "1"], realHome: work.root)
        for call in [
            { _ = try guarded.apply(.set("general.terminal", .string("terminal")), actor: .cli) },
            { _ = try guarded.apply(.set("general.terminal", .string("terminal")), actor: .cli, dryRun: true) },
            { _ = try guarded.undo() }
        ] as [() throws -> Void] {
            #expect(throws: RealHomeGuard.Refusal()) { try call() }
        }
        #expect(work.text == Self.sample)
        #expect(!FileManager.default.fileExists(atPath: work.paths.historyDirectory.path), "not even the history or the lock was made")
        #expect(!FileManager.default.fileExists(atPath: work.paths.configLockFile.path))
        // With a trial home, or from a person's terminal, or for a config elsewhere, it writes.
        let trial = ConfigService(paths: work.paths, environment: ["RH_NO_UI": "1", "RH_HOME": work.root.path], realHome: work.root)
        _ = try trial.apply(.set("general.terminal", .string("terminal")), actor: .cli)
        let person = ConfigService(paths: work.paths, environment: [:], realHome: work.root)
        _ = try person.apply(.set("general.terminal", .string("iterm")), actor: .cli)
        let elsewhere = ConfigService(paths: work.paths, environment: ["RH_NO_UI": "1"], realHome: URL(fileURLWithPath: "/nonexistent-home"))
        _ = try elsewhere.apply(.set("general.terminal", .string("wezterm")), actor: .cli)
    }
}
