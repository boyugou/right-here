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
        for glyph in Set(IconProvider.dedicatedGlyphs.values).union([IconProvider.toolbarGlyph]) {
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

    @Test func anAppIconIsOneSmallBitmapAndNotEverySizeOfTheIcon() throws {
        // The menu goes to Finder with its images; an app's own icon holds about thirty sizes of itself, which took a second to send.
        let facts = FakeSystemFacts(applications: ["com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")])
        let provider = IconProvider(facts: facts)
        let image = try #require(provider.image(for: .app("com.apple.Terminal")))
        #expect(image.representations.count == 1)
        let rep = try #require(image.representations.first as? NSBitmapImageRep)
        #expect(rep.pixelsWide == 48 && rep.pixelsHigh == 48, "three pixels to the point")
        #expect(image.size == NSSize(width: 16, height: 16) && rep.size == NSSize(width: 16, height: 16))
        let weight = try #require(image.tiffRepresentation?.count)
        #expect(weight < 100_000, "\(weight) bytes")
        // It is the whole icon, not a blank picture or a corner of one: the middle is drawn and so is most of the square (an app icon has a margin of its own).
        let middle = try #require(rep.colorAt(x: 24, y: 24))
        #expect(middle.alphaComponent > 0.5)
        var opaque = 0
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { opaque += 1 } }
        #expect(opaque > 48 * 48 / 2, "\(opaque) of \(48 * 48) pixels are drawn")
    }

    @Test func theSizeAskedForIsTheSizeOfTheBitmapAndTheIconStaysTheSameObjectAfterward() throws {
        let facts = FakeSystemFacts(applications: ["com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")])
        let provider = IconProvider(facts: facts)
        let large = try #require(provider.image(for: .app("com.apple.Terminal"), side: 18))
        #expect(large.size == NSSize(width: 18, height: 18) && (large.representations.first as? NSBitmapImageRep)?.pixelsWide == 54)
        #expect(provider.image(for: .app("com.apple.Terminal"), side: 18) === large, "it is remembered")
        #expect(provider.image(for: .app("com.apple.Terminal"))?.size == NSSize(width: 16, height: 16))
    }

    @Test func aFileTypeIconIsOneSmallBitmapToo() throws {
        let image = try #require(IconProvider(facts: FakeSystemFacts()).image(for: .fileType("md")))
        #expect(image.representations.count == 1 && (image.representations.first as? NSBitmapImageRep)?.pixelsWide == 48)
        #expect(try #require(image.tiffRepresentation?.count) < 100_000)
    }

    @Test func aNewFileEntryGetsTheSystemIconOfItsKindOfFile() throws {
        let provider = IconProvider(facts: FakeSystemFacts())
        let text = try #require(provider.image(for: .fileType("txt")))
        let markdown = try #require(provider.image(for: .fileType("md")))
        #expect(text.size == NSSize(width: 16, height: 16) && markdown.size == NSSize(width: 16, height: 16))
        // A file name extension that names no type has no icon, and the menu simply shows none.
        #expect(provider.image(for: .fileType("")) == nil)
    }
}
