import Foundation

/// Decides when a refresh may start. One runs at a time; requests that arrive while it runs are answered by exactly one
/// more run after it, however many there were. The one more run starts after the last request, so what it reads is at
/// least as new as the state that request was about (a refresh asked for at the end of an install must not be answered by
/// one that began before the install finished).
public struct RefreshGate: Sendable, Equatable {
    public private(set) var isRunning = false
    public private(set) var hasPendingRequest = false

    public init() {}

    /// A refresh is wanted. Returns whether the caller starts one now; otherwise one is running, and it goes around again.
    public mutating func request() -> Bool {
        if isRunning {
            hasPendingRequest = true
            return false
        }
        isRunning = true
        return true
    }

    /// The running refresh ended. Returns whether it has to run again because it was asked for meanwhile.
    public mutating func finish() -> Bool {
        if hasPendingRequest {
            hasPendingRequest = false
            return true
        }
        isRunning = false
        return false
    }
}

/// Reads the state of the machine, off the main actor, one refresh at a time, and hands each result to the main actor.
///
/// The setup window asks for a refresh when it opens, after a repair, from its refresh button and when the Finder extension
/// has just been switched on. Those may overlap (a double click, a poll that fires during a repair): started side by side
/// they would each ask the login shell for the agents' commands and each write their answer in whatever order they ended,
/// the older one possibly last. Here a request made during a refresh joins it, and one more refresh follows.
@MainActor
public final class RefreshLoop<Snapshot: Sendable> {
    private var gate = RefreshGate()
    private var running: Task<Void, Never>?
    private let load: @Sendable () async -> Snapshot
    private let apply: @MainActor (Snapshot) -> Void
    private let busyChanged: @MainActor (Bool) -> Void

    /// - Parameters:
    ///   - load: Reads the state. It runs off the main actor.
    ///   - apply: Takes a result, on the main actor, in the order the reads ended (which is the order they started).
    ///   - busyChanged: Called with `true` when a burst of refreshes starts and with `false` when it has ended.
    public init(load: @escaping @Sendable () async -> Snapshot, apply: @escaping @MainActor (Snapshot) -> Void,
                busyChanged: @escaping @MainActor (Bool) -> Void = { _ in }) {
        self.load = load
        self.apply = apply
        self.busyChanged = busyChanged
    }

    public var isRunning: Bool { gate.isRunning }

    /// Whether a refresh was asked for while one runs, so that another will follow it.
    var hasPendingRequest: Bool { gate.hasPendingRequest }

    /// Refreshes, or joins the refresh that is running. Returns when everything that was asked for has been applied.
    /// - Parameter first: Reads the state in place of `load` for this refresh alone, when it starts one: a caller that already has part of the state
    ///   (the checks a repair ran) need not read it again. When a refresh is running it is not used, and the one more read that follows is a whole one.
    public func refresh(using first: (@Sendable () async -> Snapshot)? = nil) async {
        if gate.request() {
            busyChanged(true)
            running = Task { await self.drain(first: first) }
        }
        await running?.value
    }

    private func drain(first: (@Sendable () async -> Snapshot)?) async {
        var read = first ?? load
        repeat {
            apply(await read())
            read = load
        } while gate.finish()
        running = nil
        busyChanged(false)
    }
}
