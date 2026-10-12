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

    @Test func aFileAsTheContainerYieldsItsFolder() {
        let context = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code/b.txt"))
        #expect(context.workingDirectory(facts: facts)?.path == "/Users/tester/code")
    }

    @Test func aContainerThatDoesNotExistYieldsNil() {
        let context = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/gone"))
        #expect(context.workingDirectory(facts: facts) == nil)
    }

    @Test func anItemInAFolderThatDoesNotExistYieldsNil() {
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/gone/x.txt")])
        #expect(context.workingDirectory(facts: facts) == nil)
    }

    @Test func aMistypedItemIsNotReplacedByTheFolderAroundIt() {
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/appp")])
        #expect(context.workingDirectory(facts: facts) == nil)
        #expect(context.firstMissingPath(facts: facts)?.path == "/Users/tester/code/appp")
    }

    @Test func theMissingPathIsFoundAmongSeveralItemsAndForAContainer() {
        let several = HereContext(origin: .items, items: [
            URL(fileURLWithPath: "/Users/tester/code/b.txt"), URL(fileURLWithPath: "/Users/tester/code/gone")
        ])
        #expect(several.firstMissingPath(facts: facts)?.path == "/Users/tester/code/gone")
        let container = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/gone"))
        #expect(container.firstMissingPath(facts: facts)?.path == "/Users/tester/gone")
    }

    @Test func nothingIsMissingWhenEverythingExistsOrNothingWasNamed() {
        #expect(HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/b.txt")]).firstMissingPath(facts: facts) == nil)
        #expect(HereContext(origin: .container).firstMissingPath(facts: facts) == nil)
    }

    @Test func aFileWhereAFolderIsExpectedNeverBecomesTheDirectory() {
        // /Users/tester/code/b.txt is a file: nothing under it exists, let alone as a working directory.
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/b.txt/inside")])
        #expect(context.workingDirectory(facts: facts) == nil)
        let asContainer = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code/b.txt/inside"))
        #expect(asContainer.workingDirectory(facts: facts) == nil)
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

@Suite("Path normalization")
struct PathNormalizationTests {
    @Test("dot components and repeated slashes are removed", arguments: [
        ("/a/b/../c", "/a/c"), ("/a/./b", "/a/b"), ("//a///b/", "/a/b"), ("/a/b/..", "/a"), ("/..", "/"), ("/", "/"),
        ("/a/../../b", "/b")
    ])
    func normalizes(input: String, expected: String) {
        #expect(URL(fileURLWithPath: input).lexicallyNormalized.path == expected)
    }

    @Test("the /private prefix of /tmp, /var and /etc is kept", arguments: ["/private/tmp/x", "/private/var/folders/a", "/private/etc/hosts"])
    func keepsPrivatePrefix(path: String) {
        #expect(URL(fileURLWithPath: path).lexicallyNormalized.path == path)
        #expect(HereContext(origin: .items, items: [URL(fileURLWithPath: path)]).items.first?.path == path)
    }
}

@Suite("Finder context")
struct FinderContextTests {
    private let folder = URL(fileURLWithPath: "/Users/tester/code")
    private let file = URL(fileURLWithPath: "/Users/tester/code/a.txt")

    @Test func itemsKeepTheSelectionAndTheContainer() {
        let context = HereContext.finder(kind: .items, selected: [file], targeted: folder)
        #expect(context.origin == .items)
        #expect(context.items == [file])
        #expect(context.container == folder)
    }

    @Test func aBackgroundMenuIgnoresTheReportedSelection() {
        let previousColumnSelection = URL(fileURLWithPath: "/Users/tester")
        let context = HereContext.finder(kind: .container, selected: [previousColumnSelection], targeted: folder)
        #expect(context.origin == .container)
        #expect(context.items.isEmpty)
        #expect(context.container == folder)
    }

    @Test func aBackgroundMenuFallsBackToTheSelectionWhenNothingIsTargeted() {
        #expect(HereContext.finder(kind: .container, selected: [folder], targeted: nil).container == folder)
    }

    @Test func sidebarUsesTheTargetedFolder() {
        let context = HereContext.finder(kind: .sidebar, selected: [], targeted: folder)
        #expect(context.origin == .sidebar)
        #expect(context.container == folder)
    }

    @Test func toolbarActsOnTheSelectionWhenThereIsOne() {
        let withSelection = HereContext.finder(kind: .toolbar, selected: [file], targeted: folder)
        #expect(withSelection.items == [file])
        let without = HereContext.finder(kind: .toolbar, selected: [], targeted: folder)
        #expect(without.items.isEmpty)
        #expect(without.container == folder)
    }
}
