import Foundation
import Testing
@testable import RightHereKit

@Suite("RefreshGate")
struct RefreshGateTests {
    @Test func theFirstRequestStartsARefresh() {
        var gate = RefreshGate()
        let start = gate.request()
        #expect(start)
        #expect(gate.isRunning)
        #expect(!gate.hasPendingRequest)
    }

    @Test func aRequestDuringARefreshWaitsForItsTurn() {
        var gate = RefreshGate()
        _ = gate.request()
        let start = gate.request()
        #expect(!start)
        #expect(gate.hasPendingRequest)
    }

    @Test func severalRequestsDuringARefreshAskForOneMoreRun() {
        var gate = RefreshGate()
        _ = gate.request()
        for _ in 0..<10 { _ = gate.request() }
        let again = gate.finish()
        let andAgain = gate.finish()
        #expect(again)
        #expect(!andAgain)
        #expect(!gate.isRunning)
    }

    @Test func aRefreshThatNobodyAskedAgainEndsTheRun() {
        var gate = RefreshGate()
        _ = gate.request()
        let again = gate.finish()
        #expect(!again)
        #expect(!gate.isRunning)
        let start = gate.request()
        #expect(start)
    }

    @Test func theRunThatFollowsKeepsTheGateBusyAndTakesNewRequestsToo() {
        var gate = RefreshGate()
        _ = gate.request()
        _ = gate.request()
        let second = gate.finish()
        #expect(second)
        #expect(gate.isRunning)
        _ = gate.request()
        let third = gate.finish()
        let fourth = gate.finish()
        #expect(third)
        #expect(!fourth)
    }
}

/// Holds each load until the test lets it end, and keeps a diary of what happened in what order. A load of a number the
/// test has not released yet waits; `releaseAll` lets every load end, so a test that fails cannot leave one hanging.
private actor Loads {
    private(set) var started = 0
    private(set) var returned = 0
    private(set) var diary: [String] = []
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<Int> = []
    private var everythingIsReleased = false

    func note(_ event: String) { diary.append(event) }

    /// A caller of `refresh()` has come back.
    func refreshReturned() { returned += 1 }

    /// A load begins. It ends, with its own number, once `release` has been called for it.
    func load() async -> Int {
        started += 1
        let number = started
        diary.append("load \(number) starts")
        if !everythingIsReleased, !released.contains(number) {
            await withCheckedContinuation { waiting[number] = $0 }
        }
        diary.append("load \(number) ends")
        return number
    }

    func release(_ number: Int) {
        released.insert(number)
        waiting.removeValue(forKey: number)?.resume()
    }

    func releaseAll() {
        everythingIsReleased = true
        for continuation in waiting.values { continuation.resume() }
        waiting = [:]
    }
}

/// Waits, a few milliseconds at a time, until `condition` holds; records an issue after about three seconds.
@MainActor
private func waitFor(_ what: String, sourceLocation: SourceLocation = #_sourceLocation, _ condition: @MainActor () async -> Bool) async {
    for _ in 0..<600 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("timed out waiting for \(what)", sourceLocation: sourceLocation)
}

@MainActor
@Suite("RefreshLoop")
struct RefreshLoopTests {
    /// Asks for a refresh the way the window does, from a task of its own, and counts the asker's return.
    private func ask(_ loop: RefreshLoop<Int>, _ loads: Loads) -> Task<Void, Never> {
        Task {
            await loop.refresh()
            await loads.refreshReturned()
        }
    }

    @Test func aRefreshReadsOnceAndHandsTheResultOver() async {
        let loads = Loads()
        var applied: [Int] = []
        var busy: [Bool] = []
        let loop = RefreshLoop<Int>(load: { await loads.load() }, apply: { applied.append($0) }, busyChanged: { busy.append($0) })
        await loads.release(1)
        await loop.refresh()
        #expect(applied == [1])
        #expect(busy == [true, false])
        #expect(!loop.isRunning)
    }

    @Test func tenRequestsDuringARefreshAreAnsweredByOneMoreRefreshAndNotTenMore() async {
        // A double click on the refresh button, or a poll that fires while a repair ends, used to start one refresh each; every
        // one of them asked the login shell for the agents' commands, and whichever ended last wrote its answer last.
        let loads = Loads()
        var applied: [Int] = []
        var busy: [Bool] = []
        let loop = RefreshLoop<Int>(load: { await loads.load() }, apply: { applied.append($0) }, busyChanged: { busy.append($0) })

        _ = ask(loop, loads)
        await waitFor("the first load to start") { await loads.started == 1 }
        for _ in 0..<10 { _ = ask(loop, loads) }
        await waitFor("the requests to be noted") { loop.hasPendingRequest }

        await loads.release(1)
        await waitFor("the second load to start") { await loads.started >= 2 }
        let startedSoFar = await loads.started
        await loads.releaseAll()
        await waitFor("every caller to be answered") { await loads.returned == 11 }

        #expect(startedSoFar == 2)
        #expect(await loads.started == 2)
        #expect(applied == [1, 2])
        #expect(busy == [true, false])
        #expect(!loop.isRunning)
    }

    @Test func theRefreshThatFollowsStartsAfterTheRequestItAnswers() async {
        let loads = Loads()
        let loop = RefreshLoop<Int>(load: { await loads.load() }, apply: { _ in })
        _ = ask(loop, loads)
        await waitFor("the first load to start") { await loads.started == 1 }
        await loads.note("requested")
        _ = ask(loop, loads)
        await waitFor("the request to be noted") { loop.hasPendingRequest }
        await loads.release(1)
        await waitFor("the second load to start") { await loads.started >= 2 }
        await loads.releaseAll()
        await waitFor("both callers to be answered") { await loads.returned == 2 }
        #expect(await loads.diary == ["load 1 starts", "requested", "load 1 ends", "load 2 starts", "load 2 ends"])
    }

    @Test func everyCallerWaitsUntilWhatItAskedForHasBeenApplied() async {
        let loads = Loads()
        var applied: [Int] = []
        var appliedWhenTheLateCallerCameBack: [Int]?
        let loop = RefreshLoop<Int>(load: { await loads.load() }, apply: { applied.append($0) })
        _ = ask(loop, loads)
        await waitFor("the first load to start") { await loads.started == 1 }
        let late = Task {
            await loop.refresh()
            appliedWhenTheLateCallerCameBack = applied
            await loads.refreshReturned()
        }
        await waitFor("the request to be noted") { loop.hasPendingRequest }
        await loads.release(1)
        await waitFor("the second load to start") { await loads.started >= 2 }
        await loads.releaseAll()
        await waitFor("both callers to be answered") { await loads.returned == 2 }
        _ = late
        // The late caller asked during the first load, so what it asked for is the second one: it comes back after it.
        #expect(appliedWhenTheLateCallerCameBack == [1, 2])
        #expect(!loop.isRunning)
    }

    @Test func aRefreshAfterTheLastOneEndedStartsAgain() async {
        let loads = Loads()
        var applied: [Int] = []
        var busy: [Bool] = []
        let loop = RefreshLoop<Int>(load: { await loads.load() }, apply: { applied.append($0) }, busyChanged: { busy.append($0) })
        await loads.releaseAll()
        await loop.refresh()
        await loop.refresh()
        #expect(applied == [1, 2])
        #expect(busy == [true, false, true, false])
    }

    @Test func theLoadRunsOffTheMainThread() async {
        // The doctor asks the login shell for the agents' commands and the config is read from disk: neither may hold the
        // window's thread.
        let seen = Seen()
        let loop = RefreshLoop<Int>(load: { seen.record(pthread_main_np() != 0); return 0 }, apply: { _ in })
        await loop.refresh()
        #expect(seen.values == [false])
    }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Bool] = []
    func record(_ value: Bool) { lock.withLock { recorded.append(value) } }
    var values: [Bool] { lock.withLock { recorded } }
}
