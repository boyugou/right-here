import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("Saved-folder read failures and storage limits")
struct StateStoreReadTests {
    @Test func aMissingFileIsAnEmptyStoreAndTheFirstPinCreatesIt() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = RHPaths(environment: [:], home: home)
        #expect(try StateStore.load(paths: paths) == StateStore())
        #expect(!FileManager.default.fileExists(atPath: paths.configDirectory.path))
        try StateStore.update(paths: paths) { $0.pin("/work/first") }
        #expect(try StateStore.load(paths: paths).pins == ["/work/first"])
    }

    @Test func aDanglingLinkIsNotMistakenForAnAbsentFile() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = RHPaths(environment: [:], home: home)
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        let target = home.appendingPathComponent("unavailable-state.toml").path
        try FileManager.default.createSymbolicLink(atPath: paths.stateFile.path, withDestinationPath: target)
        #expect(throws: StateStoreError.self) { try StateStore.load(paths: paths) }
        #expect(throws: StateStoreError.self) { try StateStore.update(paths: paths) { $0.pin("/work/new") } }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: paths.stateFile.path) == target)
    }

    @Test func aDirectoryAtTheStatePathIsAReadFailure() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = RHPaths(environment: [:], home: home)
        try FileManager.default.createDirectory(at: paths.stateFile, withIntermediateDirectories: true)
        #expect(throws: StateStoreError.self) { try StateStore.load(paths: paths) }
    }

    @Test func aValidSymbolicLinkStillLoadsItsSavedFolders() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = RHPaths(environment: [:], home: home)
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        let target = home.appendingPathComponent("linked-state.toml")
        try StateStore(pins: ["/work/linked"]).render().write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: paths.stateFile, withDestinationURL: target)
        #expect(try StateStore.load(paths: paths).pins == ["/work/linked"])
    }

    @Test func aFileInPlaceOfAParentDirectoryIsNotAnEmptyStore() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = RHPaths(environment: [:], home: home)
        try Data().write(to: home.appendingPathComponent(".config"))
        #expect(throws: StateStoreError.self) { try StateStore.load(paths: paths) }
    }

    @Test func anUnreadableFileCannotBeReplacedEvenWhenItsDirectoryIsWritable() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = RHPaths(environment: [:], home: home)
        try StateStore(pins: ["/work/important"]).save(paths: paths)
        let original = try Data(contentsOf: paths.stateFile)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: paths.stateFile.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.stateFile.path) }
        var changed = false
        #expect(throws: StateStoreError.self) { try StateStore.update(paths: paths) { $0.pin("/work/new"); changed = true } }
        #expect(!changed)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.stateFile.path)
        #expect(try Data(contentsOf: paths.stateFile) == original)
    }

    @Test func aFileAtTheByteLimitCanBeWrittenAndReadAndAnOverflowKeepsIt() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = RHPaths(environment: [:], home: home)
        var state = StateStore(pins: (0..<643).map { "/work/\($0)" + String(repeating: "a", count: 188) })
        let padding = StateStore.maximumFileBytes - StateStore(pins: state.pins + [""]).render().utf8.count
        // Keep every fixture path within filesystem limits while bringing the whole file to its byte limit.
        try #require(padding > 0 && padding < 1024)
        state.pins.append(String(repeating: "/a", count: padding / 2) + (padding.isMultiple(of: 2) ? "" : "x"))
        #expect(state.render().utf8.count == StateStore.maximumFileBytes)
        try state.save(paths: paths)
        #expect(try StateStore.load(paths: paths) == state)
        let original = try Data(contentsOf: paths.stateFile)
        #expect(throws: StateStoreError.self) { try StateStore.update(paths: paths) { $0.pin("/work/overflow") } }
        #expect(try Data(contentsOf: paths.stateFile) == original)
    }

    @Test func theWriteLimitCountsEncodedBytesRatherThanCharacters() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = RHPaths(environment: [:], home: home)
        let state = StateStore(pins: ["/" + String(repeating: "文", count: StateStore.maximumFileBytes / 2)])
        #expect(state.render().count < StateStore.maximumFileBytes)
        #expect(throws: StateStoreError.self) { try state.save(paths: paths) }
        #expect(!FileManager.default.fileExists(atPath: paths.stateFile.path))
    }

    @Test func errorMessagesAbbreviateTheHomeAndEscapeUntrustedText() {
        let error = StateStoreError.unreadable(file: "/Users/tester/state\n.toml", detail: "bad\u{1b}[31mfield")
        let message = error.message(home: "/Users/tester")
        #expect(message == .appSavedFoldersReadFailed("~/state\\n.toml", "bad\\u001b[31mfield"))
        #expect(Localizer(languages: ["zh-Hans"]).render(message).contains("文件未被更改"))
    }
}
