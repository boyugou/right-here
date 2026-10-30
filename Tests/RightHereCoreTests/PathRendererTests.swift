import Foundation
import Testing
@testable import RightHereCore

private func facts(gitRoots: [String] = ["/Users/tester/code/app"]) -> FakeSystemFacts {
    FakeSystemFacts(
        directories: ["/Users/tester", "/Users/tester/code/app", "/Users/tester/code/app/src", "/Volumes/Data"],
        files: ["/Users/tester/code/app/src/main.swift", "/Users/tester/code/app/My Notes.md", "/Volumes/Data/x.txt"],
        gitRoots: gitRoots
    )
}

@Suite("PathRenderer")
struct PathRendererTests {
    private let nested = URL(fileURLWithPath: "/Users/tester/code/app/src/main.swift")
    private let spaced = URL(fileURLWithPath: "/Users/tester/code/app/My Notes.md")
    private let outside = URL(fileURLWithPath: "/Volumes/Data/x.txt")

    @Test func theNameOfTheRootFolderIsASlashNotNothing() {
        let root = URL(fileURLWithPath: "/")
        #expect(PathRenderer(facts: facts()).render(root, style: .name) == "/")
        #expect(PathRenderer(facts: facts()).render(root, style: .markdownLink) == "[/](/)")
    }

    @Test func absolute() {
        #expect(PathRenderer(facts: facts()).render(nested, style: .absolute) == "/Users/tester/code/app/src/main.swift")
    }

    @Test func tildeInsideAndOutsideHome() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render(nested, style: .tilde) == "~/code/app/src/main.swift")
        #expect(renderer.render(URL(fileURLWithPath: "/Users/tester"), style: .tilde) == "~")
        #expect(renderer.render(outside, style: .tilde) == "/Volumes/Data/x.txt")
    }

    @Test("tilde works however the first component after the home folder begins", arguments: ["\u{301}notes.txt", "e\u{301}/x", "plain/\u{301}", "a b/c"])
    func tildeSeesThroughACombiningMarkAfterTheSlash(rest: String) {
        let url = URL(fileURLWithPath: "/Users/tester/" + rest)
        #expect(PathRenderer(facts: facts()).render(url, style: .tilde) == "~/" + rest)
    }

    @Test func tildeDoesNotMatchSiblingWithSamePrefix() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render(URL(fileURLWithPath: "/Users/tester2/file"), style: .tilde) == "/Users/tester2/file")
    }

    @Test func gitRelative() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render(nested, style: .gitRelative) == "src/main.swift")
        #expect(renderer.render(URL(fileURLWithPath: "/Users/tester/code/app"), style: .gitRelative) == ".")
        #expect(renderer.render(outside, style: .gitRelative) == "/Volumes/Data/x.txt")
    }

    @Test func gitRelativeFallsBackToAbsoluteWithoutRepository() {
        let renderer = PathRenderer(facts: facts(gitRoots: []))
        #expect(renderer.render(nested, style: .gitRelative) == "/Users/tester/code/app/src/main.swift")
    }

    @Test func nameAndParent() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render(spaced, style: .name) == "My Notes.md")
        #expect(renderer.render(spaced, style: .parent) == "/Users/tester/code/app")
    }

    @Test func shellStyles() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render(spaced, style: .shellEscaped) == "/Users/tester/code/app/My\\ Notes.md")
        #expect(renderer.render(spaced, style: .shellQuoted) == "'/Users/tester/code/app/My Notes.md'")
    }

    @Test("a shell-quoted path reads the same in every shell, whichever shell the person logs in with", arguments: [
        #"x\'; touch CANARY #"#, #"back\slash"#, "it's", #"a\"#, "plain", "with space", "a'b'c", #"q"uo"te"#, "dollar $HOME `x`", "tab\there", "ünï\u{301}", "-dash"
    ])
    func shellQuotedIsIndependentOfTheLoginShell(name: String) throws {
        let url = URL(fileURLWithPath: "/tmp/" + name)
        let zsh = PathRenderer(facts: FakeSystemFacts(loginShell: "/bin/zsh")).render(url, style: .shellQuoted)
        let fish = PathRenderer(facts: FakeSystemFacts(loginShell: "/opt/homebrew/bin/fish")).render(url, style: .shellQuoted)
        #expect(zsh == fish, "the text changed with the login shell")
        // And the same text, read by the shells that are here, gives the path back (a canary file would appear if a
        // name could break out).
        for shell in ["/bin/sh", "/bin/bash", "/bin/zsh"] + (fishPath.map { [$0] } ?? []) {
            #expect(try Shell.run(shell, "printf %s " + zsh) == "/tmp/" + name, "\(shell) read \(zsh.debugDescription) differently")
        }
    }

    @Test func aPathWithABackslashIsBackslashEscapedAndOtherPathsAreSingleQuoted() {
        // Fish reads a backslash inside single quotes as an escape and the other shells do not, so the one form every shell reads alike is the backslash-escaped one for such a name.
        // (The round trip above is the oracle where fish is installed; this pins the choice where it is not.)
        let renderer = PathRenderer(facts: FakeSystemFacts())
        #expect(renderer.render(URL(fileURLWithPath: "/tmp/back\\slash"), style: .shellQuoted) == "/tmp/back\\\\slash")
        #expect(renderer.render(URL(fileURLWithPath: "/tmp/plain name"), style: .shellQuoted) == "'/tmp/plain name'")
    }

    @Test("a name with both a backslash and a control character has no shell form that every shell reads alike", arguments: [PathStyle.shellEscaped, .shellQuoted])
    func backslashPlusControlCharacterIsRefused(style: PathStyle) throws {
        let hostile = URL(fileURLWithPath: "/tmp/a\\';touch\tpwned;\\'")
        #expect(PathRenderer.shellFormRefusal(for: [hostile], style: style) != nil)
        // Either one alone has a form every shell agrees on.
        for fine in ["/tmp/back\\slash", "/tmp/tab\there", "/tmp/it's", "/tmp/plain"] {
            #expect(PathRenderer.shellFormRefusal(for: [URL(fileURLWithPath: fine)], style: style) == nil, "\(fine)")
        }
        // The other styles are plain text, not shell syntax.
        for other in [PathStyle.absolute, .name, .tilde, .fileURL, .markdownLink, .aiMention] {
            #expect(PathRenderer.shellFormRefusal(for: [hostile], style: other) == nil)
        }
        let machine = FakeSystemFacts(files: [hostile.path])
        #expect(throws: PlanError.self) {
            try Planner(facts: machine).plan(.copyPath(style), context: HereContext(origin: .items, items: [hostile]))
        }
        #expect(try Planner(facts: machine).plan(.copyPath(.absolute), context: HereContext(origin: .items, items: [hostile])).steps.count == 1)
    }

    @Test func fileURL() {
        #expect(PathRenderer(facts: facts()).render(spaced, style: .fileURL) == "file:///Users/tester/code/app/My%20Notes.md")
    }

    @Test func aiMention() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render(nested, style: .aiMention) == "@src/main.swift")
        #expect(renderer.render(spaced, style: .aiMention) == "@\"My Notes.md\"")
        #expect(renderer.render(outside, style: .aiMention) == "@/Volumes/Data/x.txt")
    }

    @Test func markdownLink() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render(nested, style: .markdownLink) == "[main.swift](src/main.swift)")
        #expect(renderer.render(spaced, style: .markdownLink) == "[My Notes.md](<My Notes.md>)")
    }

    @Test("a link or mention made from a hostile name stays one link or one mention", arguments: [
        ("a]b (1).md", "[a\\]b (1).md](<a]b (1).md>)"),
        ("x*y_z.md", "[x\\*y\\_z.md](x*y_z.md)"),
        ("a)b.md", "[a)b.md](<a)b.md>)"),
        ("<b>.md", "[\\<b\\>.md](<\\<b\\>.md>)"),
        ("t`k.md", "[t\\`k.md](t`k.md)"),
        ("a&amp;b.md", "[a\\&amp;b.md](a&amp;b.md)"),
        ("back\\slash.md", "[back\\\\slash.md](<back\\\\slash.md>)"),
        ("line\nbreak.md", "[line\nbreak.md](<line%0Abreak.md>)")
    ])
    func markdownLinkEscapes(name: String, expected: String) {
        var machine = facts()
        machine.files.insert("/Users/tester/code/app/" + name)
        let url = URL(fileURLWithPath: "/Users/tester/code/app/" + name)
        #expect(PathRenderer(facts: machine).render(url, style: .markdownLink) == expected.replacingOccurrences(of: "\u{1}", with: ""))
    }

    @Test("a quote or backslash in a mention cannot end it early", arguments: [
        ("a \"b\".md", "@\"a \\\"b\\\".md\""),
        ("a\\ b.md", "@\"a\\\\ b.md\""),
        ("plain.md", "@plain.md"),
        ("q\"uote.md", "@q\"uote.md"),
        ("a \u{301}b.md", "@\"a \u{301}b.md\"")
    ])
    func mentionEscapes(name: String, expected: String) {
        let url = URL(fileURLWithPath: "/Users/tester/code/app/" + name)
        #expect(PathRenderer(facts: facts()).render(url, style: .aiMention) == expected)
    }

    @Test func severalItemsJoinPerStyle() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render([nested, spaced], style: .name) == "main.swift\nMy Notes.md")
        #expect(renderer.render([nested, spaced], style: .aiMention) == "@src/main.swift @\"My Notes.md\"")
        #expect(renderer.render([nested, spaced], style: .shellEscaped)
                == "/Users/tester/code/app/src/main.swift /Users/tester/code/app/My\\ Notes.md")
    }

    @Test func standardizesDotComponents() {
        let url = URL(fileURLWithPath: "/Users/tester/code/app/src/../src/./main.swift")
        #expect(PathRenderer(facts: facts()).render(url, style: .absolute) == "/Users/tester/code/app/src/main.swift")
    }

    @Test func repositoryAtHomeIsIgnored() {
        let renderer = PathRenderer(facts: facts(gitRoots: ["/Users/tester"]))
        #expect(renderer.render(nested, style: .gitRelative) == "/Users/tester/code/app/src/main.swift")
    }

    @Test func nestedRepositoryWinsOverOuter() {
        let renderer = PathRenderer(facts: facts(gitRoots: ["/Users/tester/code", "/Users/tester/code/app"]))
        #expect(renderer.render(nested, style: .gitRelative) == "src/main.swift")
    }
}

@Suite("Paths are copied as the file system stores them")
struct OnDiskSpellingTests {
    // The URL spelling decomposes the accent; the disk keeps the precomposed é.
    private static let typed = "/Users/tester/code/cafe\u{301}/Readme.md"
    private static let stored = "/Users/tester/code/caf\u{e9}/README.md"

    private func facts() -> FakeSystemFacts {
        FakeSystemFacts(gitRoots: ["/Users/tester/code"], diskPaths: [URL(fileURLWithPath: Self.typed).lexicallyNormalized.path: Self.stored])
    }

    @Test("every style spells the names as stored", arguments: [
        (PathStyle.absolute, stored), (.name, "README.md"), (.parent, "/Users/tester/code/caf\u{e9}"),
        (.tilde, "~/code/caf\u{e9}/README.md"), (.gitRelative, "caf\u{e9}/README.md"),
        (.shellQuoted, "'" + stored + "'"), (.aiMention, "@caf\u{e9}/README.md"),
        (.fileURL, "file:///Users/tester/code/caf%C3%A9/README.md")
    ])
    func spelledAsStored(style: PathStyle, expected: String) {
        #expect(PathRenderer(facts: facts()).render(URL(fileURLWithPath: Self.typed), style: style) == expected)
    }
}

