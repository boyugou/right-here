import Foundation
import Synchronization
import Testing
import RightHereCore
import RightHereKit
@testable import RightHereMCP

/// The machine as it is, except that the first look at `stale` misses what is there: another run made that file between this run's look and its create.
private final class MissesAFileOnce: SystemFacts {
    private let base = LiveSystemFacts()
    private let stale: String
    private let looked = Mutex(false)

    init(stale: String) { self.stale = stale }

    var homeDirectory: URL { base.homeDirectory }
    var currentDirectory: URL { base.currentDirectory }
    var loginShell: String { base.loginShell }
    func isDirectory(_ url: URL) -> Bool? { base.isDirectory(url) }
    func isPackage(_ url: URL) -> Bool { base.isPackage(url) }
    func fileExists(_ url: URL) -> Bool { base.fileExists(url) }
    func itemState(_ url: URL) -> ItemState {
        if url.path == stale, looked.withLock({ looked in defer { looked = true }; return !looked }) { return .missing }
        return base.itemState(url)
    }
    func gitRoot(containing url: URL) -> URL? { base.gitRoot(containing: url) }
    func applicationURL(bundleID: String) -> URL? { base.applicationURL(bundleID: bundleID) }
    func displayName(bundleID: String) -> String? { base.displayName(bundleID: bundleID) }
    func runsShellScripts(bundleID: String) -> Bool { base.runsShellScripts(bundleID: bundleID) }
    func bundleVersion(bundleID: String) -> String? { base.bundleVersion(bundleID: bundleID) }
    func isRunning(bundleID: String) -> Bool { base.isRunning(bundleID: bundleID) }
    func environment(_ key: String) -> String? { base.environment(key) }
    func onDiskPath(_ url: URL) -> String { base.onDiskPath(url) }
}

@Suite("MCP: New File when another run takes its name")
struct MCPNewFileTests {
    /// `right_here_run` of New File whose name another run took after it was planned: it failed with "already exists"; it plans again and makes the next
    /// name, and what it reports is the file it made. The reveal goes to a fake runner, so no Finder window opens.
    @Test func aNewFileWhoseNameWasTakenMeanwhileTakesTheNextName() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rh-mcp-new-\(UUID().uuidString)")
        let configDirectory = folder.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "theirs".write(to: folder.appendingPathComponent("untitled.txt"), atomically: false, encoding: .utf8)
        let paths = RHPaths(environment: ["RH_CONFIG_DIR": configDirectory.path], home: URL(fileURLWithPath: "/Users/tester"))
        let server = MCPServer(context: ServerContext(facts: MissesAFileOnce(stale: folder.appendingPathComponent("untitled.txt").path), paths: paths,
                                                      runner: FakeProcessRunner(), pasteboard: RecordingPasteboard(), rhPath: nil))
        let request = JSONValue.object(["jsonrpc": .string("2.0"), "id": .number(1), "method": .string("tools/call"), "params": .object([
            "name": .string("right_here_run"), "arguments": .object(["action": .string("new-file.txt"), "container": .string(folder.path)]),
        ])])
        let reply = try #require(await server.handle(request.line()))
        let result = try #require(try JSONDecoder().decode(JSONValue.self, from: Data(reply.utf8))["result"])
        let text = result["content"]?.arrayValue?.first?["text"]?.stringValue ?? ""
        #expect(result["isError"]?.boolValue != true, "\(text)")
        #expect(text.contains("untitled 2.txt"), "\(text)")
        #expect(try String(contentsOf: folder.appendingPathComponent("untitled.txt"), encoding: .utf8) == "theirs")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("untitled 2.txt").path))
    }
}
