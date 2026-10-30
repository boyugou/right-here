import Foundation
import Testing
@testable import RightHereCore

/// `ShellWords` decides whether a preset may start an agent, so what it reads is compared with what the shells that a person's terminal runs (zsh, which macOS makes the login shell, and bash)
/// really make of the same line: each shell is asked, once, for the words of every line (`set -- <line>` and the arguments that a program, `/usr/bin/printf`, receives).
@Suite("ShellWords against the real shells")
struct ShellWordsRealShellTests {
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

    private static let plain = ["abc", "--flag", "--flag=value", "-x", "a-b_c.d", "--dangerously-skip-permissions", "--approval-mode=yolo", "yolo", "A=1", "claude", "/usr/bin/claude", "Claude", "é", "日本"]
    private static let single = ["'a b'", "''", "'it'\\''s'", "'--flag'", "'a\\b'", "'$x'", "'`x`'", "'a\"b'", "'--dangerously-skip-permissions'"]
    private static let double = ["\"a b\"", "\"\"", "\"a\\\"b\"", "\"a\\\\b\"", "\"a\\$b\"", "\"a\\nb\"", "\"a\\`b\"", "\"--flag\"", "\"a'b\"", "\"--dangerously-skip-permissions\"", "\"a\\ b\"", "\"\\x41\""]
    private static let ansi = ["$'a\\tb'", "$'\\x41'", "$'\\101'", "$'\\u00e9'", "$'a\\'b'", "$'\\e'", "$'\\n'", "$'\\\\'", "$'--flag'", "$'\\x2d\\x2dflag'", "$'\\055\\055flag'", "$'\\U0001F600'", "$''",
                               "$'a\\\"b'", "$'\\?'", "$'\\a\\b\\f\\v\\r'", "$'\\1'", "$'\\u41'",
                               // what the two shells read differently, and what has a NUL: the reader must say it cannot read these
                               "$'\\q'", "$'\\cA'", "$'\\xg'", "$'\\u'", "$'\\0'", "$'\\08'", "$'\\x00'", "$'--\\dangerously-skip-permissions'"]
    private static let backslashes = ["a\\ b", "\\--flag", "a\\\\b", "\\'", "\\\"", "\\$", "a\\\nb", "\\a", "\\\\", "\\ "]
    /// What the shells compute from the line: braces (with a space inside, quoted, escaped or not a space to them), globs of the names in the folder that the lines run in (`in-0`, `out-0`), a
    /// no-break space, which is a character of a word, and octal escapes over \377, which are bytes. The reader has to say it cannot read the first three, and to read the others as the shells do.
    private static let computed = ["{--flag,' '}", "{a,b\\ c}", "{x,y}", "a{b,c}d", "{--flag,\"a b\"}", "{--flag,a\u{A0}b}", "*", "?", "[a-c]", "in-*", "out-?", "x*y", "--dangerously-skip-permission?"]
    private static let spaces = ["a\u{A0}b", "\u{3000}", "a\u{2009}b", "\u{A0}--flag"]
    private static let octal = ["$'\\455'", "$'\\455\\455flag'", "$'\\377'", "$'\\x2d'", "$'\\1055'", "$'\\60'"]

    private static func lines(count: Int, seed: UInt64) -> [String] {
        var random = SplitMix64(state: seed)
        let pieces = plain + single + double + ansi + backslashes + computed + spaces + octal
        func word(_ random: inout SplitMix64) -> String {
            (0..<[1, 1, 1, 2, 2, 3].randomElement(using: &random)!).map { _ in pieces.randomElement(using: &random)! }.joined()
        }
        var seen = Set<String>()
        var made: [String] = []
        while made.count < count {
            var line = word(&random)
            for _ in 0..<([0, 1, 1, 2, 3, 4].randomElement(using: &random)!) {
                line += [" ", " ", "  ", "\t"].randomElement(using: &random)! + word(&random)
            }
            if seen.insert(line).inserted { made.append(line) }
        }
        return made
    }

    /// The words that `shell` makes of each line, in the order of the lines; `nil` for a line it could not read.
    private static func words(of lines: [String], in shell: String) throws -> [[String]?] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rh-shellwords-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for (index, line) in lines.enumerated() {
            try line.write(to: folder.appendingPathComponent("in-\(index)"), atomically: false, encoding: .utf8)
        }
        let script = #"""
        cd "$1" || exit 2
        n=0
        while [ -f "in-$n" ]; do
          line=$(<"in-$n")
          ( eval "set -- $line" 2>/dev/null && /usr/bin/printf '%s\0' "$@" > "out-$n" ) || : > "err-$n"
          n=$((n + 1))
        done
        """#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", script, "shellwords", folder.path]
        process.currentDirectoryURL = folder
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return lines.indices.map { index in
            guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent("out-\(index)").path) else { return nil }
            let parts = data.split(separator: 0, omittingEmptySubsequences: false).dropLast()
            return parts.map { String(decoding: $0, as: UTF8.self) }
        }
    }

    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func theWordsOfALineAreTheOnesTheShellMakesOfIt(shell: String) throws {
        try #require(FileManager.default.isExecutableFile(atPath: shell), "\(shell) is part of macOS")
        // Only lines that the reader says it can read are put to the shell, so nothing that expands is ever evaluated.
        let readable = Self.lines(count: 1500, seed: 25).filter { !ShellWords.read($0).hasExpansion }
        // bash 3.2, the one macOS ships, keeps `\u` and `\U` as they are written; zsh and bash 4.2 and later decode them, as the reader does.
        let candidates = shell.hasSuffix("bash") ? readable.filter { !$0.contains("\\u") && !$0.contains("\\U") } : readable
        #expect(candidates.count > 400, "too few lines were readable to say anything: \(candidates.count)")
        let made = try Self.words(of: candidates, in: shell)
        var differences: [String] = []
        for (line, theirs) in zip(candidates, made) {
            let ours = ShellWords.split(line)
            if let theirs, theirs != ours { differences.append("\(line.debugDescription)\n   read as \(ours)\n   \(shell) makes \(theirs)") }
            if theirs == nil { differences.append("\(line.debugDescription) was not read by \(shell) at all") }
        }
        #expect(differences.isEmpty, Comment(rawValue: "\(differences.count) of \(candidates.count) lines differ; the first: " + differences.prefix(3).joined(separator: "\n")))
    }
}
