import Foundation
import Testing
import RightHereCore
import RightHereKit
@testable import AppModel

/// Holds a doctor's process after its config was read, so edits during a refresh are deterministic.
private actor RefreshProbe: ProcessRunner {
    private var holdNext = false
    private var pending: CheckedContinuation<Void, Never>?
    private var activationRead = false

    func arm() { holdNext = true }
    func sawActivationRead() { activationRead = true }
    func isHolding() -> Bool { pending != nil }
    func hasActivationRead() -> Bool { activationRead }
    func release() { holdNext = false; pending?.resume(); pending = nil }

    func run(_ step: ProcessStep, timeout: Duration?) async throws -> ProcessResult {
        if holdNext {
            holdNext = false
            await withCheckedContinuation { pending = $0 }
        }
        return ProcessResult(status: 0)
    }
}

private actor ActivationProbe {
    private var holdNext = true
    private var pending: CheckedContinuation<Void, Never>?

    func didRead() async {
        if holdNext {
            holdNext = false
            await withCheckedContinuation { pending = $0 }
        }
    }
    func isHolding() -> Bool { pending != nil }
    func release() { holdNext = false; pending?.resume(); pending = nil }
}

@Suite("Configuration changes on returning to the window")
@MainActor
struct SetupConfigRefreshTests {
    @Test func externalCreationAndDeletionUpdateFirstRunWithoutWaitingForTheQuietPeriod() async throws {
        let mac = try Mac(activationQuietPeriod: .seconds(60)); defer { mac.cleanUp() }
        await mac.model.refresh()
        #expect(mac.model.needsFirstRunChoice)
        try mac.writeConfig()
        await mac.model.refreshOnActivation()
        #expect(mac.model.configIsThere && !mac.model.needsFirstRunChoice)
        try FileManager.default.removeItem(at: mac.paths.configFile)
        await mac.model.refreshOnActivation()
        #expect(!mac.model.configIsThere && mac.model.needsFirstRunChoice)
    }

    @Test func aCommentOnlyEditDoesNotRestartTheLoginShellOnReturn() async throws {
        let mac = try Mac(activationQuietPeriod: .seconds(60)); defer { mac.cleanUp() }
        try mac.writeConfig()
        await mac.model.refresh()
        let before = mac.runner.calls.count
        try mac.writeConfig("# My tools\n[general]\n")
        await mac.model.refreshOnActivation()
        #expect(mac.runner.calls.count == before)
        #expect(mac.model.check(.config)?.status == .ok)
    }

    @Test func aNewDanglingOverlayIsVisibleEvenThoughItStillReadsAsAnAbsentFile() async throws {
        let mac = try Mac(activationQuietPeriod: .seconds(60)); defer { mac.cleanUp() }
        try mac.writeConfig()
        await mac.model.refresh()
        let target = mac.home.appendingPathComponent("not-created.toml")
        try FileManager.default.createSymbolicLink(at: mac.paths.localConfigFile, withDestinationURL: target)
        await mac.model.refreshOnActivation()
        #expect(mac.model.check(.config)?.status == .fail)
        #expect(mac.model.check(.config)?.detail?.english().contains("config.local.toml") == true)
        #expect(mac.model.snapshot?.configFiles == [.main, .local])
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test func anEditDuringARefreshIsComparedWithTheConfigBeingRead() async throws {
        let probe = RefreshProbe()
        let mac = try Mac(activationQuietPeriod: .seconds(60), loaderRunner: probe, afterConfigRead: { await probe.sawActivationRead() })
        defer { mac.cleanUp() }
        try mac.writeConfig()
        await mac.model.refresh()
        #expect(mac.model.check(.config)?.status == .ok)

        try mac.writeConfig("[general\n")
        await probe.arm()
        let reading = Task { await mac.model.refresh() }
        defer { Task { await probe.release() } }
        let held = await eventually { await probe.isHolding() }
        #expect(held, "the full read never reached the held process")

        // Return to the already displayed config while a different, broken version is being checked.
        try mac.writeConfig()
        let returning = Task { await mac.model.refreshOnActivation() }
        let inspected = await eventually { await probe.hasActivationRead() }
        await probe.release()
        await reading.value
        await returning.value
        #expect(inspected, "activation during a full refresh was discarded")
        #expect(mac.model.check(.config)?.status == .ok, "the older read's error survived the edit made during it")
        #expect(mac.model.menuState == .ready)
    }

    @Test func returningAgainDuringALightweightReadQueuesAnotherInspection() async throws {
        let probe = ActivationProbe()
        let mac = try Mac(activationQuietPeriod: .seconds(60), afterConfigRead: { await probe.didRead() })
        defer { mac.cleanUp() }
        try mac.writeConfig()
        await mac.model.refresh()
        let first = Task { await mac.model.refreshOnActivation() }
        defer { Task { await probe.release() } }
        #expect(await eventually { await probe.isHolding() })
        try mac.writeConfig("[general\n")
        var secondStarted = false
        let second = Task { secondStarted = true; await mac.model.refreshOnActivation() }
        #expect(await mac.eventually { secondStarted })
        await probe.release()
        await first.value
        await second.value
        #expect(mac.model.check(.config)?.status == .fail)
        #expect(mac.model.menuState == .invalidConfig)
    }

    @Test func aValidSymlinkUpdatesItsWarningEvenWhenTheContentsDoNotChange() async throws {
        let mac = try Mac(activationQuietPeriod: .seconds(60)); defer { mac.cleanUp() }
        try mac.writeConfig()
        await mac.model.refresh()
        let target = mac.home.appendingPathComponent("dotfiles.toml")
        try FileManager.default.moveItem(at: mac.paths.configFile, to: target)
        try FileManager.default.createSymbolicLink(at: mac.paths.configFile, withDestinationURL: target)
        await mac.model.refreshOnActivation()
        #expect(mac.model.check(.config)?.status == .warn)
        #expect(mac.model.check(.config)?.notes.contains(.doctorConfigSymlink("config.toml")) == true)
        try FileManager.default.removeItem(at: mac.paths.configFile)
        try FileManager.default.moveItem(at: target, to: mac.paths.configFile)
        await mac.model.refreshOnActivation()
        #expect(mac.model.check(.config)?.status == .ok)
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}
