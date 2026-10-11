import Foundation
import Testing
@testable import RightHereCore

private let awkwardWords: [String] = [
    "plain",
    "with space",
    "it's",
    "say \"hi\"",
    "$HOME and `date` and $(id)",
    "back\\slash",
    "trailing backslash\\",
    "star*?[glob]",
    "bang!history",
    "semi;colon && pipe | redirect > file",
    "~tilde",
    "-leading-dash",
    "=equals",
    "%percent",
    "日本語 パス",
    "emoji 🚀 folder",
    "tab\there",
    "new\nline",
    "carriage\rreturn",
    "a'b'c'd",
    "''",
    "#hash",
    "{braces}",
    "(parens)"
]

@Suite("ShellQuoting")
struct ShellQuotingTests {
    @Test("bare-safe words stay bare", arguments: ["abc", "/usr/local/bin", "a-b_c.d", "user@host:1,2+3"])
    func bareWords(word: String) {
        #expect(ShellQuoting.quote(word) == word)
    }

    @Test func emptyIsQuoted() {
        #expect(ShellQuoting.quote("") == "''")
    }

    @Test func posixEmbeddedQuote() {
        #expect(ShellQuoting.quote("it's") == "'it'\\''s'")
    }

    @Test func fishEscapesBackslashAndQuote() {
        #expect(ShellQuoting.quote("a\\b'c", for: .fish) == "'a\\\\b\\'c'")
    }

    @Test("a real POSIX shell reads every quoted word back unchanged",
          arguments: ["/bin/sh", "/bin/bash", "/bin/zsh"], awkwardWords)
    func roundTrip(shell: String, word: String) throws {
        try #require(FileManager.default.isExecutableFile(atPath: shell))
        let command = "printf %s " + ShellQuoting.quote(word)
        #expect(try Shell.run(shell, command) == word)
    }

    @Test("a real shell reads backslash-escaped words back unchanged",
          arguments: ["/bin/sh", "/bin/zsh"], awkwardWords)
    func backslashRoundTrip(shell: String, word: String) throws {
        let command = "printf %s " + ShellQuoting.backslashEscape(word)
        #expect(try Shell.run(shell, command) == word)
    }

    @Test func joinQuotesEachWord() throws {
        let words = ["cd", "my dir", "it's"]
        #expect(ShellQuoting.join(words) == "cd 'my dir' 'it'\\''s'")
        #expect(try Shell.run("/bin/sh", "printf '%s|' " + ShellQuoting.join(words)) == "cd|my dir|it's|")
    }

    @Test("fish quoting reads back unchanged when fish is installed", arguments: awkwardWords)
    func fishRoundTrip(word: String) throws {
        let candidates = ["/opt/homebrew/bin/fish", "/usr/local/bin/fish"]
        guard let fish = candidates.first(where: FileManager.default.isExecutableFile) else { return }
        let command = "printf %s " + ShellQuoting.quote(word, for: .fish)
        #expect(try Shell.run(fish, command) == word)
    }

    @Test("typing rejects line breaks and control characters",
          arguments: ["a\nb", "a\rb", "a\tb", "a\u{1B}[31mb", "a\u{7}b", "a\u{2028}b", "a\u{2029}b", "a\u{0}b"])
    func typingRejects(word: String) {
        #expect(throws: ShellQuotingError.self) { try ShellQuoting.validateForTyping(word) }
    }

    @Test("typing accepts ordinary text including spaces, quotes and unicode",
          arguments: ["plain", "with space", "it's", "日本語", "emoji 🚀"])
    func typingAccepts(word: String) throws {
        try ShellQuoting.validateForTyping(word)
    }

    @Test func loginShellFlavor() {
        #expect(ShellFlavor(loginShellPath: "/bin/zsh") == .posix)
        #expect(ShellFlavor(loginShellPath: "/opt/homebrew/bin/fish") == .fish)
    }
}

/// Runs a shell command line and returns its standard output.
enum Shell {
    static func run(_ shell: String, _ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
