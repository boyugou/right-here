import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

/// The window's question and the change it asked about are made against the same files: the service refuses, under the lock of the write, a change of the window that would make an agent start
/// without its permission prompts that the person did not agree to. None of these touch the real home.
@Suite("ConfigService: a change of the window makes only the agents the person agreed to start without asking")
struct ConfigAgreedLooseningTests {
    private struct Workspace {
        let root: URL
        let paths: RHPaths
        let service: ConfigService

        init(_ config: String, local: String? = nil) throws {
            root = try makeTemporaryDirectory()
            paths = RHPaths(environment: [:], home: root)
            service = ConfigService(paths: paths, environment: [:])
            try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
            try config.write(to: paths.configFile, atomically: true, encoding: .utf8)
            if let local { try local.write(to: paths.localConfigFile, atomically: true, encoding: .utf8) }
        }

        var text: String { (try? String(contentsOf: paths.configFile, encoding: .utf8)) ?? "" }
        func clean() { try? FileManager.default.removeItem(at: root) }
    }

    private static let claude = PromptEffects.Entry(agent: "claude", name: "Claude Code", flag: "--dangerously-skip-permissions")
    private static let switchOn: [ConfigOperation] = [.set("general.bypass_permissions", .boolean(true))]

    private func refusal(_ body: () throws -> ConfigChange) -> [String]? {
        do {
            _ = try body()
            return nil
        } catch ConfigService.Failure.wouldStartWithoutAsking(let agents) {
            return agents.map(\.agent)
        } catch {
            Issue.record("another error: \(error)")
            return nil
        }
    }

    @Test func aChangeIsRefusedWithEveryAgentItWouldStartWhenOneOfThemWasNotAgreedTo() throws {
        let work = try Workspace("[general]\nagents = [\"claude\", \"codex\"]\n"); defer { work.clean() }
        let before = work.text
        #expect(refusal { try work.service.apply(Self.switchOn, actor: .window, startingWithoutAsking: []) } == ["claude", "codex"])
        #expect(refusal { try work.service.apply(Self.switchOn, actor: .window, startingWithoutAsking: [Self.claude]) } == ["claude", "codex"], "Codex was not named")
        #expect(work.text == before && work.service.history().isEmpty, "nothing was written or kept")
        let codex = PromptEffects.Entry(agent: "codex", name: "Codex", flag: "--dangerously-bypass-approvals-and-sandbox")
        #expect(refusal { try work.service.apply(Self.switchOn, actor: .window, startingWithoutAsking: [Self.claude, codex]) } == nil)
        #expect(work.text.contains("bypass_permissions = true"))
    }

    @Test func anAgentAgreedToWithAnotherFlagIsNotAgreedTo() throws {
        let work = try Workspace("[general]\nagents = [\"claude\"]\n\n[agent.claude]\nbypass_permission_arg = \"--yolo\"\n"); defer { work.clean() }
        #expect(refusal { try work.service.apply(Self.switchOn, actor: .window, startingWithoutAsking: [Self.claude]) } == ["claude"])
    }

    /// Without the list, the command line and an assistant's tool: the person at the command line is not asked, and an assistant's change waits as a proposal (`submit`).
    @Test func withoutTheListNothingIsAskedAsBefore() throws {
        let work = try Workspace("[general]\nagents = [\"claude\"]\n"); defer { work.clean() }
        #expect(refusal { try work.service.apply(Self.switchOn, actor: .cli) } == nil)
        #expect(work.text.contains("bypass_permissions = true"))
    }

    /// A change that makes nothing start without asking is made whatever was agreed, and so is one that tightens.
    @Test func aChangeThatStartsNothingWithoutAskingIsMade() throws {
        let work = try Workspace("[general]\nagents = [\"claude\"]\nbypass_permissions = true\n"); defer { work.clean() }
        #expect(refusal { try work.service.apply([.set("general.terminal_placement", .string("tab"))], actor: .window, startingWithoutAsking: []) } == nil)
        #expect(refusal { try work.service.apply([.set("general.bypass_permissions", .boolean(false))], actor: .window, startingWithoutAsking: []) } == nil)
    }

    @Test func anUndoThatWouldStartAnAgentWithoutAskingIsHeldTheSameWay() throws {
        let work = try Workspace("[general]\nagents = [\"claude\"]\nbypass_permissions = true\n"); defer { work.clean() }
        let off = try work.service.apply([.set("general.bypass_permissions", .boolean(false))], actor: .window)
        #expect(refusal { try work.service.undo(expecting: off.afterDigest, replacing: off.beforeDigest, startingWithoutAsking: []) } == ["claude"])
        #expect(work.text.contains("bypass_permissions = false") && work.service.history().count == 1, "nothing was taken back, and the change can still be")
        #expect(refusal { try work.service.undo(expecting: off.afterDigest, replacing: off.beforeDigest, startingWithoutAsking: [Self.claude]) } == nil)
        #expect(work.text.contains("bypass_permissions = true"))
    }

    @Test func aProposalThatWouldStartAnAgentWithoutAskingIsHeldTheSameWayAndStaysWaiting() throws {
        let work = try Workspace("[general]\nagents = [\"claude\"]\n"); defer { work.clean() }
        guard case .proposed(let proposal, _) = try work.service.submit(Self.switchOn, actor: .mcp) else { Issue.record("not proposed"); return }
        #expect(refusal { try work.service.approve(proposal.id, actor: .window, startingWithoutAsking: []) } == ["claude"])
        #expect(work.service.pending().map(\.id) == [proposal.id], "it still waits")
        #expect(refusal { try work.service.approve(proposal.id, actor: .window, startingWithoutAsking: [Self.claude]) } == nil)
        #expect(work.text.contains("bypass_permissions = true") && work.service.pending().isEmpty)
    }

    /// The other file counts: the switch is in the shared file and the agents in this Mac's own, and a change of either is held to what the two make together.
    @Test func whatTheTwoFilesMakeTogetherIsWhatIsHeld() throws {
        let work = try Workspace("[general]\nbypass_permissions = true\nagents = [\"claude\"]\n", local: "[general]\nagents = [\"claude\"]\n"); defer { work.clean() }
        #expect(refusal { try work.service.apply([.insert("codex", into: "general.agents", at: nil)], target: .local, actor: .window, startingWithoutAsking: []) } == ["codex"])
    }

    /// The history row carries what an Undo of it is held to: the text the edit left and the one it replaced.
    @Test func aRowOfTheHistoryNamesTheTextsItsUndoIsHeldTo() throws {
        let work = try Workspace("[general]\nagents = [\"claude\"]\n"); defer { work.clean() }
        let change = try work.service.apply([.set("general.terminal_placement", .string("tab"))], actor: .window)
        let row = try #require(work.service.history().first)
        #expect(row.afterDigest == change.afterDigest && row.beforeDigest == change.beforeDigest)
        _ = try work.service.apply([.set("general.terminal_placement", .string("window"))], actor: .mcp)
        #expect(throws: ConfigService.Failure.notTheLast(.shared)) { try work.service.undo(expecting: row.afterDigest, replacing: row.beforeDigest) }
    }
}
