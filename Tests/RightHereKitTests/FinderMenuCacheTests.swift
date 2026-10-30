import Foundation
import Testing
@testable import RightHereKit
import RightHereCore

@Suite("FinderMenuCache: what the extension serves and what a warmup may replace")
struct FinderMenuCacheTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let oldConfig = ConfigStore.Stamp(base: Date(timeIntervalSince1970: 1), local: nil)
    private let newConfig = ConfigStore.Stamp(base: Date(timeIntervalSince1970: 2), local: nil)

    @Test func aWarmupBuildsEveryMenuAClickOnAFolderCanAskForTheToolbarsToo() {
        var cache = FinderMenuCache<String>()
        cache.storeWarmup(hasMenu: true, stamp: oldConfig, startedAt: t0, now: t0) { "built for \($0.rawValue)" }
        for kind in [FinderMenuKind.items, .container, .sidebar, .toolbar] { #expect(cache[kind]?.menu == "built for \(kind.rawValue)" && cache[kind]?.builtAt == t0, "\(kind)") }
    }

    @Test func aMenuThatIsServedOldIsBuiltAgainByTheNextWarmupIncludingTheToolbars() {
        var cache = FinderMenuCache<String>()
        cache.store("click", kind: .toolbar, stamp: oldConfig, now: t0)
        let later = t0.addingTimeInterval(120)
        cache.storeWarmup(hasMenu: true, stamp: oldConfig, startedAt: later, now: later) { _ in "new" }
        #expect(cache[.toolbar]?.menu == "new" && cache[.toolbar]?.builtAt == later, "the toolbar's menu was served for ever, old")
    }

    @Test func aWarmupThatFindsNoMenuLeavesNoneServed() {
        var cache = FinderMenuCache<String>()
        cache.storeWarmup(hasMenu: true, stamp: oldConfig, startedAt: t0, now: t0) { _ in "old" }
        cache.storeWarmup(hasMenu: false, stamp: oldConfig, startedAt: t0.addingTimeInterval(60), now: t0.addingTimeInterval(60)) { _ in "never" }
        for kind in FinderMenuCache<String>.kinds { #expect(cache[kind] == nil, "\(kind): an entry for an app that is gone was served, a day later") }
    }

    @Test func aWarmupThatBeganBeforeAConfigChangeDoesNotPutItsOldMenusOverANewerOne() {
        var cache = FinderMenuCache<String>()
        // The warmup begins; the config changes; a click builds the menu from the new config; the warmup ends with what it read before.
        let started = t0
        cache.store("built from the new config", kind: .container, stamp: newConfig, now: t0.addingTimeInterval(1))
        cache.storeWarmup(hasMenu: true, stamp: oldConfig, startedAt: started, now: t0.addingTimeInterval(2)) { "warmup \($0.rawValue)" }
        #expect(cache[.container]?.menu == "built from the new config" && cache[.container]?.stamp == newConfig)
        #expect(cache[.sidebar]?.menu == "warmup sidebar", "the kinds nobody built since are filled")
    }

    @Test func aWarmupReplacesAMenuThatWasBuiltBeforeItBeganOrFromTheSameConfig() {
        var cache = FinderMenuCache<String>()
        cache.store("before", kind: .container, stamp: oldConfig, now: t0)
        cache.storeWarmup(hasMenu: true, stamp: newConfig, startedAt: t0.addingTimeInterval(5), now: t0.addingTimeInterval(6)) { _ in "warmup" }
        #expect(cache[.container]?.menu == "warmup")
        cache.store("click", kind: .container, stamp: newConfig, now: t0.addingTimeInterval(7))
        cache.storeWarmup(hasMenu: true, stamp: newConfig, startedAt: t0.addingTimeInterval(6), now: t0.addingTimeInterval(8)) { _ in "warmup again" }
        #expect(cache[.container]?.menu == "warmup again", "the same config: the newer build wins")
    }
}
