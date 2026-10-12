import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("Runner arguments")
struct RunnerArgumentsTests {
    @Test func aMenuClickOnItemsPassesTheOriginTheContainerAndTheItemsAfterADoubleDash() {
        let context = HereContext(origin: .items,
                                  items: [URL(fileURLWithPath: "/Users/me/my code/a b.txt"), URL(fileURLWithPath: "/Users/me/my code/-rf")],
                                  container: URL(fileURLWithPath: "/Users/me/my code"))
        #expect(RunnerArguments.run(actionID: "agent.claude", context: context) == [
            "run", "--alert", "agent.claude", "--origin", "items", "--container", "/Users/me/my code", "--", "/Users/me/my code/a b.txt", "/Users/me/my code/-rf"
        ])
    }

    @Test func aBackgroundClickHasNoItemsAndEndsAtTheDoubleDash() {
        let context = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/me/code"))
        #expect(RunnerArguments.run(actionID: "open.terminal", context: context) == [
            "run", "--alert", "open.terminal", "--origin", "container", "--container", "/Users/me/code", "--"
        ])
    }

    @Test func noContainerMeansNoContainerOption() {
        let context = HereContext(origin: .services, items: [URL(fileURLWithPath: "/tmp/x")])
        #expect(!RunnerArguments.run(actionID: "reveal", context: context).contains("--container"))
    }

    @Test("a probe marker only ever picks from a fixed list", arguments: [
        ("launch", ["probe", "launch", "--from-extension"]),
        (" launch\n", ["probe", "launch", "--from-extension"]),
        ("launch:window", ["probe", "launch", "--from-extension", "--placement", "window"]),
        ("launch:tab", ["probe", "launch", "--from-extension", "--placement", "tab"]),
        ("automation", ["probe", "automation", "--from-extension"]),
        ("", ["probe", "automation", "--from-extension"])
    ])
    func probeVocabulary(text: String, expected: [String]) {
        #expect(RunnerArguments.probe(markerText: text) == expected)
    }

    @Test("a marker cannot smuggle arguments into rh", arguments: [
        "launch --placement ../../x", "launch:tab; touch /tmp/x", "install", "launch:split", "LAUNCH", "launch:tab:extra", "--version", "../../../bin/sh"
    ])
    func hostileMarkers(text: String) {
        #expect(RunnerArguments.probe(markerText: text) == ["probe", "automation", "--from-extension"])
    }
}
