import Foundation
import Synchronization
import Testing
@testable import RightHereKit

@Suite("FileLock: one at a time")
struct FileLockTests {
    private func lockFile(_ folder: URL) -> URL { folder.appendingPathComponent("config/.test.lock") }

    @Test func aSecondLockOnTheSameFileWaitsAndGivesUpWhileTheFirstIsHeldAndTakesItAfter() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        // The folder of the lock is made too: a setup on a Mac that has no config folder yet takes its turn all the same.
        let first = try FileLock.acquireNow(lockFile(folder), timeout: .milliseconds(50))
        #expect(first.isHeld)
        // Two locks in one process contend as two processes do (measured: `flock` belongs to the open file description).
        #expect(throws: FileLock.Busy.self) { _ = try FileLock.acquireNow(lockFile(folder), timeout: .milliseconds(100)) }
        first.release()
        let second = try FileLock.acquireNow(lockFile(folder), timeout: .milliseconds(50))
        #expect(second.isHeld)
        // The file stays: a lock file that is removed and made again would be two locks.
        second.release()
        #expect(FileManager.default.fileExists(atPath: lockFile(folder).path))
    }

    @Test func aLockThatIsNotReleasedIsLetGoOfWhenItsObjectIsGone() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        do { _ = try FileLock.acquireNow(lockFile(folder), timeout: .milliseconds(50)) }
        #expect(try FileLock.acquireNow(lockFile(folder), timeout: .milliseconds(50)).isHeld)
    }

    @Test func theOneThatWaitsGetsItsTurnWhenTheHolderLetsGo() async throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let holder = try await FileLock.acquire(lockFile(folder), timeout: .seconds(1))
        let started = ContinuousClock.now
        let waiting = Task { try await FileLock.acquire(lockFile(folder), timeout: .seconds(20), poll: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(300))
        holder.release()
        let taken = try await waiting.value
        #expect(taken.isHeld && ContinuousClock.now - started >= .milliseconds(250), "it did not wait for the holder")
        await #expect(throws: FileLock.Busy.self) { _ = try await FileLock.acquire(lockFile(folder), timeout: .milliseconds(150), poll: .milliseconds(20)) }
    }

    @Test func aWaitThatIsCancelledEndsAndLetsGoOfWhatItHad() async throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let holder = try await FileLock.acquire(lockFile(folder), timeout: .seconds(1))
        let waiting = Task { try await FileLock.acquire(lockFile(folder), timeout: .seconds(60), poll: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(100))
        waiting.cancel()
        await #expect(throws: CancellationError.self) { _ = try await waiting.value }
        holder.release()
        #expect(try FileLock.acquireNow(lockFile(folder), timeout: .milliseconds(50)).isHeld)
    }

    @Test func aLockThatCannotBeMadeIsNotHeldAndIsNoError() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        // The folder is a file.
        let file = folder.appendingPathComponent("not a folder")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        #expect(try FileLock.acquireNow(file.appendingPathComponent(".lock"), timeout: .milliseconds(50)).isHeld == false)
        // The name is a link, which is not followed: what it points at is not made, though its folder is there, and a file it points at is
        // not locked or changed.
        let target = folder.appendingPathComponent("target")
        let link = folder.appendingPathComponent("linked.lock")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)
        #expect(try FileLock.acquireNow(link, timeout: .milliseconds(50)).isHeld == false)
        #expect(!FileManager.default.fileExists(atPath: target.path), "a file was made through the link")
        try "mine".write(to: target, atomically: true, encoding: .utf8)
        #expect(try FileLock.acquireNow(link, timeout: .milliseconds(50)).isHeld == false)
        #expect(try String(contentsOf: target, encoding: .utf8) == "mine")
        #expect(try FileLock.acquireNow(target, timeout: .milliseconds(50)).isHeld, "the file itself is no less a lock file")
        // The name is a folder.
        let directory = folder.appendingPathComponent("a.lock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(try FileLock.acquireNow(directory, timeout: .milliseconds(50)).isHeld == false)
    }

    @Test func manyThreadsTakeTurnsAndNeverTwoAreInsideAtOnce() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let inside = Mutex(0)
        let overlaps = Mutex(0)
        let counted = Mutex(0)
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            for _ in 0..<15 {
                guard let lock = try? FileLock.acquireNow(lockFile(folder), timeout: .seconds(30), poll: .milliseconds(1)), lock.isHeld else { continue }
                if inside.withLock({ $0 += 1; return $0 }) > 1 { overlaps.withLock { $0 += 1 } }
                usleep(300)
                inside.withLock { $0 -= 1 }
                counted.withLock { $0 += 1 }
                lock.release()
            }
        }
        #expect(overlaps.withLock { $0 } == 0, "two threads held the lock at once")
        #expect(counted.withLock { $0 } == 8 * 15)
    }

    /// The system lets go of a lock when the process that holds it ends, even one that is killed: there is no stale lock file to clean up
    /// (measured on APFS, ADR 0021). A holder in another process: perl, which ships with macOS, takes the same `flock`.
    @Test func aLockHeldByAnotherProcessIsLetGoOfWhenThatProcessIsKilled() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = lockFile(folder)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let holder = Process()
        holder.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        holder.arguments = ["-MFcntl=:flock", "-e", "open(F, '>>', $ARGV[0]) or die; flock(F, LOCK_EX) or die; $| = 1; print \"held\\n\"; sleep 60", file.path]
        let out = Pipe()
        holder.standardOutput = out
        try holder.run()
        defer { if holder.isRunning { holder.terminate() } }
        #expect(String(decoding: out.fileHandleForReading.availableData, as: UTF8.self).hasPrefix("held"), "the holder did not take the lock")
        #expect(throws: FileLock.Busy.self) { _ = try FileLock.acquireNow(file, timeout: .milliseconds(100)) }
        kill(holder.processIdentifier, SIGKILL)
        holder.waitUntilExit()
        #expect(try FileLock.acquireNow(file, timeout: .seconds(5)).isHeld, "the lock of a process that was killed is still held")
    }
}
