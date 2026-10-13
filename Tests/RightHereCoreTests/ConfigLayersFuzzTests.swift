import Foundation
import Testing
@testable import RightHereCore

@Suite("Fuzz: config layers")
struct ConfigLayersFuzzTests {
    @Test("an empty overlay changes nothing, through the merge path", arguments: Array(1...8))
    func emptyOverlayIsTransparent(seed: Int) {
        for text in randomConfigTexts(seed: UInt64(seed) &+ 1000, count: 150) {
            let plain = ConfigParser.parse(text)
            let layered = ConfigLayers.load(base: .text(text), local: .text("# nothing here\n"))
            #expect(layered.config == plain.config, "config differs for:\n\(text)")
            #expect(layered.diagnostics == plain.diagnostics, "diagnostics differ for:\n\(text)")
        }
    }

    @Test("values survive the trip through the tree and back to text", arguments: Array(1...8))
    func treeRoundTrips(seed: Int) {
        for text in randomConfigTexts(seed: UInt64(seed) &+ 2000, count: 150) {
            guard let first = ConfigParser.readTree(text).tree else { continue }
            let again = ConfigParser.readTree(TOMLEmitter.emit(first)).tree
            #expect(again == first, "round trip changed:\n\(text)")
        }
    }

    @Test("random overlays over random bases never crash and honour disabled", arguments: Array(1...8))
    func randomPairs(seed: Int) {
        let bases = randomConfigTexts(seed: UInt64(seed) &+ 3000, count: 100)
        let overlays = randomConfigTexts(seed: UInt64(seed) &+ 4000, count: 100)
        for (base, overlay) in zip(bases, overlays) {
            _ = ConfigLayers.load(base: .text(base), local: .text(overlay + "\n")).config.allApps
            let disabled = ConfigLayers.load(base: .text(base), local: .text("disabled = [\"md\", \"mine\"]\n"))
            #expect(disabled.config.newFile.templates.allSatisfy { $0.id != "md" })
            #expect(disabled.config.agent(id: "mine") == nil)
        }
    }
}
