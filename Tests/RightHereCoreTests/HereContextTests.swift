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


@Suite("Links that point nowhere, and paths cut like the kernel cuts them")
struct HereContextEdgeTests {
    private let machine = FakeSystemFacts(
        directories: ["/Users/tester/code"],
        files: ["/Users/tester/code/real.txt"],
        danglingLinks: ["/Users/tester/code/broken-link"]
    )

    @Test func aDanglingLinkExistsAndIsNotReportedMissing() {
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/broken-link")])
        #expect(context.firstMissingPath(facts: machine) == nil, "lstat sees the link; only a stat-based check calls it missing")
        let asContainer = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code/broken-link"))
        #expect(asContainer.firstMissingPath(facts: machine) == nil)
    }

    @Test func aDanglingLinkHasNoFolderAndItsParentIsNotSubstituted() {
        // It exists (copy and reveal work), but it names nowhere: the folder holding it is not what was asked for.
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/broken-link")])
        #expect(context.workingDirectory(facts: machine) == nil)
        #expect(context.unplaceableTarget(facts: machine)?.reason == .dangling)
        #expect(context.firstMissingPath(facts: machine) == nil)
    }

    @Test func aPathWithNothingAtAllIsStillMissing() {
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code/nothing")])
        #expect(context.firstMissingPath(facts: machine)?.path == "/Users/tester/code/nothing")
        #expect(context.workingDirectory(facts: machine) == nil)
    }

    @Test("a slash followed by a combining mark is still a slash to the file system", arguments: [
        ("/d/a/\u{301}/../b", "/d/a/b"),
        ("/d/a/\u{FE0F}/../b", "/d/a/b"),
        ("/d/a/\u{200D}/../b", "/d/a/b"),
        ("/d/a/\u{20E3}/./c", "/d/a/\u{20E3}/c"),
        ("/d/./a//b/../c", "/d/a/c"),
        ("/../..", "/")
    ])
    func normalizationSplitsOnScalars(input: String, expected: String) {
        #expect(URL(fileURLWithPath: input).lexicallyNormalized.path == expected)
    }

    @Test func aDotWithAMarkAfterItIsAnOrdinaryName() {
        // "." followed by a combining acute is a real file name, not the current directory.
        #expect(URL(fileURLWithPath: "/d/.\u{301}/x").lexicallyNormalized.path == "/d/.\u{301}/x")
        #expect(URL(fileURLWithPath: "/d/..\u{301}/x").lexicallyNormalized.path == "/d/..\u{301}/x")
    }
}


@Suite("Paths the system will not let us look at")
struct UnreadablePathTests {
    private let machine = FakeSystemFacts(
        directories: ["/Users/tester/code", "/Users/tester/Documents"],
        unreadablePaths: ["/Users/tester/Documents/project", "/Users/tester/Documents/notes.txt"]
    )

    @Test func anUnreadablePathIsNeitherMissingNorAFolder() {
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/Documents/project")])
        #expect(machine.itemState(URL(fileURLWithPath: "/Users/tester/Documents/project")) == .unreadable)
        #expect(context.firstMissingPath(facts: machine) == nil, "it was selected in Finder; it is not a typo")
        #expect(context.workingDirectory(facts: machine) == nil, "its parent is not the folder that was asked for")
        #expect(context.unplaceableTarget(facts: machine)?.url.path == "/Users/tester/Documents/project")
        #expect(context.unplaceableTarget(facts: machine)?.reason == .unreadable)
    }

    @Test func aFileThatCannotBeInspectedIsNeverTakenForItsParentFolderEither() {
        // Its type is unknown, and a file handed to a terminal runs; so there is no folder to give.
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/Documents/notes.txt")])
        #expect(context.workingDirectory(facts: machine) == nil)
    }

    @Test func aContainerThatCannotBeInspectedIsReportedToo() {
        let context = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/Documents/project"))
        #expect(context.workingDirectory(facts: machine) == nil)
        #expect(context.unplaceableTarget(facts: machine)?.url.path == "/Users/tester/Documents/project")
        #expect(context.firstMissingPath(facts: machine) == nil)
    }

    @Test func aReadableSelectionHasNoUnreadableTarget() {
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: "/Users/tester/code")])
        #expect(context.unplaceableTarget(facts: machine) == nil)
        #expect(HereContext(origin: .cli).unplaceableTarget(facts: machine) == nil)
    }
}
