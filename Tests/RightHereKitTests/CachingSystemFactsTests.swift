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

    @Test func theTableOfFoldersStaysBoundedForAProcessThatNeverQuits() {
        let cached = CachingSystemFacts(base: FakeSystemFacts(directories: ["/Volumes/Work/proj"]))
        for number in 0..<(CachingSystemFacts.maxDirectories * 3) {
            _ = cached.isDirectory(URL(fileURLWithPath: "/Volumes/Work/folder-\(number)"))
        }
        #expect(cached.cachedDirectoryCountForTesting <= CachingSystemFacts.maxDirectories)
        #expect(cached.cachedDirectoryCountForTesting > 0)
        #expect(cached.isDirectory(URL(fileURLWithPath: "/Volumes/Work/proj")) == true, "an answer is still given after the table was emptied")
    }

    @Test func expiringMakesTheNextLookupsAskTheSystemAgain() {
        final class Counting: SystemFacts, @unchecked Sendable {
            let base = FakeSystemFacts(directories: ["/work"], applications: ["com.example.app": URL(fileURLWithPath: "/Applications/Example.app")], bundleVersions: ["com.example.app": "1"],
                                       displayNames: ["com.example.app": "Example"])
            var asked = 0
            var homeDirectory: URL { base.homeDirectory }
            var currentDirectory: URL { base.currentDirectory }
            var loginShell: String { base.loginShell }
            func isDirectory(_ url: URL) -> Bool? { asked += 1; return base.isDirectory(url) }
            func fileExists(_ url: URL) -> Bool { base.fileExists(url) }
            func itemState(_ url: URL) -> ItemState { base.itemState(url) }
            func gitRoot(containing url: URL) -> URL? { base.gitRoot(containing: url) }
            func applicationURL(bundleID: String) -> URL? { asked += 1; return base.applicationURL(bundleID: bundleID) }
            func displayName(bundleID: String) -> String? { asked += 1; return base.displayName(bundleID: bundleID) }
            func bundleVersion(bundleID: String) -> String? { asked += 1; return base.bundleVersion(bundleID: bundleID) }
            func isRunning(bundleID: String) -> Bool { base.isRunning(bundleID: bundleID) }
            func environment(_ key: String) -> String? { base.environment(key) }
            func onDiskPath(_ url: URL) -> String { base.onDiskPath(url) }
        }
        let base = Counting()
        let cached = CachingSystemFacts(base: base)
        func lookups() {
            _ = cached.applicationURL(bundleID: "com.example.app")
            _ = cached.displayName(bundleID: "com.example.app")
            _ = cached.bundleVersion(bundleID: "com.example.app")
            _ = cached.isDirectory(URL(fileURLWithPath: "/work"))
        }
        lookups()
        lookups()
        #expect(base.asked == 4, "the second round came from what was remembered")
        cached.expire()
        lookups()
        #expect(base.asked == 8, "after expiring all four are asked of the system again")
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
