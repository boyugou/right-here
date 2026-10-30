import Foundation
import Testing
@testable import RightHereCore

@Suite("StateStore (pins and recents)")
struct StateStoreTests {
    @Test func aFileNestedDeeperThanAnythingRightHereWritesIsNeverGivenToTheTOMLParser() {
        // A parser with a recursion limit of its own can overflow the stack on a file somebody made on purpose: the file is refused as a whole, whatever else is in it.
        let deep = String(repeating: "[", count: 40) + String(repeating: "]", count: 40)
        #expect(StateStore.parse("pins = [\"/a\"]\nnested = \(deep)\n").pins.isEmpty)
        #expect(StateStore.parse("pins = [\"/a\"]\n").pins == ["/a"], "control: the same file without the nesting is read")
    }

    @Test func emptyStateStoreParsesAndRendersCleanly() {
        let store = StateStore()
        #expect(store.pins.isEmpty)
        #expect(store.recents.isEmpty)

        let rendered = store.render()
        let parsed = StateStore.parse(rendered)
        #expect(parsed == store)
    }

    @Test func pinAddsFolderDeduplicatedAndStandardized() {
        var store = StateStore()
        let added1 = store.pin("/Users/tester/code")
        #expect(added1)
        #expect(store.pins == ["/Users/tester/code"])

        // Second pin of same folder returns false and does not duplicate
        let added2 = store.pin("/Users/tester/code")
        #expect(!added2)
        let added3 = store.pin("/Users/tester/code/")
        #expect(!added3)
        #expect(store.pins == ["/Users/tester/code"])

        let added4 = store.pin("/Users/tester/notes")
        #expect(added4)
        #expect(store.pins == ["/Users/tester/code", "/Users/tester/notes"])
    }

    @Test func unpinRemovesFolder() {
        var store = StateStore(pins: ["/Users/tester/code", "/Users/tester/notes"])
        let removed1 = store.unpin("/Users/tester/code")
        #expect(removed1)
        #expect(store.pins == ["/Users/tester/notes"])

        let removed2 = store.unpin("/Users/tester/code")
        #expect(!removed2)
        #expect(store.pins == ["/Users/tester/notes"])
    }

    @Test func recentsAreOrderedMostRecentFirstAndCappedAtLimit() {
        var store = StateStore()
        for i in 1...25 {
            store.recordRecent("/folder/\(i)")
        }
        #expect(store.recents.count == StateStore.maxRecents)
        #expect(store.recents.first == "/folder/25")
        #expect(store.recents.last == "/folder/6")

        // Visiting an existing folder promotes it to the top
        store.recordRecent("/folder/10")
        #expect(store.recents.first == "/folder/10")
        #expect(store.recents.count == StateStore.maxRecents)
    }

    @Test func clearRecentsEmptiesRecentsList() {
        var store = StateStore(pins: ["/Users/tester/code"], recents: ["/Users/tester/a", "/Users/tester/b"])
        store.clearRecents()
        #expect(store.recents.isEmpty)
        #expect(store.pins == ["/Users/tester/code"])
    }

    @Test func tomlRoundTripPreservesPinsAndRecents() {
        let toml = """
        # Right Here local state (pins and recent folders)

        pins = [
          "/Users/tester/project-alpha",
          "/Users/tester/docs",
        ]

        recents = [
          "/Users/tester/project-alpha",
          "/Users/tester/downloads",
        ]
        """
        let parsed = StateStore.parse(toml)
        #expect(parsed.pins == ["/Users/tester/project-alpha", "/Users/tester/docs"])
        #expect(parsed.recents == ["/Users/tester/project-alpha", "/Users/tester/downloads"])

        let reRendered = parsed.render()
        let reParsed = StateStore.parse(reRendered)
        #expect(reParsed == parsed)
    }

    @Test func aFileHoldsOnlyAbsoluteFolders() {
        let parsed = StateStore.parse("""
        pins = ["relative/project", "~/project", "/Users/tester/code/", "/Users/tester/./code", "", "/Users/tester/../tester/notes"]
        recents = ["../elsewhere", "/Users/tester/a", "."]
        """)
        #expect(parsed.pins == ["/Users/tester/code", "/Users/tester/notes"])
        #expect(parsed.recents == ["/Users/tester/a"])
    }

    @Test func aFileWithMoreRecentsThanTheLimitKeepsTheNewest() {
        let many = (1...StateStore.maxRecents + 5).map { "\"/folder/\($0)\"" }.joined(separator: ", ")
        let parsed = StateStore.parse("recents = [\(many)]")
        #expect(parsed.recents.count == StateStore.maxRecents)
        #expect(parsed.recents.first == "/folder/1")
    }

    @Test func aRelativeFolderIsNeitherPinnedNorRemembered() {
        var store = StateStore(pins: ["/Users/tester/code"])
        let pinnedRelative = store.pin("relative/project")
        let pinnedTilde = store.pin("~/project")
        store.recordRecent("relative/project")
        let unpinnedRelative = store.unpin("code")
        #expect(!pinnedRelative && !pinnedTilde && !unpinnedRelative)
        #expect(store.pins == ["/Users/tester/code"])
        #expect(store.recents.isEmpty)
    }
}
