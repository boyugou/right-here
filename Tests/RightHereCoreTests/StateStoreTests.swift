import Foundation
import Testing
@testable import RightHereCore

@Suite("StateStore (pins and recents)")
struct StateStoreTests {
    @Test("Invalid saved-folder documents are reported", arguments: ["pins = [", "pins = '/work/app'", "recents = false", "pins = ['/work/app', 42]", "recents = [false]", "pin = ['/work/app']", "[extra]\npins = []"])
    func invalidStateIsReportedInsteadOfSilentlyDiscarded(_ text: String) {
        #expect(throws: (any Error).self) { try StateStore.parse(text) }
    }

    @Test func deepNestingIsRefusedBeforeParsing() {
        let text = "pins = " + String(repeating: "[", count: 9) + String(repeating: "]", count: 9)
        #expect(throws: StateStore.ParseError.tooDeep) { try StateStore.parse(text) }
    }

    @Test(arguments: ["", "# No folders yet\n", "pins = []", "recents = []"])
    func absentOptionalListsAreEmpty(_ text: String) throws {
        #expect(try StateStore.parse(text) == StateStore())
    }

    @Test func emptyStateStoreParsesAndRendersCleanly() throws {
        let store = StateStore()
        #expect(store.pins.isEmpty)
        #expect(store.recents.isEmpty)

        let rendered = store.render()
        let parsed = try StateStore.parse(rendered)
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

    @Test func tomlRoundTripPreservesPinsAndRecents() throws {
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
        let parsed = try StateStore.parse(toml)
        #expect(parsed.pins == ["/Users/tester/project-alpha", "/Users/tester/docs"])
        #expect(parsed.recents == ["/Users/tester/project-alpha", "/Users/tester/downloads"])

        let reRendered = parsed.render()
        let reParsed = try StateStore.parse(reRendered)
        #expect(reParsed == parsed)
    }

    @Test func aFileHoldsOnlyAbsoluteFolders() throws {
        let parsed = try StateStore.parse("""
        pins = ["relative/project", "~/project", "/Users/tester/code/", "/Users/tester/./code", "", "/Users/tester/../tester/notes"]
        recents = ["../elsewhere", "/Users/tester/a", "."]
        """)
        #expect(parsed.pins == ["/Users/tester/code", "/Users/tester/notes"])
        #expect(parsed.recents == ["/Users/tester/a"])
    }

    @Test func aFileWithMoreRecentsThanTheLimitKeepsTheNewest() throws {
        let many = (1...StateStore.maxRecents + 5).map { "\"/folder/\($0)\"" }.joined(separator: ", ")
        let parsed = try StateStore.parse("recents = [\(many)]")
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
