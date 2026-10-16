import Foundation
import Synchronization
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("The state file under several writers")
struct StateStoreUpdateTests {
    @Test func pinsMadeAtTheSameTimeAreAllKept() throws {
        // Twenty `rh pin` started together kept twelve: each read the file, added its folder and wrote it back.
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let folders = (0..<8).map { "/work/project-\($0)" }
        let lost = Mutex<[String]>([])
        for round in 0..<60 {
            let paths = RHPaths(environment: [:], home: root.appendingPathComponent("round-\(round)"))
            DispatchQueue.concurrentPerform(iterations: folders.count) { index in
                do { try StateStore.update(paths: paths) { $0.pin(folders[index]) } } catch { lost.withLock { $0.append("round \(round): \(error)") } }
            }
            let kept = StateStore.load(paths: paths).pins
            if Set(kept) != Set(folders) { lost.withLock { $0.append("round \(round): \(kept.count) of \(folders.count)") } }
        }
        #expect(lost.withLock { $0 }.isEmpty, "\(lost.withLock { $0 }.count) rounds lost a pin; the first: \(lost.withLock { $0 }.first ?? "")")
    }

    @Test func pinsUnpinsAndRecentsAtTheSameTimeEachKeepTheirOwnChange() throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let paths = RHPaths(environment: [:], home: root)
        try StateStore.update(paths: paths) { $0.pin("/work/old") }
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            switch index % 3 {
            case 0: try? StateStore.update(paths: paths) { $0.pin("/work/pin-\(index)") }
            case 1: try? StateStore.update(paths: paths) { $0.recordRecent("/work/recent-\(index)") }
            default: try? StateStore.update(paths: paths) { $0.unpin("/work/old") }
            }
        }
        let state = StateStore.load(paths: paths)
        #expect(Set(state.pins) == ["/work/pin-0", "/work/pin-3", "/work/pin-6", "/work/pin-9"], "\(state.pins)")
        #expect(Set(state.recents) == ["/work/recent-1", "/work/recent-4", "/work/recent-7", "/work/recent-10"], "\(state.recents)")
    }

    @Test func anUpdateSaysWhatItsChangeSaysAndWritesOnlyWhatChanged() throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let paths = RHPaths(environment: [:], home: root)
        #expect(try StateStore.update(paths: paths) { $0.unpin("/work/none") } == false)
        #expect(!FileManager.default.fileExists(atPath: paths.stateFile.path), "nothing changed, so nothing was written")
        #expect(try StateStore.update(paths: paths) { $0.pin("/work/a") } == true)
        let written = try FileManager.default.attributesOfItem(atPath: paths.stateFile.path)
        #expect((written[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try StateStore.update(paths: paths) { $0.pin("/work/a") } == false)
        #expect(try FileManager.default.attributesOfItem(atPath: paths.stateFile.path)[.modificationDate] as? Date == written[.modificationDate] as? Date, "an unchanged state was written again")
        // A change that throws writes nothing.
        struct Refused: Error {}
        #expect(throws: Refused.self) { try StateStore.update(paths: paths) { $0.pin("/work/b"); throw Refused() } }
        #expect(StateStore.load(paths: paths).pins == ["/work/a"])
    }

    @Test func aStateThatAnotherProgramIsChangingIsNotChangedByAnUpdateThatGivesUp() throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let paths = RHPaths(environment: [:], home: root)
        let holder = try FileLock.acquireNow(paths.stateLockFile, timeout: .milliseconds(50))
        #expect(throws: FileLock.Busy.self) { try StateStore.update(paths: paths, timeout: .milliseconds(100)) { $0.pin("/work/a") } }
        #expect(StateStore.load(paths: paths).pins.isEmpty)
        // A setup, which takes seconds, is not what the state waits for.
        let setup = try FileLock.acquireNow(paths.setupLockFile, timeout: .milliseconds(50))
        holder.release()
        #expect(try StateStore.update(paths: paths, timeout: .milliseconds(100)) { $0.pin("/work/a") } == true)
        setup.release()
    }
}
