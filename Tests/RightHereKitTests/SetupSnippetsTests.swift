import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

private func parsed(_ json: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
}

@Suite("SetupSnippets")
struct SetupSnippetsTests {
    @Test("the MCP snippet is JSON that starts rh mcp, whatever the command is called", arguments: [
        "rh", "/opt/tools/ann/bin/rh", "/Applications/Right Here.app/Contents/Helpers/rh", "/opt/tools/o\"brien/bin/rh", "/opt/tools/back\\slash/rh",
        "/opt/tools/日本語/rh"
    ])
    func theMCPSnippetIsValidJSON(command: String) throws {
        let json = try parsed(SetupSnippets.mcpConfiguration(command: command))
        let servers = try #require(json["mcpServers"] as? [String: Any])
        #expect(servers.keys.sorted() == [SetupSnippets.mcpServerName])
        let server = try #require(servers[SetupSnippets.mcpServerName] as? [String: Any])
        #expect(server["command"] as? String == command)
        #expect(server["args"] as? [String] == ["mcp"])
    }

    @Test func theMCPSnippetIsWrittenTheWayTheReadmeWritesIt() {
        #expect(SetupSnippets.mcpConfiguration(command: "rh") == """
        {
          "mcpServers": {
            "right-here": {
              "command": "rh",
              "args": ["mcp"]
            }
          }
        }
        """)
    }

    @Test func aSlashIsNotEscapedInThePath() {
        #expect(SetupSnippets.mcpConfiguration(command: "/a/b").contains("\"command\": \"/a/b\""))
    }

    @Test func theCommandIsTheLinkRhInstallMakesWhenItWorks() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let helper = home.appendingPathComponent("App/rh")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let installer = Installer(home: home)
        try FileManager.default.createDirectory(at: installer.locations.localBin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: installer.cliLink.path, withDestinationPath: helper.path)
        #expect(SetupSnippets.mcpCommand(home: home, helperPath: helper.path) == installer.cliLink.path)
    }

    @Test func withoutTheLinkItIsTheCopyInsideTheApp() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let helper = home.appendingPathComponent("rh")
        try "#!/bin/sh\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        #expect(SetupSnippets.mcpCommand(home: home, helperPath: helper.path) == helper.path)
    }

    @Test func aLinkThatPointsNowhereIsNotUsed() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        let installer = Installer(home: home)
        try FileManager.default.createDirectory(at: installer.locations.localBin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: installer.cliLink.path, withDestinationPath: home.appendingPathComponent("gone").path)
        #expect(SetupSnippets.mcpCommand(home: home, helperPath: nil) == "rh")
    }

    @Test func nothingInstalledMeansTheBareCommandOfTheReadme() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        #expect(SetupSnippets.mcpCommand(home: home, helperPath: home.appendingPathComponent("not-there/rh").path) == "rh")
        #expect(SetupSnippets.mcpCommand(home: home, helperPath: nil) == "rh")
    }

    @Test func thePluginCommandsNameTheMarketplaceAndThePluginTheRepositoryHas() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let marketplace = try parsed(String(contentsOf: root.appendingPathComponent(".claude-plugin/marketplace.json"), encoding: .utf8))
        let name = try #require(marketplace["name"] as? String)
        let plugin = try #require((marketplace["plugins"] as? [[String: Any]])?.first?["name"] as? String)
        let lines = SetupSnippets.pluginCommands.split(separator: "\n").map(String.init)
        #expect(lines == ["/plugin marketplace add boyugou/right-here", "/plugin install \(plugin)@\(name)"])
    }

    @Test func theSetupPromptNamesAGuideThatExists() {
        #expect(SetupSnippets.setupPrompt.contains("`rh docs agent-setup`"))
        #expect(Documentation.topics.contains("agent-setup"))
        #expect(!SetupSnippets.setupPrompt.contains("\n"))
    }
}
