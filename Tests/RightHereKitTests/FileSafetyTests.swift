import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

/// From an independent review (2026-11-08) of the operations that delete, move, overwrite or create files. Real `git` in throwaway repositories under the
/// temporary folder (`TestGit`); nothing here touches the home folder, Finder or an installed app.
@Suite("File safety: worktrees")
struct WorktreeSafetyTests {
    private func git(_ arguments: [String], in directory: URL) throws -> String { try TestGit.run(arguments, in: directory) }

    private func makeRepository(ignoring patterns: [String] = []) throws -> URL { try TestGit.repository(ignoring: patterns) }

    /// `rh worktree add` (WorktreeTarget.gitRoot), `rh run --worktree` and the MCP tool (`path`, or the server's working folder) all find the repository
    /// with `SystemFacts.gitRoot`, which stops at the first `.git`: inside a worktree that is the worktree's own `.git` file. A worktree asked for from
    /// there is made inside the outer worktree's folder, where the shared `info/exclude` line `.right-here` hides it from `git status`. A removal of the
    /// outer worktree without `--force` (the setup window, the MCP tool, `rh worktree remove`) then finds it clean and git deletes the folder with
    /// everything in it, the inner worktree's uncommitted work included.
    @Test func aRemovalWithoutForceDoesNotDeleteTheUncommittedWorkOfAWorktreeMadeFromInsideIt() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let outer = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "outer")
        let rootFromInside = try #require(LiveSystemFacts().gitRoot(containing: outer.worktreeURL))
        let inner = try await GitWorktreeManager.prepareWorktree(gitRoot: rootFromInside, branch: "inner")
        let work = inner.worktreeURL.appendingPathComponent("agent-work.txt")
        try "an agent's uncommitted work".write(to: work, atomically: true, encoding: .utf8)
        #expect(try git(["status", "--porcelain"], in: inner.worktreeURL).contains("agent-work.txt"), "the inner worktree has uncommitted work")

        _ = try? await GitWorktreeManager.removeWorktree(worktreePath: "outer", gitRoot: repository, deleteBranch: false, force: false)

        #expect(FileManager.default.fileExists(atPath: work.path),
                "a removal without --force deleted another worktree's uncommitted work (\(inner.worktreeURL.path) was inside \(outer.worktreeURL.path))")
    }

    /// The guard of `prepareWorktree` compares the folder's path as text, and git follows a link. A repository somebody sent can commit `.right-here` as a
    /// symbolic link, and the checkout of the new worktree (the repository's files) is then written wherever the link points.
    @Test func aRepositoryThatCommitsDotRightHereAsALinkGetsNoWorktreeOutsideIt() async throws {
        let repository = try makeRepository()
        let outside = repository.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repository); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(atPath: repository.appendingPathComponent(".right-here").path, withDestinationPath: "../" + outside.lastPathComponent)
        _ = try git(["add", ".right-here"], in: repository)
        _ = try git(["commit", "-q", "-m", "a link where Right Here keeps its worktrees"], in: repository)

        _ = try? await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "feature")

        let written = FileManager.default.enumerator(atPath: outside.path)?.allObjects as? [String] ?? []
        #expect(written.isEmpty, "the worktree was checked out outside the repository, in \(outside.path): \(written.prefix(5))")
    }

    /// The base `resolveManaged` holds a removal to is resolved through the same link: a worktree the person made, with plain `git worktree add`, in the
    /// folder the link points into, counts as one Right Here made, and is removed (the MCP tool needs only its name).
    @Test func aRepositoryThatCommitsDotRightHereAsALinkCannotMakeThePersonsOwnWorktreeRemovable() async throws {
        let repository = try makeRepository()
        let sibling = repository.deletingLastPathComponent().appendingPathComponent("sibling-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: repository); try? FileManager.default.removeItem(at: sibling) }
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let own = sibling.appendingPathComponent("worktrees/mine")
        _ = try git(["worktree", "add", "-q", "-b", "mine", own.path], in: repository)
        try FileManager.default.createSymbolicLink(atPath: repository.appendingPathComponent(".right-here").path, withDestinationPath: "../" + sibling.lastPathComponent)
        _ = try git(["add", ".right-here"], in: repository)
        _ = try git(["commit", "-q", "-m", "link"], in: repository)

        await #expect(throws: WorktreeError.self) {
            _ = try await GitWorktreeManager.removeWorktree(worktreePath: "mine", gitRoot: repository, deleteBranch: false, force: false)
        }
        #expect(FileManager.default.fileExists(atPath: own.appendingPathComponent("README.md").path), "the person's own worktree was removed")
    }

    /// `git worktree remove` without `--force` checks `git status --porcelain`, which does not list ignored files: a `.env` with a key that exists nowhere
    /// else, a local database, notes in an ignored folder are deleted by the removal the MCP tool describes as "never one with uncommitted work".
    @Test func aRemovalWithoutForceDoesNotDeleteIgnoredFilesThatExistOnlyInTheWorktree() async throws {
        let repository = try makeRepository(ignoring: [".env"])
        defer { try? FileManager.default.removeItem(at: repository) }
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "keys")
        let secret = made.worktreeURL.appendingPathComponent(".env")
        try "API_KEY=exists-only-here\n".write(to: secret, atomically: true, encoding: .utf8)

        _ = try? await GitWorktreeManager.removeWorktree(worktreePath: "keys", gitRoot: repository, deleteBranch: false, force: false)

        #expect(FileManager.default.fileExists(atPath: secret.path), "a removal without --force deleted an ignored file that existed only in the worktree")
    }

    /// A worktree made inside one of Right Here's (by hand, or by a Right Here that still made them there): removing the outer one would delete it with its work,
    /// which the outer one's `git status` does not see. It is refused, with force too: force is about the worktree's own changes.
    @Test func aWorktreeThatHoldsAnotherIsNotRemovedEvenWithForce() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let outer = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "outer")
        let inner = outer.worktreeURL.appendingPathComponent(".right-here/worktrees/inner")
        _ = try git(["worktree", "add", "-q", "-b", "inner", inner.path], in: repository)
        let work = inner.appendingPathComponent("work.txt")
        try "work".write(to: work, atomically: true, encoding: .utf8)
        for force in [false, true] {
            do {
                _ = try await GitWorktreeManager.removeWorktree(worktreePath: "outer", gitRoot: repository, force: force)
                Issue.record("removed with force: \(force)")
            } catch WorktreeError.holdsOtherWorktrees(_, let inside) {
                #expect(inside.count == 1 && inside.first?.hasSuffix("/.right-here/worktrees/inner") == true, "\(inside)")
            }
        }
        #expect(FileManager.default.fileExists(atPath: work.path))
    }

    /// Ignored files are named, and a removal is made only for exactly those the person agreed to lose: one that appeared since is asked about again.
    @Test func aRemovalIsHeldToTheIgnoredFilesThePersonAgreedToLose() async throws {
        let repository = try makeRepository(ignoring: [".env", "build/"])
        defer { try? FileManager.default.removeItem(at: repository) }
        let made = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "keys")
        try "API_KEY=1\n".write(to: made.worktreeURL.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: made.worktreeURL.appendingPathComponent("build/out"), withIntermediateDirectories: true)
        try "x".write(to: made.worktreeURL.appendingPathComponent("build/out/a.o"), atomically: true, encoding: .utf8)
        var named: [String] = []
        do {
            _ = try await GitWorktreeManager.removeWorktree(worktreePath: "keys", gitRoot: repository)
        } catch WorktreeError.ignoredFiles(_, let files) {
            named = files
        }
        #expect(named.sorted() == [".env", "build/"], "a folder of ignored files is one name: \(named)")
        try "y".write(to: made.worktreeURL.appendingPathComponent("build-notes.env"), atomically: true, encoding: .utf8)
        try "z".write(to: made.worktreeURL.appendingPathComponent("local.env"), atomically: true, encoding: .utf8)
        _ = try? git(["-C", made.worktreeURL.path, "status"], in: repository)
        await #expect(throws: (any Error).self, "the files are untracked now, not ignored: git refuses") {
            _ = try await GitWorktreeManager.removeWorktree(worktreePath: "keys", gitRoot: repository, ignoredAgreed: named)
        }
        try FileManager.default.removeItem(at: made.worktreeURL.appendingPathComponent("build-notes.env"))
        try FileManager.default.removeItem(at: made.worktreeURL.appendingPathComponent("local.env"))
        _ = try await GitWorktreeManager.removeWorktree(worktreePath: "keys", gitRoot: repository, ignoredAgreed: named)
        #expect(!FileManager.default.fileExists(atPath: made.worktreeURL.path), "removed once the person agreed to lose exactly those")
    }

    /// `rh worktree remove` run in the folder of another of Right Here's worktrees finds the repository by the nearest `.git`, that worktree's own: the worktree to remove is
    /// looked for under the main working copy, where Right Here makes them all.
    @Test func aWorktreeIsRemovedWhenAskedFromInsideAnotherWorktreeOfTheRepository() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let one = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "one")
        let two = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "two")
        let fromInsideOne = try #require(LiveSystemFacts().gitRoot(containing: one.worktreeURL))
        _ = try await GitWorktreeManager.removeWorktree(worktreePath: "two", gitRoot: fromInsideOne)
        #expect(!FileManager.default.fileExists(atPath: two.worktreeURL.path) && FileManager.default.fileExists(atPath: one.worktreeURL.path))
    }

    /// Probe: `.git/info/exclude` is a link (a repository that came as an archive with its `.git`). Writing through it would change another file.
    @Test func theExcludeLineIsNotWrittenThroughALink() async throws {
        let repository = try makeRepository()
        let victim = repository.deletingLastPathComponent().appendingPathComponent("victim-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: repository); try? FileManager.default.removeItem(at: victim) }
        try "the person's own file\n".write(to: victim, atomically: true, encoding: .utf8)
        let exclude = repository.appendingPathComponent(".git/info/exclude")
        try FileManager.default.removeItem(at: exclude)
        try FileManager.default.createSymbolicLink(atPath: exclude.path, withDestinationPath: victim.path)
        _ = try await GitWorktreeManager.prepareWorktree(gitRoot: repository, branch: "feature")
        #expect(try String(contentsOf: victim, encoding: .utf8) == "the person's own file\n", "the line was written into the file the link points to")
    }
}

@Suite("File safety: config files")
struct ConfigFileSafetyTests {
    /// `rh config init --force` (and the setup's forced config step) on a config kept as a link in a dotfiles repository: `copyItem` copies the link,
    /// not the file, so the "saved copy" is a second link to the live file, and the replacement is renamed over the link, which ends it (an edit and a pull
    /// write through the link: ConfigService.write, ConfigSync.pullLocked).
    @Test func aForcedReplacementOfALinkedConfigSavesARealCopyAndKeepsTheLink() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dotfiles = directory.appendingPathComponent("dotfiles")
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        let real = dotfiles.appendingPathComponent("config.toml")
        try "# my hand-made settings\n".write(to: real, atomically: true, encoding: .utf8)
        let paths = RHPaths(environment: ["RH_CONFIG_DIR": directory.appendingPathComponent("config").path], home: directory)
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: paths.configFile.path, withDestinationPath: real.path)

        let outcome = try ConfigStore.initialize(paths: paths, detected: DetectedEnvironment(), force: true, environment: [:])
        guard case .replaced(let backup) = outcome else { Issue.record("expected a replacement, got \(outcome)"); return }
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: backup.path)) == nil,
                "the saved copy \(backup.lastPathComponent) is a link to the dotfiles file, not a copy of what it held")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: paths.configFile.path)) != nil,
                "config.toml is no longer the dotfiles link: the dotfiles file stopped being the config")
        // Then the person tidies the dotfiles repository: the only "copy" of the hand-made settings goes with it.
        try FileManager.default.removeItem(at: real)
        #expect((try? String(contentsOf: backup, encoding: .utf8)) == "# my hand-made settings\n", "the saved copy no longer holds the old settings")
    }

    /// A dotfiles manager makes `config.local.toml` as a link before it has cloned its repository (LoadedConfig.hasConfig, Doctor.configCheck). The read
    /// takes the dangling link for no file, and the first edit of this Mac's file renames a regular file over the link.
    @Test func anEditOfThisMacsFileDoesNotReplaceTheLinkADotfilesManagerMadeForIt() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RHPaths(environment: [:], home: root)
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try "[general]\nterminal = \"ghostty\"\n".write(to: paths.configFile, atomically: true, encoding: .utf8)
        let notClonedYet = root.appendingPathComponent("dotfiles/right-here/config.local.toml")
        try FileManager.default.createSymbolicLink(atPath: paths.localConfigFile.path, withDestinationPath: notClonedYet.path)

        _ = try? ConfigService(paths: paths, environment: [:]).apply(.set("general.terminal", .string("ghostty")), target: .local, actor: .cli)

        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: paths.localConfigFile.path)) != nil,
                "the dotfiles manager's link was replaced by a regular file")
    }
}

extension ConfigFileSafetyTests {
    /// The refusal of an edit says where the link points. (A forced start over replaces such a link: it is the person's to ask for, and there is no text to save.)
    @Test func aLinkThatPointsNowhereIsRefusedNamingWhereItPoints() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RHPaths(environment: [:], home: root)
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        try "[general]\nterminal = \"ghostty\"\n".write(to: paths.configFile, atomically: true, encoding: .utf8)
        let notClonedYet = root.appendingPathComponent("dotfiles/right-here/config.local.toml")
        try FileManager.default.createSymbolicLink(atPath: paths.localConfigFile.path, withDestinationPath: notClonedYet.path)
        do {
            _ = try ConfigService(paths: paths, environment: [:]).apply(.set("general.terminal", .string("ghostty")), target: .local, actor: .cli)
            Issue.record("the edit was made")
        } catch {
            #expect(error.localizedDescription.contains("dotfiles/right-here/config.local.toml") && error.localizedDescription.contains("not there"), "\(error.localizedDescription)")
        }
    }
}

@Suite("File safety: the state file")
struct StateFileSafetyTests {
    /// `StateStore.load` gives an empty store for a `state.toml` it cannot parse (a hand edit with a missing comma, a sync tool's conflict text), cannot read,
    /// or finds past 128 KB, and `update` then writes what it changed over the file. Every successful `rh run` records its folder as a recent one
    /// (`Run.present`), so the next click in Finder replaces the person's pinned folders with an empty list.
    @Test func aStateFileThatDoesNotParseIsNotReplacedByTheNextRecentFolder() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RHPaths(environment: ["RH_CONFIG_DIR": root.path], home: root)
        let handEdited = "pins = [\n  \"/Users/me/code/app\",\n  \"/Users/me/notes\"\n  \"/Users/me/clients\",\n]\n"
        try handEdited.write(to: paths.stateFile, atomically: true, encoding: .utf8)

        // The click that records the folder is best effort (`try?` in Run); a pin or an unpin is refused, and says why.
        #expect(throws: StateFileNotRead.self) { try StateStore.update(paths: paths) { $0.recordRecent(root.path) } }
        #expect(throws: StateFileNotRead.self) { try StateStore.update(paths: paths) { $0.pin("/Users/me/other") } }

        let after = (try? String(contentsOf: paths.stateFile, encoding: .utf8)) ?? ""
        #expect(after == handEdited, "the pinned folders were written over: \(after.debugDescription)")
        #expect(StateStore.read(paths: paths) == .unreadable("it is not valid TOML"))
    }

    /// The file that is not there yet starts the state, and one that was too large or is a link that points nowhere is not written over either.
    @Test func anAbsentStateFileStartsTheStateAndOneThatCannotBeReadIsLeftAlone() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RHPaths(environment: ["RH_CONFIG_DIR": root.path], home: root)
        #expect(StateStore.read(paths: paths) == .absent)
        try StateStore.update(paths: paths) { $0.pin("/work/app") }
        #expect(StateStore.load(paths: paths).pins == ["/work/app"])
        try String(repeating: "# a long comment line\n", count: 8000).write(to: paths.stateFile, atomically: true, encoding: .utf8)
        #expect(throws: StateFileNotRead.self) { try StateStore.update(paths: paths) { $0.pin("/work/other") } }
        try FileManager.default.removeItem(at: paths.stateFile)
        try FileManager.default.createSymbolicLink(atPath: paths.stateFile.path, withDestinationPath: root.appendingPathComponent("gone/state.toml").path)
        #expect(throws: StateFileNotRead.self) { try StateStore.update(paths: paths) { $0.pin("/work/other") } }
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: paths.stateFile.path)) != nil, "the link was not replaced by a regular file")
    }
}

@Suite("File safety: the installer and New File")
struct InstallerAndNewFileSafetyTests {
    /// `installedServices()` claims every `Right Here - *.workflow` in ~/Library/Services by its name alone. A copy the person made of one of Right Here's to
    /// change it (Finder's Duplicate names it "... copy.workflow") is removed by the next `rh setup` or repair (the extra bundle makes the Quick Actions
    /// "not current") and by `rh uninstall`.
    @Test func aServiceThePersonMadeWhoseNameStartsLikeRightHeresIsNeverRemoved() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let own = installer.locations.services.appendingPathComponent("Right Here - Open in Terminal copy.workflow/Contents")
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        try "<plist>my own shell script</plist>".write(to: own.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
        try installer.installServices([ServiceSpec(title: "Open in Ghostty", actionID: "open.terminal@ghostty", command: "/x/rh run")])
        #expect(FileManager.default.fileExists(atPath: own.path), "rh setup removed a Service the person made")
        try installer.removeServices()
        #expect(FileManager.default.fileExists(atPath: own.path), "rh uninstall removed a Service the person made")
    }

    /// A close that fails (the last of the data is refused then, on a network volume or past a quota) is a failure of the action, and the file it made is removed.
    @Test func aFileWhoseCloseFailsIsRemovedAndTheActionFails() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("untitled.txt").path
        #expect(throws: ExecutionError.self) {
            try LiveExecutor.createFile(CreateFileStep(path: path, contents: "text"), close: { descriptor in _ = Darwin.close(descriptor); errno = EDQUOT; return -1 })
        }
        #expect(!FileManager.default.fileExists(atPath: path), "a file the action could not finish was left behind")
    }

    /// The record holds what is installed now: a name the config no longer asks for leaves it with its bundle, so a Service the person makes under that name later is theirs.
    @Test func aNameThatIsNoLongerInstalledLeavesTheRecord() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        let ghostty = ServiceSpec(title: "Open in Ghostty", actionID: "open.terminal@ghostty", command: "/x/rh run")
        let copy = ServiceSpec(title: "Copy Path", actionID: "copy-path.absolute", command: "/x/rh run")
        try installer.installServices([ghostty, copy])
        try installer.installServices([copy])
        // The person makes their own Service under the name Right Here no longer uses.
        let own = installer.locations.services.appendingPathComponent(ServiceWorkflow.bundleName(for: ghostty)).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        try "<plist>mine</plist>".write(to: own.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
        try installer.removeServices()
        #expect(FileManager.default.fileExists(atPath: own.path), "rh uninstall removed a Service the person made under a name Right Here had used once")
    }

    /// Probe: the names New File may meet in the folder: one in the other Unicode form, one in another case, a link that points nowhere.
    @Test func newFileNeverReplacesWhatIsThere() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let template = NewFileTemplate(id: "note", title: "Note", baseName: "Caf\u{E9}", fileExtension: "txt", contents: "new")
        // NFD on disk, NFC in the template.
        try "mine 1".write(to: folder.appendingPathComponent("Cafe\u{301}.txt"), atomically: false, encoding: .utf8)
        // Case.
        try "mine 2".write(to: folder.appendingPathComponent("CAF\u{C9} 2.txt"), atomically: false, encoding: .utf8)
        // Dangling link.
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("Caf\u{E9} 3.txt").path, withDestinationPath: folder.appendingPathComponent("elsewhere/target.txt").path)
        let name = NewFileNamer.firstFreeName(for: template, in: folder, facts: LiveSystemFacts())
        #expect(name == .free("Caf\u{E9} 4.txt"))
        // And the executor itself, handed each taken name, refuses.
        for taken in ["Caf\u{E9}.txt", "caf\u{E9} 2.txt", "Caf\u{E9} 3.txt"] {
            #expect(throws: ExecutionError.self) { try LiveExecutor.createFile(CreateFileStep(path: folder.appendingPathComponent(taken).path, contents: "new")) }
        }
        #expect(try String(contentsOf: folder.appendingPathComponent("Cafe\u{301}.txt"), encoding: .utf8) == "mine 1")
        #expect(try String(contentsOf: folder.appendingPathComponent("CAF\u{C9} 2.txt"), encoding: .utf8) == "mine 2")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("elsewhere/target.txt").path))
    }

    /// The names in a folder as the file system stores them (`readdir`), by scalar: Swift's `==` takes a name and its decomposed form for one.
    private static func storedNames(in folder: URL) -> [[UInt32]] {
        guard let directory = opendir(folder.path) else { return [] }
        defer { closedir(directory) }
        var names: [[UInt32]] = []
        while let entry = readdir(directory) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self) }
            if name != "." && name != ".." { names.append(name.unicodeScalars.map(\.value)) }
        }
        return names
    }

    /// New File built its path with `URL.appendingPathComponent(name).path`, which decomposes the name, and APFS keeps the form it is given: the Korean
    /// "무제.txt" was stored as conjoining jamo, the Spanish "sin título.txt" with an `i` and a combining accent, and a config's `base_name` the same.
    /// Finder shows them alike, but copied off the Mac (Windows, a web upload) the Korean name falls apart into letters. Text typed on a Mac is precomposed.
    @Test("a new file is stored under the precomposed name", arguments: [
        ("ko", nil, "\u{BB34}\u{C81C}.txt"), ("es", nil, "sin t\u{ED}tulo.txt"), ("en", "Cafe\u{301}", "Caf\u{E9}.txt"),
    ] as [(String, String?, String)])
    func aNewFileIsStoredUnderThePrecomposedName(language: String, baseName: String?, expected: String) throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var config = Config()
        if let baseName { config.newFile.templates = [NewFileTemplate(id: "txt", title: "Text", baseName: baseName, fileExtension: "txt")] }
        let plan = try Planner(config: config, facts: LiveSystemFacts(), localizer: Localizer(languages: [language])).plan(.newFile("txt"), context: HereContext(origin: .container, container: folder))
        let step = try #require(plan.steps.compactMap { step -> CreateFileStep? in if case .createFile(let file) = step { return file }; return nil }.first)
        try LiveExecutor.createFile(step)
        #expect(Self.storedNames(in: folder) == [expected.unicodeScalars.map(\.value)], "the template says \(expected.debugDescription)")
    }
}

/// After the app was replaced (an upgrade), macOS no longer knows the Finder extension. The app registers it again, and only that: the person's own choice to use it or
/// not is kept by pluginkit, and `-e use` would switch on an extension they had switched off.
@Suite("The Finder extension after an update")
struct ExtensionRestoreTests {
    @Test func theRestoreRegistersTheExtensionAndDoesNotSwitchItOn() async throws {
        let app = try makeTemporaryDirectory().appendingPathComponent("Right Here.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let appex = app.appendingPathComponent("Contents/PlugIns/FinderExtension.appex")
        try FileManager.default.createDirectory(at: appex, withIntermediateDirectories: true)
        let runner = FakeProcessRunner(results: [ProcessResult(status: 0), ProcessResult(status: 0, standardOutput: "")])
        let actions = SetupActions(facts: FakeSystemFacts(), paths: RHPaths(environment: [:], home: app.deletingLastPathComponent()), runner: runner, helperPath: "/x/rh",
                                   app: app, trialHome: nil)
        _ = await actions.restoreExtensionRegistration()
        let calls = runner.recorded.filter { $0.executable == "/usr/bin/pluginkit" }.map(\.arguments)
        #expect(calls.first == ["-a", appex.path], "\(calls)")
        #expect(!calls.contains { $0.contains("-e") }, "the person's choice was changed: \(calls)")
        // No app (the command line), nothing to register.
        #expect(await SetupActions(facts: FakeSystemFacts(), runner: FakeProcessRunner(), helperPath: "/x/rh", app: nil).restoreExtensionRegistration() == nil)
    }
}

/// Two New File runs that plan at the same moment (two clicks, a Quick Action and a Shortcut) both chose `untitled.md`. The exclusive create kept the first file
/// safe, but the second run failed with "untitled.md already exists." (an independent review, 2026-11-13). It plans again and takes the next name.
@Suite("New File when another run takes its name")
struct NewFileReplanTests {
    private let executor = LiveExecutor(runner: FakeProcessRunner(), pasteboard: RecordingPasteboard())

    private static func createFile(_ path: String) -> LaunchPlan {
        LaunchPlan(action: "new-file.txt", summary: "Create " + (path as NSString).lastPathComponent, steps: [.createFile(CreateFileStep(path: path, contents: "new"))])
    }

    @Test func aSecondNewFilePlannedAtTheSameTimeTakesTheNextName() async throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let planner = Planner(facts: LiveSystemFacts())
        let context = HereContext(origin: .container, container: folder)
        let first = try planner.plan(.newFile("md"), context: context)
        let second = try planner.plan(.newFile("md"), context: context)
        try await executor.execute(first)
        let (ran, _) = try await executor.execute(second, replanning: { try planner.plan(.newFile("md"), context: context) })
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == ["untitled.md", "untitled 2.md"])
        // What the run reports, and the Finder window it opens, are of the file it made.
        #expect(ran.summary == "Create untitled 2.md")
        #expect(ran.steps.last == .reveal([folder.path + "/untitled 2.md"]))
    }

    /// A plan made again that names the same file (the folder does not show the file that is in the way) fails at once, as it did, and is not tried again.
    @Test func aPlanMadeAgainForTheSameFileFailsAsItDid() async throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let taken = folder.path + "/untitled.txt"
        try "theirs".write(toFile: taken, atomically: false, encoding: .utf8)
        var plans = 0
        await #expect(throws: ExecutionError.fileExists(path: taken)) {
            try await executor.execute(Self.createFile(taken), replanning: { plans += 1; return Self.createFile(taken) })
        }
        #expect(plans == 1)
        #expect(try String(contentsOfFile: taken, encoding: .utf8) == "theirs")
    }

    /// Runs that keep taking each next name are not followed for ever.
    @Test func aNameThatIsTakenEveryTimeStopsAfterAFewPlans() async throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        for number in 1...10 { try "theirs".write(toFile: folder.path + "/n\(number).txt", atomically: false, encoding: .utf8) }
        var plans = 1
        await #expect(throws: ExecutionError.self) {
            try await executor.execute(Self.createFile(folder.path + "/n1.txt"), replanning: { plans += 1; return Self.createFile(folder.path + "/n\(plans).txt") })
        }
        #expect(plans == LiveExecutor.newFileAttempts)
    }

    /// Only a file that is the plan's first step is planned again: then nothing has run. A file met by a later step fails the run as it did.
    @Test func aFileInTheWayOfALaterStepIsNotPlannedAgain() async throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let taken = folder.path + "/untitled.txt"
        try "theirs".write(toFile: taken, atomically: false, encoding: .utf8)
        let plan = LaunchPlan(action: "x", summary: "x", steps: [.pause(milliseconds: 0), .createFile(CreateFileStep(path: taken))])
        var plans = 0
        await #expect(throws: ExecutionError.fileExists(path: taken)) {
            try await executor.execute(plan, replanning: { plans += 1; return Self.createFile(folder.path + "/other.txt") })
        }
        #expect(plans == 0)
    }
}
