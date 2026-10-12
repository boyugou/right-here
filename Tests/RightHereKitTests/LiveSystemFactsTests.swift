import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("LiveSystemFacts: existence")
struct LiveSystemFactsExistenceTests {
    private let facts = LiveSystemFacts()

    @Test func anExistingFileAndFolderAreFoundAndTellApart() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        #expect(facts.itemExists(file) && facts.itemExists(directory))
        #expect(facts.isDirectory(file) == false)
        #expect(facts.isDirectory(directory) == true)
    }

    @Test func nothingAtThePathIsMissing() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        #expect(!facts.itemExists(directory.appendingPathComponent("nope")))
        #expect(facts.isDirectory(directory.appendingPathComponent("nope")) == nil)
        // A file where a folder should be is "not there" as well (ENOTDIR).
        let file = directory.appendingPathComponent("f")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        #expect(!facts.itemExists(file.appendingPathComponent("inside")))
    }

    @Test func aLinkThatPointsNowhereExistsButIsNotAFolder() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let link = directory.appendingPathComponent("broken")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/nowhere/at/all")
        #expect(facts.itemExists(link))
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
        #expect(facts.itemExists(locked.appendingPathComponent("inside.txt")))
        #expect(facts.isDirectory(locked.appendingPathComponent("inside.txt")) == nil, "its type cannot be known")
        // And a path that really is not there, in the same folder, is still reported missing only if the system says so:
        // here it also cannot say, so it counts as present, which is the safe side for "do not reject a real path".
        #expect(facts.itemExists(locked.appendingPathComponent("who-knows")))
    }
}
