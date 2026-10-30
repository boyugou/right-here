import Foundation
import Testing
@testable import RightHereKit

@Suite("BoundedRead")
struct BoundedReadTests {
    private func inTemporaryFolder(_ body: (URL) throws -> Void) throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    @Test func aFileWithinTheLimitIsRead() throws {
        try inTemporaryFolder { folder in
            let file = folder.appendingPathComponent("a")
            try Data("hello".utf8).write(to: file)
            #expect(BoundedRead.read(file, limit: 5) == .data(Data("hello".utf8)))
            #expect(BoundedRead.read(file, limit: 4) == .tooLarge(bytes: 5))
            let empty = folder.appendingPathComponent("empty")
            try Data().write(to: empty)
            #expect(BoundedRead.read(empty) == .data(Data()))
        }
    }

    @Test func aMissingFileOrALinkToNothingIsAbsent() throws {
        try inTemporaryFolder { folder in
            #expect(BoundedRead.read(folder.appendingPathComponent("nothing")) == .absent)
            let link = folder.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder.appendingPathComponent("nothing"))
            #expect(BoundedRead.read(link) == .absent)
            #expect(BoundedRead.read(folder.appendingPathComponent("file/inside")) == .absent)
        }
    }

    @Test func aHugeFileIsNeverRead() throws {
        try inTemporaryFolder { folder in
            // A sparse file of 4 GiB: reading it would allocate that much, or take long enough for the test to fail.
            let file = folder.appendingPathComponent("huge")
            let descriptor = open(file.path, O_WRONLY | O_CREAT, 0o644)
            try #require(descriptor >= 0)
            try #require(ftruncate(descriptor, 4 * 1024 * 1024 * 1024) == 0)
            close(descriptor)
            #expect(BoundedRead.read(file) == .tooLarge(bytes: 4 * 1024 * 1024 * 1024))
            // Through a link too.
            let link = folder.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
            #expect(BoundedRead.read(link) == .tooLarge(bytes: 4 * 1024 * 1024 * 1024))
        }
    }

    @Test func aFolderAndAPipeAreUnreadableNotHanging() throws {
        try inTemporaryFolder { folder in
            #expect(BoundedRead.read(folder) == .unreadable(reason: "it is a folder, not a file"))
            let pipe = folder.appendingPathComponent("pipe")
            try #require(mkfifo(pipe.path, 0o644) == 0)
            #expect(BoundedRead.read(pipe) == .unreadable(reason: "it is not a regular file"))
        }
    }

    @Test func aFileWithoutPermissionSaysWhy() throws {
        try inTemporaryFolder { folder in
            let file = folder.appendingPathComponent("locked")
            try Data("x".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
            try #require(!FileManager.default.isReadableFile(atPath: file.path), "running as a user that ignores permissions")
            #expect(BoundedRead.read(file) == .unreadable(reason: "Permission denied"))
        }
    }
}
