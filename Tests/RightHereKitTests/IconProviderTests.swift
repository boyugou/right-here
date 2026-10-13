import AppKit
import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("IconProvider")
struct IconProviderTests {
    private var catalog: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Apps/FinderExtension/Assets.xcassets")
    }

    @Test func everyDedicatedGlyphHasATemplateImageSetWithAVectorPDF() throws {
        for glyph in Set(IconProvider.dedicatedGlyphs.values) {
            let set = catalog.appendingPathComponent("\(glyph).imageset")
            let contents = try Data(contentsOf: set.appendingPathComponent("Contents.json"))
            let json = try #require(try JSONSerialization.jsonObject(with: contents) as? [String: Any])
            let properties = try #require(json["properties"] as? [String: Any])
            #expect(properties["template-rendering-intent"] as? String == "template", "\(glyph) must render as a template")
            #expect(properties["preserves-vector-representation"] as? Bool == true)
            let pdf = try Data(contentsOf: set.appendingPathComponent("\(glyph).pdf"))
            #expect(pdf.starts(with: Data("%PDF".utf8)))
        }
    }

    @Test func theSymbolsTheMenuUsesAreAllCovered() {
        let used = ["doc.badge.plus", "doc.on.doc", "ellipsis.circle", "magnifyingglass", "terminal", "arrow.up.forward.app"]
        for symbol in used { #expect(IconProvider.dedicatedGlyphs[symbol] != nil, "\(symbol) has no dedicated glyph") }
    }

    @Test func outsideTheExtensionTheSystemSymbolIsStillUsed() {
        let provider = IconProvider(facts: FakeSystemFacts())
        let image = provider.image(for: .symbol("doc.badge.plus"))
        #expect(image != nil)
        #expect(image?.isTemplate == true)
    }
}
