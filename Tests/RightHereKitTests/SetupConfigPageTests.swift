import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("SetupActions: what the Config page shows and does")
struct SetupConfigPageTests {
    private static let sample = "[general]\nterminal = \"ghostty\"\nagents = [\"claude\"]\n\n[menu]\nitems = [\"open-terminal\", \"copy-path\"]\n"

    private struct Home {
        let home: URL
        let paths: RHPaths
        let service: ConfigService
        let actions: SetupActions

        init(config: String? = SetupConfigPageTests.sample) throws {
            home = try makeTemporaryDirectory()
            paths = RHPaths(environment: [:], home: home)
            service = ConfigService(paths: paths, environment: [:])
            actions = SetupActions(facts: FakeSystemFacts(homeDirectory: home), paths: paths, runner: FakeProcessRunner(), helperPath: "/opt/app/rh", trialHome: home)
            if let config {
                try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
                try config.write(to: paths.configFile, atomically: true, encoding: .utf8)
            }
        }

        var text: String { (try? String(contentsOf: paths.configFile, encoding: .utf8)) ?? "" }
        func cleanUp() { try? FileManager.default.removeItem(at: home) }
    }

    @Test func thePageHasTheTextTheDigestTheHistoryAndTheProposals() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        _ = try machine.service.apply(.set("general.terminal", .string("terminal")), actor: .cli)
        guard case .proposed(let proposal, _) = try machine.service.submit([.set("agent.claude.args", .strings(["-p"]))], actor: .mcp) else { Issue.record("not proposed"); return }
        let page = await machine.actions.configPage(target: .shared)
        #expect(page.target == .shared && page.problem == nil)
        #expect(page.text?.text == machine.text && page.text?.digest == ConfigHistory.digest(machine.text))
        #expect(page.history.map(\.summary) == ["set general.terminal = \"terminal\""] && page.history.map(\.actor) == [.cli])
        #expect(page.proposals.map(\.id) == [proposal.id])
        #expect(page.proposals.first?.change?.diff.contains("+args = [\"-p\"]") == true && page.proposals.first?.problem == nil)
        #expect(page.validation != nil)
    }

    @Test func theMachinesOwnFileIsAnEmptyTextWhenItIsNotThereAndIsReadOverTheSharedOne() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let page = await machine.actions.configPage(target: .local)
        #expect(page.text == ConfigService.ConfigText(text: "", digest: ConfigHistory.digest(""), exists: false) && page.problem == nil)
        #expect(page.history.isEmpty)
        // A terminal the shared file does not define is a problem on its own; one it does is not.
        let validation = try #require(page.validation)
        #expect(validation.problems("[general]\nterminal = \"nonsense\"\n").contains { $0.severity == .error })
        #expect(validation.problems("[general]\nterminal = \"terminal\"\n").filter { $0.severity == .error }.isEmpty)
    }

    @Test func aTerminalOnlyTheSharedFileDefinesIsAcceptedInTheMachinesOwnTextAndNotOnItsOwn() async throws {
        let shared = SetupConfigPageTests.sample + "\n[[app]]\nid = \"tower\"\nname = \"Tower\"\nbundle_id = \"com.fournova.Tower3\"\nrole = \"terminal\"\n"
        let machine = try Home(config: shared); defer { machine.cleanUp() }
        let text = "[general]\nterminal = \"tower\"\n"
        let local = try #require(await machine.actions.configPage(target: .local).validation)
        #expect(local.problems(text).filter { $0.severity == .error }.isEmpty, "read over the shared file, tower is a terminal")
        let sharedValidation = try #require(await machine.actions.configPage(target: .shared).validation)
        #expect(sharedValidation.problems(text).contains { $0.severity == .error }, "read on its own it is not")
        // And a save of that text for this Mac's file goes through.
        let read = try machine.service.text(of: .local)
        #expect(await machine.actions.saveConfigText(text, target: .local, unchangedSince: read.digest).change?.written == true)
    }

    @Test func withNoConfigThePageSaysSoAndHasNothingToEdit() async throws {
        let machine = try Home(config: nil); defer { machine.cleanUp() }
        let page = await machine.actions.configPage(target: .shared)
        #expect(page.text == nil && page.problem?.contains("rh setup") == true && page.proposals.isEmpty && page.history.isEmpty)
    }

    @Test func aProposalThatCannotBeMadeAnyMoreShowsWhyInsteadOfAChange() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let app = ConfigOperation.addEntry(to: "app", fields: [ConfigField("id", .string("tower")), ConfigField("name", .string("Tower")), ConfigField("bundle_id", .string("com.fournova.Tower3"))], at: nil)
        guard case .proposed(let proposal, _) = try machine.service.submit([app], actor: .mcp) else { Issue.record("not proposed"); return }
        try (Self.sample + "\n[[app]]\nid = \"tower\"\nname = \"Tower\"\nbundle_id = \"com.fournova.Tower3\"\n").write(to: machine.paths.configFile, atomically: true, encoding: .utf8)
        let page = await machine.actions.configPage(target: .shared)
        let preview = try #require(page.proposals.first)
        #expect(preview.proposal.id == proposal.id && preview.change == nil && preview.problem?.isEmpty == false)
    }

    @Test func aSavedTextReplacesTheFileAndIsOnTheHistoryAndCanBeTakenBack() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let read = try await #require(machine.actions.configPage(target: .shared).text)
        let written = "# My own.\n" + Self.sample.replacingOccurrences(of: "ghostty", with: "iterm")
        let result = await machine.actions.saveConfigText(written, target: .shared, unchangedSince: read.digest)
        #expect(result.notice == nil && result.change?.written == true && machine.text == written)
        #expect(await machine.actions.configPage(target: .shared).history.map(\.actor) == [.window])
        let undone = await machine.actions.undoConfigEdit(target: .shared)
        #expect(undone.change?.written == true && machine.text == Self.sample)
        #expect(await machine.actions.undoConfigEdit(target: .shared).notice?.isProblem == true, "there is nothing left to take back")
    }

    @Test func aTextIsNotSavedOverAChangeMadeMeanwhileOrWhenItDoesNotRead() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        let read = try await #require(machine.actions.configPage(target: .shared).text)
        _ = try machine.service.apply(.set("general.terminal", .string("terminal")), actor: .mcp)
        let meanwhile = await machine.actions.saveConfigText("[general]\n", target: .shared, unchangedSince: read.digest)
        #expect(meanwhile.change == nil && meanwhile.notice?.isProblem == true)
        if case .failed(let text)? = meanwhile.notice { #expect(text.contains("was changed while you were editing it"), "\(text)") }
        #expect(machine.text.contains("terminal = \"terminal\""))
        let fresh = try await #require(machine.actions.configPage(target: .shared).text)
        let broken = await machine.actions.saveConfigText("[general\n", target: .shared, unchangedSince: fresh.digest)
        #expect(broken.change == nil && broken.notice?.isProblem == true)
        if case .failed(let text)? = broken.notice { #expect(text.hasPrefix("That change would make the config invalid:"), "\(text)") }
        #expect(machine.text.contains("terminal = \"terminal\""))
    }

    @Test func aProposalIsAppliedByThePersonAndForgottenOrDismissed() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        guard case .proposed(let first, _) = try machine.service.submit([.set("agent.claude.args", .strings(["-p"]))], actor: .mcp),
              case .proposed(let second, _) = try machine.service.submit([.set("agent.claude.command", .string("/tmp/other"))], actor: .mcp) else { Issue.record("not proposed"); return }
        let applied = await machine.actions.approveProposal(first.id)
        #expect(applied.change?.written == true && machine.text.contains("args = [\"-p\"]"))
        #expect(machine.service.history().map(\.actor) == [.window], "the person made it")
        #expect(await machine.actions.dismissProposal(second.id) == nil)
        #expect(!machine.text.contains("/tmp/other") && machine.service.pending().isEmpty)
        let gone = await machine.actions.approveProposal(first.id)
        #expect(gone.change == nil && gone.notice?.isProblem == true)
        #expect(await machine.actions.dismissProposal(first.id)?.isProblem == true)
    }

    @Test func theSnapshotCarriesTheWaitingProposals() async throws {
        let machine = try Home(); defer { machine.cleanUp() }
        guard case .proposed(let proposal, _) = try machine.service.submit([.set("agent.claude.args", .strings(["-p"]))], actor: .mcp) else { Issue.record("not proposed"); return }
        let loader = SetupLoader(facts: FakeSystemFacts(homeDirectory: machine.home, directories: [machine.home.path]), paths: machine.paths, runner: FakeProcessRunner(), helperPath: "/opt/rh/bin/rh", localizer: .english)
        #expect(await loader.load().proposals.map(\.id) == [proposal.id])
    }
}
