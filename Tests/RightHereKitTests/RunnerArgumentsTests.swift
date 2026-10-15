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

    @Test func theRunnerNeverCutsASelectionThatAPresetCouldTake() {
        // A preset refuses more files than its max_files instead of naming fewer than were selected, which only holds
        // if the runner passes at least that many on to rh.
        #expect(RunnerArguments.maxItems >= AgentPreset.maxFilesLimit)
    }

    @Test func aHugeSelectionStaysWithinWhatTheSystemCanStart() {
        let items = (0..<20_000).map { URL(fileURLWithPath: "/Users/me/a-fairly-long-folder-name/with/some/depth/file number \($0).txt") }
        let arguments = RunnerArguments.run(actionID: "open.terminal", context: HereContext(origin: .items, items: items))
        let bytes = arguments.reduce(0) { $0 + $1.utf8.count + 1 }
        #expect(bytes < 200_000, "\(bytes) bytes of arguments would not leave room under the system limit (about 1 MB with the environment)")
        let afterSeparator = arguments.drop { $0 != "--" }.dropFirst()
        #expect(afterSeparator.count == RunnerArguments.maxItems)
        // The first item decides the folder, and several items still read as several.
        #expect(afterSeparator.first == items[0].path)
        // A normal selection is passed whole.
        #expect(RunnerArguments.run(actionID: "x", context: HereContext(origin: .items, items: Array(items.prefix(3)))).suffix(3) == items.prefix(3).map(\.path))
    }

    @Test func noContainerMeansNoContainerOption() {
        let context = HereContext(origin: .services, items: [URL(fileURLWithPath: "/tmp/x")])
        #expect(!RunnerArguments.run(actionID: "reveal", context: context).contains("--container"))
    }

    @Test func everyPlacementHasALaunchProbeMarkerThatReachesTheLaunchProbe() {
        // What `rh doctor --probe-launch --placement <p>` leaves must be what the extension runs, for every placement there is.
        for placement in TerminalPlacement.allCases {
            let arguments = RunnerArguments.probe(markerText: ExtensionProbe.markerText(placement: placement))
            #expect(arguments == ["probe", "launch", "--from-extension", "--placement", placement.configName], "\(placement)")
        }
    }

    @Test("a probe marker only ever picks from a fixed list", arguments: [
        ("launch", ["probe", "launch", "--from-extension"]),
        (" launch\n", ["probe", "launch", "--from-extension"]),
        ("launch:window", ["probe", "launch", "--from-extension", "--placement", "window"]),
        ("launch:tab", ["probe", "launch", "--from-extension", "--placement", "tab"]),
        ("launch:split-right", ["probe", "launch", "--from-extension", "--placement", "split-right"]),
        ("launch:split-down", ["probe", "launch", "--from-extension", "--placement", "split-down"]),
        ("launch:split", ["probe", "automation", "--from-extension"]),
        ("launch:floating", ["probe", "automation", "--from-extension"]),
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
