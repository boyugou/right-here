import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("CachingSystemFacts: the Finder extension's view of the machine")
struct CachingSystemFactsTests {
    @Test func copyPathFromTheExtensionKeepsTheOnDiskSpelling() throws {
        // The extension builds `PathRenderer(facts: CachingSystemFacts())`. A wrapper that forgot to forward
        // `onDiskPath` would hand the renderer `URL.path`, which decomposes an accented name (ADR 0008).
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let name = "caf\u{e9} Dir"
        #expect(mkdir(directory.path + "/" + name, 0o755) == 0)
        let url = directory.appendingPathComponent(name)
        // Typed in the decomposed spelling a URL round trip produces: only the file system knows the stored one.
        let stored = CachingSystemFacts().onDiskPath(directory.appendingPathComponent("cafe\u{301} Dir"))
        #expect(stored.unicodeScalars.contains("\u{e9}") && !stored.unicodeScalars.contains("\u{301}"), "the wrapper changed the on-disk spelling: \(stored)")
        let copied = PathRenderer(facts: CachingSystemFacts()).render(url, style: .absolute)
        #expect(copied.unicodeScalars.contains("\u{e9}") && !copied.unicodeScalars.contains("\u{301}"), "Copy Path from the extension decomposed the name: \(copied)")
    }

    @Test func everyFactComesFromTheWrappedFacts() {
        let folder = URL(fileURLWithPath: "/Volumes/Work/proj")
        let facts = FakeSystemFacts(
            homeDirectory: URL(fileURLWithPath: "/Volumes/Work/home"), currentDirectory: URL(fileURLWithPath: "/Volumes/Work/cwd"), loginShell: "/bin/fish",
            directories: ["/Volumes/Work/proj"], files: ["/Volumes/Work/proj/a.txt"], danglingLinks: ["/Volumes/Work/proj/dead"],
            unreadablePaths: ["/Volumes/Work/proj/locked"], gitRoots: ["/Volumes/Work/proj"],
            applications: ["com.example.app": URL(fileURLWithPath: "/Applications/Example.app")], bundleVersions: ["com.example.app": "9.1"],
            runningApplications: ["com.example.app"], variables: ["RH_PROBE": "yes"],
            diskPaths: ["/Volumes/Work/proj/a.txt": "/Volumes/Work/proj/A.TXT"], displayNames: ["com.example.app": "Beispiel"])
        let cached = CachingSystemFacts(base: facts)
        #expect(cached.homeDirectory == facts.homeDirectory)
        #expect(cached.currentDirectory == facts.currentDirectory)
        #expect(cached.loginShell == "/bin/fish")
        #expect(cached.isDirectory(folder) == true)
        #expect(cached.isDirectory(folder.appendingPathComponent("a.txt")) == false)
        #expect(cached.fileExists(folder.appendingPathComponent("a.txt")))
        #expect(cached.itemState(folder.appendingPathComponent("dead")) == .present)
        #expect(cached.itemState(folder.appendingPathComponent("locked")) == .unreadable)
        #expect(cached.itemState(folder.appendingPathComponent("nothing")) == .missing)
        #expect(cached.gitRoot(containing: folder.appendingPathComponent("a.txt")) == folder)
        #expect(cached.applicationURL(bundleID: "com.example.app") == URL(fileURLWithPath: "/Applications/Example.app"))
        #expect(cached.displayName(bundleID: "com.example.app") == "Beispiel")
        #expect(cached.bundleVersion(bundleID: "com.example.app") == "9.1")
        #expect(cached.isRunning(bundleID: "com.example.app"))
        #expect(cached.environment("RH_PROBE") == "yes")
        #expect(cached.onDiskPath(folder.appendingPathComponent("a.txt")) == "/Volumes/Work/proj/A.TXT")
    }
}
