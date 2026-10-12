import Testing
@testable import RightHereCore

@Suite("AppVersion")
struct AppVersionTests {
    @Test("parses the leading dotted number", arguments: [
        ("1.3.1", [1, 3, 1]), ("1.3", [1, 3]), ("27", [27]), ("1.4.0-dev+abc", [1, 4, 0]), ("2.0 (beta)", [2, 0])
    ])
    func parses(text: String, components: [Int]) {
        #expect(AppVersion(text)?.components == components)
    }

    @Test("rejects text without a version", arguments: ["", "dev", ".1", "v1.2", "1..2"])
    func rejects(text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test func ordersNumericallyNotAlphabetically() throws {
        #expect(try #require(AppVersion("1.10")) > #require(AppVersion("1.9")))
        #expect(try #require(AppVersion("1.2.9")) < #require(AppVersion("1.3")))
    }

    @Test func missingComponentsAreZero() throws {
        #expect(try #require(AppVersion("1.3")) == #require(AppVersion("1.3.0")))
        #expect(try #require(AppVersion("1.3.0.1")) > #require(AppVersion("1.3")))
    }
}
