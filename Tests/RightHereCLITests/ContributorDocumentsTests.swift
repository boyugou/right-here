import Foundation
import Testing

/// What a contributor is told, against what is there: the counts and symbols the documents name exist in the sources, and the gate says
/// what it needs before its slow steps. Nothing here touches the real home: the scripts run in a temporary copy of the repository's
/// `script/` folder with stand-ins for `swift`, `uv` and `xcodegen`.
@Suite("Contributor documents and scripts")
struct ContributorDocumentsTests {
    private static var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent(path), encoding: .utf8)
    }

    /// DESIGN.md says what the MCP server offers: "(eight tools, ...)". `rh docs mcp` lists what it offers.
    @Test func designSaysHowManyToolsTheMCPServerHas() throws {
        let design = try Self.read("docs/DESIGN.md")
        let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
                     "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14]
        let match = try #require(design.range(of: #"\((\w+) tools"#, options: .regularExpression), "DESIGN.md no longer counts the tools")
        let word = design[match].dropFirst().split(separator: " ").first.map(String.init) ?? ""
        let claimed = try #require(words[word.lowercased()] ?? Int(word), "cannot read the number '\(word)'")

        let tools = try Self.read("Sources/RightHereMCP/Tools.swift")
        let offered = tools.components(separatedBy: "name: \"right_here_").count - 1
        #expect(offered > 0, "could not count the tools in Tools.swift")
        #expect(claimed == offered, "DESIGN.md says \(claimed) tools; the server defines \(offered)")
    }

    /// RELEASING.md step 2 says where the version is raised: "`Sources/rh/RH.swift` (`RightHereInfo.version`)". Every
    /// `Type.member` the release steps name must exist in the sources.
    @Test func theReleaseStepsNameSymbolsThatExist() throws {
        let releasing = try Self.read("docs/development/RELEASING.md")
        var sources = ""
        for folder in ["Sources", "Apps"] {
            let enumerator = FileManager.default.enumerator(at: Self.repository.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "swift" { sources += (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
            }
        }
        let pattern = try NSRegularExpression(pattern: #"`([A-Z][a-z][A-Za-z0-9]+)\.[a-z][A-Za-z0-9]*`"#)  // a type and a member, not CHANGELOG.md
        let range = NSRange(releasing.startIndex..., in: releasing)
        let names = Set(pattern.matches(in: releasing, range: range).compactMap { Range($0.range(at: 1), in: releasing).map { String(releasing[$0]) } })
        #expect(!names.isEmpty)
        for name in names.sorted() {
            let declared = ["enum", "struct", "class", "actor", "extension", "typealias"].contains { sources.contains("\($0) \(name)") }
            #expect(declared, "RELEASING.md names `\(name)`, which no Swift file declares")
        }
    }

    // MARK: the gate

    /// A temporary copy of `script/verify_all.sh` and `script/build_app.sh`, with stand-ins that record that they were started.
    private struct Gate {
        let root: URL
        let stubs: URL
        var marker: URL { root.appendingPathComponent("started.log") }

        init(stubbing names: [String]) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("rh-gate-\(UUID().uuidString)")
            stubs = root.appendingPathComponent("stubs")
            let scripts = root.appendingPathComponent("script")
            for folder in [stubs, scripts] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            for name in ["verify_all.sh", "build_app.sh"] {
                try FileManager.default.copyItem(at: ContributorDocumentsTests.repository.appendingPathComponent("script/\(name)"),
                                                 to: scripts.appendingPathComponent(name))
            }
            // The public-safety check is not what is being tested.
            try write("#!/bin/bash\nexit 0\n", to: scripts.appendingPathComponent("verify_public_safety.sh"))
            for name in names {
                try write("#!/bin/bash\necho \"\(name) $*\" >> \"\(marker.path)\"\nexit 0\n", to: stubs.appendingPathComponent(name))
            }
        }

        private func write(_ text: String, to url: URL) throws {
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }

        var started: String { (try? String(contentsOf: marker, encoding: .utf8)) ?? "" }

        /// Runs the gate with `PATH` of only the stand-ins and the system's folders, and no usable Xcode.
        func run() throws -> (status: Int32, error: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [root.appendingPathComponent("script/verify_all.sh").path]
            process.currentDirectoryURL = root
            process.environment = [
                "PATH": "\(stubs.path):/usr/bin:/bin",
                "HOME": root.path,
                // What a Mac with only the Command Line Tools looks like to `/usr/bin/xcodebuild`: the shim is there and refuses.
                "DEVELOPER_DIR": root.appendingPathComponent("no-xcode").path,
                "SIGN_IDENTITY": "-"
            ]
            let err = Pipe()
            process.standardOutput = Pipe()
            process.standardError = err
            try process.run()
            let data = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }
    }

    /// `verify_all.sh` builds the app only `if command -v xcodegen && command -v xcodebuild`, and otherwise prints a note and goes on.
    /// On a Mac with only the Command Line Tools `/usr/bin/xcodebuild` exists (it is the `xcode-select` shim) and fails with
    /// "requires Xcode", so the condition is true, `build_app.sh` (whose `need xcodebuild` is the same test) runs and the gate stops
    /// with "Build did not produce ..." after the build and the tests, and the "note" branch can never run on a Mac.
    @Test func theGateSkipsTheAppBuildWhenXcodeCannotBuildIt() throws {
        let gate = try Gate(stubbing: ["swift", "uv", "xcodegen"]); defer { gate.cleanUp() }
        let result = try gate.run()
        #expect(result.status == 0, "verify_all.sh stopped (exit \(result.status)): \(result.error)")
        #expect(!gate.started.contains("xcodegen generate"), "the app build was attempted although xcodebuild cannot run")
    }

    /// CONTRIBUTING.md lists `uv` among the things that are "optional but useful" and then says to run `verify_all.sh` before a pull
    /// request, which runs `uv run` six times under `set -e`. A contributor without `uv` is told only after the build and the tests.
    @Test func theGateSaysUpFrontThatItNeedsUV() throws {
        let gate = try Gate(stubbing: ["swift"]); defer { gate.cleanUp() }
        let result = try gate.run()
        #expect(result.status != 0)
        #expect(result.error.contains("uv"), "the failure does not name uv: \(result.error)")
        #expect(!gate.started.contains("swift build"), "the slow steps ran before the missing tool was noticed: \(gate.started)")
    }

    /// `verify_public_safety.sh` read only `git ls-files`, so a new file passed until it was staged: run before `git add`, the check said
    /// "ok" about a file that the next commit published. A file that is not ignored is checked whether or not it is tracked yet.
    @Test func thePublicSafetyCheckReadsFilesThatAreNotStagedYet() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rh-safety-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let scripts = root.appendingPathComponent("script")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.repository.appendingPathComponent("script/verify_public_safety.sh"),
                                         to: scripts.appendingPathComponent("verify_public_safety.sh"))
        func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, error: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = root
            process.environment = ["PATH": "/usr/bin:/bin", "HOME": root.path, "GIT_CONFIG_NOSYSTEM": "1"]
            let err = Pipe()
            process.standardOutput = Pipe()
            process.standardError = err
            try process.run()
            let data = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }
        #expect(try run("/usr/bin/git", ["init", "-q"]).status == 0)
        // The copy of the script is not what is being checked (its list of names needs uv, which this PATH does not have).
        try Data("script/\n".utf8).write(to: root.appendingPathComponent(".gitignore"))
        try Data("# Notes\n".utf8).write(to: root.appendingPathComponent("notes.md"))
        let clean = try run("/bin/bash", ["script/verify_public_safety.sh"])
        #expect(!clean.error.contains("email address found"), "a file without an address was reported: \(clean.error)")
        // Written in pieces, so that this file does not hold an address itself.
        try Data(("Write to someone" + "@" + "example.org.\n").utf8).write(to: root.appendingPathComponent("notes.md"))
        let found = try run("/bin/bash", ["script/verify_public_safety.sh"])
        #expect(found.status != 0)
        #expect(found.error.contains("email address found"), "an address in a file that is not staged yet passed: \(found.error)")
    }
}
