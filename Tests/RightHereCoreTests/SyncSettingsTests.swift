import Testing
@testable import RightHereCore

@Suite("SyncSettings")
struct SyncSettingsTests {
    private let hash = String(repeating: "ab", count: 32)

    @Test func aFileNestedDeeperThanAnythingRightHereWritesIsNeverGivenToTheTOMLParser() {
        let deep = String(repeating: "[", count: 40) + String(repeating: "]", count: 40)
        #expect(SyncSettings.parse("folder = \"/f\"\nnested = \(deep)\n") == nil)
        #expect(SyncSettings.parse("folder = \"/f\"\n") != nil, "control: the same file without the nesting is read")
    }

    @Test func roundTrips() {
        let settings = SyncSettings(folder: "/tmp/with \"quotes\" and \\ backslash/Right Here", lastSynced: hash)
        #expect(SyncSettings.parse(settings.render()) == settings)
        let fresh = SyncSettings(folder: "/tmp/x")
        #expect(SyncSettings.parse(fresh.render()) == fresh)
    }

    @Test func aFolderWithControlCharactersRoundTrips() {
        let settings = SyncSettings(folder: "/tmp/a\nb\tc")
        #expect(SyncSettings.parse(settings.render()) == settings)
    }

    @Test("text that is not a sync file is refused", arguments: ["", "folder = 3\n", "folder = \"\"\n", "[folder]\n", "folder = \"/x\"\nlast_synced_sha256 = \"nothex\"\n", "folder = \"/x\"\nlast_synced_sha256 = 4\n", "folder = \"/x\"\nlast_synced_sha256 = \"\"\n", "folder = "])
    func refused(text: String) {
        #expect(SyncSettings.parse(text) == nil)
    }
}
