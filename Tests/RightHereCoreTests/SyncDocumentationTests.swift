import Testing
@testable import RightHereCore

@Suite("Documentation: sync")
struct SyncDocumentationTests {
    @Test func theSyncTopicExistsAndCoversTheParts() throws {
        let text = try #require(Documentation.text(for: "sync"))
        for part in ["Keep your config in sync", "config.local.toml", "disabled", "symlink", "sandbox", "Dropbox", "rh config sync push", "remote-evicted", "api_key",
                     "--allow-commands", "open_args", "command"] {
            #expect(text.contains(part), "the sync guide does not mention \(part)")
        }
        #expect(Documentation.topics.contains("sync"))
        #expect(Documentation.config.contains("rh docs sync"))
    }

    @Test func theSchemaDescribesDisabledAsOverlayOnly() throws {
        let node = try #require(ConfigSchema.root.first { $0.key == "disabled" })
        #expect(node.kind == .stringArray)
        #expect(node.summary.contains("config.local.toml"))
    }
}
