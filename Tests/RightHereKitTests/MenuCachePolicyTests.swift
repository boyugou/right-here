import Foundation
import Testing
@testable import RightHereKit

@Suite("MenuCachePolicy")
struct MenuCachePolicyTests {
    private let built = Date(timeIntervalSince1970: 1_000_000)

    @Test func aMenuBuiltJustNowIsServedWhileTheConfigIsTheSame() {
        #expect(MenuCachePolicy.canServe(builtAt: built, now: built, sameConfig: true))
        #expect(MenuCachePolicy.canServe(builtAt: built, now: built.addingTimeInterval(MenuCachePolicy.lifetime - 1), sameConfig: true))
    }

    @Test func anOldMenuIsBuiltAgainEvenWhenTheConfigDidNotChange() {
        // What is installed can change without the config changing.
        #expect(!MenuCachePolicy.canServe(builtAt: built, now: built.addingTimeInterval(MenuCachePolicy.lifetime), sameConfig: true))
        #expect(!MenuCachePolicy.canServe(builtAt: built, now: built.addingTimeInterval(3600), sameConfig: true))
    }

    @Test func aChangedConfigNeverServesTheOldMenu() {
        #expect(!MenuCachePolicy.canServe(builtAt: built, now: built, sameConfig: false))
    }

    @Test func aClockThatWentBackwardsIsNotTrusted() {
        #expect(!MenuCachePolicy.canServe(builtAt: built, now: built.addingTimeInterval(-5), sameConfig: true))
    }

    @Test func theMenuLivesShorterThanTheFactsItWasBuiltFrom() {
        #expect(MenuCachePolicy.lifetime < CachingSystemFacts().lifetimeForTesting)
    }
}
