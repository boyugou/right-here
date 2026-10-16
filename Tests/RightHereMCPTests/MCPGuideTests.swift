import Foundation
import Testing
import RightHereCore
@testable import RightHereMCP

@Suite("The guides name the tools the server has, and nothing else")
struct MCPGuideTests {
    private var toolNames: Set<String> { Set(Tools.definitions.map(\.name)) }

    /// Every name the text names as a tool: `right_here_` and the letters after it.
    private func namedTools(in text: String) -> Set<String> {
        var names = Set<String>()
        var rest = Substring(text)
        while let range = rest.range(of: "right_here_") {
            let tail = rest[range.lowerBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            names.insert(String(tail))
            rest = rest[range.upperBound...]
        }
        return names
    }

    private func repositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// `rh docs` prints through the one function that shows what a terminal acts on, or what draws nothing, as an escape (a line feed and a tab stay): no guide may hold
    /// such a character, or the person would read an escape where the text has one.
    @Test func noGuideHoldsACharacterThatThePrinterWouldShowAsAnEscape() {
        for topic in Documentation.topics {
            let text = Guides.text(for: topic) ?? ""
            #expect(!text.isEmpty, "\(topic)")
            #expect(text.escapingControlCharacters(keeping: ["\n", "\t"]) == text, "the guide \(topic) holds a control or invisible character")
        }
    }

    @Test func theGuideListsEveryToolAndNoneThatDoesNotExist() {
        let text = MCPGuide.text
        #expect(namedTools(in: text) == toolNames, "the guide names \(namedTools(in: text).symmetricDifference(toolNames).sorted())")
        for tool in Tools.definitions {
            #expect(text.contains("`\(tool.name)`"), "\(tool.name) is not in the guide")
        }
    }

    @Test func theGuideSaysHowToStartTheServerAndTheSnippetIsJSON() throws {
        let text = MCPGuide.text
        #expect(text.contains("claude mcp add right-here -- rh mcp"))
        let snippet = try #require(text.split(separator: "\n").first { $0.contains("\"mcpServers\"") })
        let object = try #require(try JSONSerialization.jsonObject(with: Data(snippet.utf8)) as? [String: Any])
        let servers = try #require(object["mcpServers"] as? [String: Any])
        let entry = try #require(servers["right-here"] as? [String: Any])
        #expect(entry["command"] as? String == "rh")
        #expect(entry["args"] as? [String] == ["mcp"])
        for phrase in ["one message per line", "dry_run: true", "paths", "container", "⟦user⟧", "PATH"] {
            #expect(text.contains(phrase), "the guide does not say \(phrase)")
        }
    }

    @Test func theDocsToolOffersEveryTopicAndTheMCPTopicIsServedHere() throws {
        let docs = try #require(Tools.definitions.first { $0.name == "right_here_docs" })
        let offered = docs.inputSchema["properties"]?["topic"]?["enum"]?.arrayValue?.compactMap(\.stringValue) ?? []
        #expect(Set(offered) == Set(Documentation.topics), "the tool offers \(offered)")
        for topic in Documentation.topics {
            #expect(Guides.text(for: topic)?.isEmpty == false, "no text for \(topic)")
            #expect(docs.description.contains(topic), "the tool's description does not name \(topic)")
        }
    }

    @Test func theOtherTextsThatNameToolsNameOnlyTheToolsThatExist() throws {
        // The README, the plugin, the server's instructions and the `rh mcp` help are read by people and agents as the list of the tools.
        for file in ["README.md", "plugins/right-here/README.md", "plugins/right-here/skills/open-here/SKILL.md", "plugins/right-here/skills/setup/SKILL.md",
                     "plugins/right-here/skills/review-changes/SKILL.md", "Sources/rh/Commands/MCPCommand.swift"] {
            let named = namedTools(in: try repositoryFile(file))
            #expect(named.isSubset(of: toolNames), "\(file) names \(named.subtracting(toolNames).sorted()), which the server does not have")
        }
        #expect(namedTools(in: MCPServer.instructions).isSubset(of: toolNames))
    }
}
