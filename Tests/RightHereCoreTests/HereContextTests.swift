import Foundation
import Testing
@testable import RightHereCore

private let facts = FakeSystemFacts(
    currentDirectory: URL(fileURLWithPath: "/Users/tester/work"),
    directories: ["/Users/tester/code", "/Users/tester/code/app", "/Users/tester/work"],
    files: ["/Users/tester/code/app/a.txt", "/Users/tester/code/b.txt"]
)

@Suite("HereContext")
struct HereContextTests {
    @Test func singleFolderOpensItself() {
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/app")])
        #expect(context.workingDirectory(facts: facts)?.path == "/Users/tester/code/app")
    }

    @Test func fileOpensItsParent() {
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/app/a.txt")])
        #expect(context.workingDirectory(facts: facts)?.path == "/Users/tester/code/app")
    }

    @Test func severalItemsUseFirstItemsFolder() {
        let context = HereContext(origin: .items, items: [
            URL(fileURLWithPath: "/Users/tester/code/b.txt"),
            URL(fileURLWithPath: "/Users/tester/code/app")
        ])
        #expect(context.workingDirectory(facts: facts)?.path == "/Users/tester/code")
    }

    @Test func backgroundUsesContainer() {
        let context = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code"))
        #expect(context.workingDirectory(facts: facts)?.path == "/Users/tester/code")
    }

    @Test func commandLineFallsBackToCurrentDirectory() {
        let context = HereContext(origin: .cli)
        #expect(context.workingDirectory(facts: facts)?.path == "/Users/tester/work")
    }

    @Test func nothingToActOnYieldsNil() {
        #expect(HereContext(origin: .container).workingDirectory(facts: facts) == nil)
    }

    @Test func pathTargetsPreferSelection() {
        let selected = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/b.txt")],
                                   container: URL(fileURLWithPath: "/Users/tester/code"))
        #expect(selected.pathTargets.map(\.path) == ["/Users/tester/code/b.txt"])
        let background = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code"))
        #expect(background.pathTargets.map(\.path) == ["/Users/tester/code"])
    }

    @Test func itemsAreStandardized() {
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/app/../b.txt")])
        #expect(context.items.map(\.path) == ["/Users/tester/code/b.txt"])
    }

    @Test func codableRoundTrip() throws {
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/b.txt")],
                                  container: URL(fileURLWithPath: "/Users/tester/code"))
        let data = try JSONEncoder().encode(context)
        #expect(try JSONDecoder().decode(HereContext.self, from: data) == context)
    }
}
