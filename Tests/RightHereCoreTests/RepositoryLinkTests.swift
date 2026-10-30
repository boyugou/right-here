import Foundation
import Testing
@testable import RightHereCore

@Suite("RepositoryLink")
struct RepositoryLinkTests {
    private let commit = "d89f86032883bae7ef136d543343639777e2455a"
    /// Remotes with a user name are written in pieces, so that this file holds nothing that reads as an email address.
    private static let at = "@"

    private func remote(_ text: String) -> RepositoryRemote? {
        try? RepositoryLink.parse(remote: text).get()
    }

    @Test(arguments: [
        "https://github.com/owner/repo.git", "https://github.com/owner/repo", "https://github.com/owner/repo/", "http://github.com/owner/repo",
        "git@github.com:owner/repo.git", "ssh://git@github.com/owner/repo.git", "ssh://git@github.com:22/owner/repo.git",
        "git://github.com/owner/repo.git", "  https://GitHub.com/owner/repo.git\n".trimmingCharacters(in: .newlines),
    ])
    func theFormsOfARemoteGiveTheSameRepository(text: String) {
        #expect(remote(text) == RepositoryRemote(host: .github, path: ["owner", "repo"]))
    }

    @Test func aUserNameOrAPasswordInTheRemoteNeverReachesTheLink() throws {
        let parsed = try #require(remote("https://someone:s3cr3t-token" + Self.at + "github.com/owner/repo.git"))
        let link = try #require(RepositoryLink.url(remote: parsed, commit: commit, itemPath: ["a.txt"], isDirectory: false))
        #expect(link == "https://github.com/owner/repo/blob/\(commit)/a.txt")
        #expect(!link.contains("s3cr3t") && !link.contains("someone"))
    }

    @Test(arguments: ["ext::sh -c touch% /tmp/x", "file:///etc/repo.git", "/Users/tester/repo.git", "../repo", "ftp://github.com/owner/repo",
                      "https://github.com", "https://github.com/owner", "https://github.com/owner/repo/extra", "https://github.com/../repo",
                      "https://github.com/owner/re po", "https://github.com/owner/%2e%2e", "https://github.com/owner/repo\u{0}x", ""])
    func whatIsNotARepositoryOnAHostIsRefused(text: String) {
        #expect(throws: RepositoryLinkError.self) { try RepositoryLink.parse(remote: text).get() }
    }

    /// The name of another host is shown in a refusal, so only what reads as a host name is: what is left of a token after its "@" was
    /// taken for the end of the user part, or a host with a space, is not repeated.
    @Test func whatIsNotAHostNameIsNotShownAsOne() {
        // Without a scheme, git reads everything before the first ":" as the host (`host:path`).
        #expect(RepositoryLink.parse(remote: "ghp_TOKEN123:x-oauth" + Self.at + "github.com/owner/repo") == .failure(.unreadableRemote))
        #expect(RepositoryLink.parse(remote: "https://ghp_TOKEN123:x-oauth/owner/repo") == .failure(.unreadableRemote))
        #expect(RepositoryLink.parse(remote: "https://user:12345/abc" + Self.at + "github.com/owner/repo") != .failure(.unknownHost("user")))
        #expect(RepositoryLink.parse(remote: "https://github .com/owner/repo") == .failure(.unreadableRemote))
        #expect(RepositoryLink.parse(remote: "https://localhost/owner/repo") == .failure(.unreadableRemote))
    }

    /// GitLab's `/-/` starts the part of a URL that names a page: a remote whose path has such a segment is not a repository's.
    @Test func aSegmentThatStartsWithADashIsRefusedAndAnyCaseOfGitIsDropped() {
        #expect(RepositoryLink.parse(remote: "https://gitlab.com/g/s/r/-/tree") == .failure(.unreadableRemote))
        #expect(RepositoryLink.parse(remote: "https://github.com/-owner/repo") == .failure(.unreadableRemote))
        #expect(remote("https://github.com/owner/repo.GIT") == RepositoryRemote(host: .github, path: ["owner", "repo"]))
    }

    @Test func aTransportPrefixIsNotAHost() {
        #expect(RepositoryLink.parse(remote: "ext::sh -c touch% /tmp/x") == .failure(.unreadableRemote))
        #expect(RepositoryLink.parse(remote: "fd::17") == .failure(.unreadableRemote))
    }

    @Test func anotherHostIsNamedInTheRefusal() {
        #expect(RepositoryLink.parse(remote: "git" + Self.at + "git.example.com:team/repo.git") == .failure(.unknownHost("git.example.com")))
        #expect(RepositoryLink.parse(remote: "https://user" + Self.at + "GHE.Corp.example:8443/team/repo") == .failure(.unknownHost("ghe.corp.example")))
    }

    @Test func gitLabGroupsMayNest() throws {
        let parsed = try #require(remote("git" + Self.at + "gitlab.com:group/sub/repo.git"))
        #expect(parsed.path == ["group", "sub", "repo"])
        #expect(RepositoryLink.url(remote: parsed, commit: commit, itemPath: ["doc"], isDirectory: true)
                == "https://gitlab.com/group/sub/repo/-/tree/\(commit)/doc")
    }

    @Test func eachHostHasItsFormForAFileAFolderAndTheRoot() throws {
        let cases: [(String, String, String, String)] = [
            ("https://github.com/o/r", "/blob/\(commit)/src/a.swift", "/tree/\(commit)/src", "/tree/\(commit)"),
            ("https://gitlab.com/o/r", "/-/blob/\(commit)/src/a.swift", "/-/tree/\(commit)/src", "/-/tree/\(commit)"),
            ("https://codeberg.org/o/r", "/src/commit/\(commit)/src/a.swift", "/src/commit/\(commit)/src", "/src/commit/\(commit)"),
            ("https://bitbucket.org/o/r", "/src/\(commit)/src/a.swift", "/src/\(commit)/src", "/src/\(commit)/"),
        ]
        for (text, file, folder, root) in cases {
            let parsed = try #require(remote(text))
            let base = "https://\(parsed.host.rawValue)/o/r"
            #expect(RepositoryLink.url(remote: parsed, commit: commit, itemPath: ["src", "a.swift"], isDirectory: false) == base + file)
            #expect(RepositoryLink.url(remote: parsed, commit: commit, itemPath: ["src"], isDirectory: true) == base + folder)
            #expect(RepositoryLink.url(remote: parsed, commit: commit, itemPath: [], isDirectory: true) == base + root)
        }
    }

    @Test func aDecomposedNameIsLinkedAsThePrecomposedOneGitKeeps() throws {
        let parsed = try #require(remote("https://github.com/o/r"))
        let decomposed = "e\u{301}t\u{E9}.md".decomposedStringWithCanonicalMapping
        #expect(decomposed.unicodeScalars.count == 8)  // e, U+0301, t, e, U+0301, ., m, d
        #expect(RepositoryLink.url(remote: parsed, commit: commit, itemPath: [decomposed], isDirectory: false)
                == "https://github.com/o/r/blob/\(commit)/%C3%A9t%C3%A9.md")
    }

    @Test func charactersThatEndOrSplitAURLAreEncoded() throws {
        let parsed = try #require(remote("https://github.com/o/r"))
        #expect(RepositoryLink.url(remote: parsed, commit: commit, itemPath: ["a b#c?d%e&f"], isDirectory: false)
                == "https://github.com/o/r/blob/\(commit)/a%20b%23c%3Fd%25e%26f")
    }

    @Test func onlyAFullCommitHashMakesALink() throws {
        let parsed = try #require(remote("https://github.com/o/r"))
        #expect(RepositoryLink.url(remote: parsed, commit: String(commit.prefix(7)), itemPath: [], isDirectory: true) == nil)
        #expect(RepositoryLink.url(remote: parsed, commit: "main", itemPath: [], isDirectory: true) == nil)
        #expect(RepositoryLink.url(remote: parsed, commit: commit.uppercased(), itemPath: [], isDirectory: true) == nil)
        #expect(RepositoryLink.url(remote: parsed, commit: String(repeating: "a", count: 64), itemPath: [], isDirectory: true) != nil)
        #expect(RepositoryLink.url(remote: parsed, commit: commit, itemPath: ["a", ""], isDirectory: true) == nil)
    }

    @Test func everyLinkIsHTTPSOnTheParsedHost() throws {
        for text in ["git@github.com:o/r.git", "ssh://git" + Self.at + "gitlab.com/o/r.git", "git://codeberg.org/o/r", "http://bitbucket.org/o/r"] {
            let parsed = try #require(remote(text))
            let link = try #require(RepositoryLink.url(remote: parsed, commit: commit, itemPath: ["x"], isDirectory: false))
            #expect(link.hasPrefix("https://\(parsed.host.rawValue)/o/r/"))
        }
    }
}
