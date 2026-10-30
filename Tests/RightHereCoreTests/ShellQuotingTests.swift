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

let fishPath: String? = ["/opt/homebrew/bin/fish", "/usr/local/bin/fish"].first(where: FileManager.default.isExecutableFile)

/// Marks that join the character before them into one grapheme cluster. A shell does not know about
/// grapheme clusters: it still sees the quote or the semicolon underneath.
private let joiningMarks: [String] = ["\u{301}", "\u{308}", "\u{FE0F}", "\u{FE0E}", "\u{200D}", "\u{20E3}", "\u{1F3FB}", "\u{0E31}", "\u{0915}\u{094D}"]
private let shellMetacharacters: [String] = "'\"\\$`;&|<>(){}[]*?!#~ =%^".map { String($0) } + ["\t", "\n", "\r", "\\'"]

/// Every metacharacter directly followed by every joining mark, in the middle of ordinary text.
private let markedWords: [String] = shellMetacharacters.flatMap { meta in
    joiningMarks.map { mark in "a" + meta + mark + "b" }
}

/// A deterministic generator, so a failing fuzz case can be replayed.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func fuzzWords(count: Int, seed: UInt64) -> [String] {
    var random = SplitMix64(state: seed)
    let pieces: [String] = shellMetacharacters + joiningMarks + ["a", "b", "z", "0", "-", "/", ".", "日", "é", "🚀", "\u{A0}", "\u{3000}", "touch CANARY"]
    return (0..<count).map { _ in
        (0..<Int.random(in: 1...12, using: &random)).map { _ in pieces.randomElement(using: &random)! }.joined()
    }
}

@Suite("ShellQuoting with joining marks")
struct ShellQuotingJoiningMarkTests {
    @Test func aQuoteFollowedByACombiningMarkCannotEscapeTheQuoting() throws {
        let directory = try makeScratchDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let hostile = "ab'\u{301};touch CANARY;'"
        for shell in ["/bin/sh", "/bin/bash", "/bin/zsh"] {
            #expect(try Shell.run(shell, "printf %s " + ShellQuoting.quote(hostile), in: directory) == hostile)
            #expect(try Shell.run(shell, "printf %s " + ShellQuoting.backslashEscape(hostile), in: directory) == hostile)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("CANARY").path))
    }

    @Test("every metacharacter followed by every joining mark round-trips",
          arguments: ["/bin/sh", "/bin/bash", "/bin/zsh"])
    func marksAfterMetacharacters(shell: String) throws {
        let directory = try makeScratchDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let output = try Shell.run(shell, "printf '%s\\0' " + markedWords.map { ShellQuoting.quote($0) }.joined(separator: " "), in: directory)
        #expect(output.split(separator: "\0", omittingEmptySubsequences: false).dropLast().map(String.init) == markedWords)
        let escaped = try Shell.run(shell, "printf '%s\\0' " + markedWords.map(ShellQuoting.backslashEscape).joined(separator: " "), in: directory)
        #expect(escaped.split(separator: "\0", omittingEmptySubsequences: false).dropLast().map(String.init) == markedWords)
    }

    @Test("random awkward words never break out, in three shells and two quoting styles", arguments: [1, 2, 3, 4, 5])
    func fuzz(seed: Int) throws {
        let directory = try makeScratchDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        // Words with a bare CR or LF survive printf but not a line-based split, so compare as NUL-separated records.
        let words = fuzzWords(count: 120, seed: UInt64(seed))
        for shell in ["/bin/sh", "/bin/bash", "/bin/zsh"] {
            for style in [ShellQuoting.quote(_:for:), { (word: String, _: ShellFlavor) in ShellQuoting.backslashEscape(word) }] {
                let command = "printf '%s\\0' " + words.map { style($0, .posix) }.joined(separator: " ")
                let output = try Shell.run(shell, command, in: directory)
                #expect(output.split(separator: "\0", omittingEmptySubsequences: false).dropLast().map(String.init) == words, "seed \(seed), \(shell)")
            }
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("CANARY").path), "seed \(seed) ran an injected command")
    }

    @Test func scalarReplacingSeesThroughJoiningMarks() {
        #expect("a'\u{301}b".scalarReplacing(["'": "Q"]) == "aQ\u{301}b")
        #expect("a'\u{301}b".replacingOccurrences(of: "'", with: "Q") == "a'\u{301}b", "Foundation hides the quote; that is why we do not use it here")
        let keycap: Set<Unicode.Scalar> = ["\u{20E3}"]
        let slash: Set<Unicode.Scalar> = ["/"]
        #expect("x\u{20E3}".containsAnyScalar(of: keycap))
        #expect(!"plain".containsAnyScalar(of: slash))
    }

    @Test func theMCPFenceMarkersCannotBeHiddenEither() {
        #expect("⟧\u{301}x".scalarReplacing(["⟦": "[", "⟧": "]"]) == "]\u{301}x")
    }

    @Test func aServiceTitleCannotSmuggleASlashIntoAFileName() {
        let spec = ServiceSpec(title: "A/\u{301}B:\u{301}C", actionID: "open.terminal", command: "x")
        let name = ServiceWorkflow.bundleName(for: spec)
        #expect(!name.unicodeScalars.contains("/"))
        #expect(!name.unicodeScalars.contains(":"))
    }
}

func makeScratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rh-quote-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

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

    @Test("fish quoting reads back unchanged (skipped where fish is not installed)",
          .enabled(if: fishPath != nil), arguments: awkwardWords + markedWords)
    func fishRoundTrip(word: String) throws {
        let fish = try #require(fishPath)
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

/// The environment a test shell gets: an empty home and no startup variables, so the person's own `.zshenv`, `.profile`
/// or `$ENV` never run during `swift test` (they may be slow, noisy or do things).
func emptyHomeEnvironment() -> [String: String] {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("rh-empty-home", isDirectory: true)
    try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    var environment = ProcessInfo.processInfo.environment
    for name in ["ENV", "BASH_ENV", "ZDOTDIR", "SHELL"] { environment.removeValue(forKey: name) }
    environment["HOME"] = home.path
    environment["ZDOTDIR"] = home.path
    return environment
}

/// Runs a shell command line and returns its standard output.
enum Shell {
    static func run(_ shell: String, _ command: String, in directory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", command]
        process.currentDirectoryURL = directory
        process.environment = emptyHomeEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
