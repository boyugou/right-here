import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("ProbeMarker")
struct ProbeMarkerTests {
    private func paths(in directory: URL) -> RHPaths {
        RHPaths(environment: ["RH_CONFIG_DIR": directory.path], home: directory)
    }

    private func age(_ marker: URL, by seconds: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-seconds)], ofItemAtPath: marker.path)
    }

    @Test func anInterruptedProbeWithdrawsItsRequestBeforeTheExtensionIsSwitchedBackOn() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        #expect(ProbeMarker.write("launch:tab", in: target))
        var pendingWhenReenabled: String? = "not called"
        ProbeMarker.cleanUpAfterInterrupt(in: target) { pendingWhenReenabled = ProbeMarker.pending(in: target) }
        #expect(pendingWhenReenabled == nil)
    }

    @Test func aFreshRequestIsPendingAndCarriesItsText() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        #expect(ProbeMarker.pending(in: target) == nil)
        #expect(ProbeMarker.write("launch:tab", in: target))
        #expect(ProbeMarker.pending(in: target) == "launch:tab")
    }

    @Test func aRequestThatWasLeftBehindIsNotHonoured() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        ProbeMarker.write("launch", in: target)
        try age(ProbeMarker.url(in: target), by: ProbeMarker.lifetime + 30)
        #expect(ProbeMarker.pending(in: target) == nil, "an interrupted `rh doctor` must not open a terminal at the next Finder start")
    }

    @Test func aDateFarInTheFutureIsAsStaleAsOneInThePast() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        ProbeMarker.write("launch", in: target)
        try age(ProbeMarker.url(in: target), by: -(ProbeMarker.lifetime + 30))
        #expect(ProbeMarker.pending(in: target) == nil)
    }

    @Test func claimingTakesAFreshRequestExactlyOnce() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        ProbeMarker.write("launch", in: target)
        #expect(ProbeMarker.claim(in: target))
        #expect(!ProbeMarker.claim(in: target), "a second extension process must not run the probe again")
        #expect(!FileManager.default.fileExists(atPath: ProbeMarker.url(in: target).path))
    }

    @Test func claimingAStaleRequestRemovesItAndRunsNothing() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        ProbeMarker.write("launch", in: target)
        try age(ProbeMarker.url(in: target), by: 3_600)
        #expect(!ProbeMarker.claim(in: target))
        #expect(!FileManager.default.fileExists(atPath: ProbeMarker.url(in: target).path), "a stale file must not linger to fool a later run")
    }

    @Test func manyProcessesClaimingAtOnceGiveExactlyOneWinner() async throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        for _ in 0..<20 {
            // A request that was not written has no winner: say that, not "no winner" (a test process that runs out of files cannot write it).
            try #require(ProbeMarker.write("launch", in: target), "the request could not be written: \(String(cString: strerror(errno)))")
            let winners = await withTaskGroup(of: Bool.self) { group in
                for _ in 0..<8 { group.addTask { ProbeMarker.claim(in: target) } }
                return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
            }
            #expect(winners == 1)
        }
    }

    @Test func aLinkInPlaceOfTheMarkerIsRemovedNotFollowed() throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = paths(in: directory)
        let precious = directory.appendingPathComponent("precious")
        try "keep me".write(to: precious, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: ProbeMarker.url(in: target), withDestinationURL: precious)
        _ = ProbeMarker.claim(in: target)
        #expect(try String(contentsOf: precious, encoding: .utf8) == "keep me")
        #expect(!FileManager.default.fileExists(atPath: ProbeMarker.url(in: target).path))
    }
}

@Suite("ActionTags")
struct ActionTagsTests {
    @Test func theSameActionInTheSameMenuKeepsItsTagWhateverElseIsBuilt() {
        var tags = ActionTags()
        let first = tags.tag(for: "open.terminal", kind: .items)
        _ = tags.tag(for: "agent.claude", kind: .items)
        // Other menus are built (the toolbar, the window background, the sidebar) before the click on the first.
        for kind in FinderMenuKind.allCases { for id in ["copy-path.absolute", "reveal", "new-file.md", "open.terminal"] { _ = tags.tag(for: id, kind: kind) } }
        #expect(tags.tag(for: "open.terminal", kind: .items) == first)
        #expect(tags.resolve(first)?.actionID == "open.terminal")
        #expect(tags.resolve(first)?.kind == .items)
    }

    @Test func aTagSaysWhichMenuListedIt() {
        var tags = ActionTags()
        let items = tags.tag(for: "open.terminal", kind: .items)
        let toolbar = tags.tag(for: "open.terminal", kind: .toolbar)
        #expect(items != toolbar)
        #expect(tags.resolve(items)?.kind == .items)
        #expect(tags.resolve(toolbar)?.kind == .toolbar)
        #expect(tags.resolve(items)?.actionID == tags.resolve(toolbar)?.actionID)
    }

    @Test func everyActionAndKindGetsItsOwnTag() {
        var tags = ActionTags()
        var seen = Set<Int>()
        for kind in FinderMenuKind.allCases {
            for number in 0..<200 {
                let tag = tags.tag(for: "action.\(number)", kind: kind)
                #expect(seen.insert(tag).inserted, "tag \(tag) was handed out twice")
                #expect(tags.resolve(tag)?.actionID == "action.\(number)")
            }
        }
    }

    @Test("an empty table resolves nothing", arguments: [-1, 0, 5, 1 << 20, (1 << 20) + 3, 99 << 20, Int.max, Int.min])
    func anEmptyTableResolvesNothing(tag: Int) {
        #expect(ActionTags().resolve(tag) == nil)
    }

    @Test("a number that was never handed out, or a kind that does not exist, resolves to nothing",
          arguments: [-1, 5, (2 << 20) | 7, 99 << 20, Int.max, Int.min])
    func numbersAndKindsThatWereNeverHandedOut(tag: Int) {
        var tags = ActionTags()
        _ = tags.tag(for: "only", kind: .items)
        #expect(tags.resolve(tag) == nil)
        #expect(tags.resolve(0)?.actionID == "only")
    }

    @Test func aRemovedActionStillResolvesSoAnOldMenuNeverRetargets() {
        // The table only grows: an id that left the menu keeps its number, and no other id takes it over.
        var tags = ActionTags()
        let old = tags.tag(for: "agent.removed", kind: .items)
        for number in 0..<50 { _ = tags.tag(for: "later.\(number)", kind: .items) }
        #expect(tags.resolve(old)?.actionID == "agent.removed")
    }

    @Test func aSignalWithdrawsTheRequestThenReenablesTheExtensionThenFinishes() async throws {
        let directory = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = RHPaths(environment: ["RH_CONFIG_DIR": directory.path], home: directory)
        #expect(ProbeMarker.write("launch:tab", in: target))
        let order = Recorder()
        // SIGUSR2 stands in for Ctrl-C: the wiring is the same and the test runner is not interrupted.
        let guardian = InterruptGuard(signals: [SIGUSR2], paths: target,
                                      reenableExtension: { order.add("reenable:" + (ProbeMarker.pending(in: target) ?? "no request")) },
                                      finish: { order.add("finish") })
        defer { guardian.cancel() }
        kill(getpid(), SIGUSR2)
        for _ in 0..<100 where order.events.count < 2 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(order.events == ["reenable:no request", "finish"], "\(order.events)")
    }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ event: String) { lock.lock(); items.append(event); lock.unlock() }
    var events: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

