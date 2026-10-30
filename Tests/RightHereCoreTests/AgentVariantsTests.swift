import Foundation
import Testing
@testable import RightHereCore

private func config(_ text: String) -> Config { ConfigParser.parse(text).config }

@Suite("AgentVariants: an agent's start options as pages to edit")
struct AgentVariantsTests {
    private let text = """
    [[agent.claude.variant]]
    id = "opus"
    title = "Use Opus"
    arguments = ["--model", "opus"]

    [[agent.claude.variant]]
    id = "plan"
    title = "Plan Mode"
    arguments = ["--permission-mode", "plan"]
    """ + "\n"

    private func options(_ agent: String = "claude", text: String? = nil, entries: [String: EntryLocation]? = nil, listed: [String: [String]]? = nil) -> AgentOptionsState {
        let entries = entries ?? ["opus": EntryLocation(target: .shared, position: 1), "plan": EntryLocation(target: .shared, position: 2)]
        let listed = listed ?? ["opus": ["--model", "opus"], "plan": ["--permission-mode", "plan"]]
        return AgentOptions.state(id: agent, config: config(text ?? self.text), facts: FakeSystemFacts(), listedArgs: nil, variantEntries: entries, listedVariantArguments: listed)!
    }

    private func apply(_ change: FileChange, to text: String) throws -> Config {
        var document = ConfigDocument(text)
        for operation in change.operations { document = try operation.apply(to: document) }
        return config(document.text)
    }

    private func apply(_ operations: [ConfigOperation], to text: String) throws -> Config {
        try apply(FileChange(target: .shared, operations: operations), to: text)
    }

    @Test func theStartOptionsOfTheConfigAreRowsToEditAndTheBuiltInOnesAreOnlyShown() {
        let claude = options()
        #expect(claude.variants.map(\.id) == ["opus", "plan"] && claude.variants.map(\.title) == ["Use Opus", "Plan Mode"])
        #expect(claude.variants[1].arguments == ArgumentList(key: "agent.claude.variant.2.arguments", items: ["--permission-mode", "plan"], listed: ["--permission-mode", "plan"]))
        #expect(claude.fixedVariants.map(\.id) == ["continue", "resume"] && claude.fixedVariants.allSatisfy(\.isBuiltIn) && claude.fixedVariants[0].arguments == ["--continue"])
        #expect(claude.fixedVariants.map(\.titleKey) == [.variantContinue, .variantResume], "the window names a built-in start option in its language, as the menu does")
        let unplaced = options(entries: [:], listed: [:])
        #expect(unplaced.variants.isEmpty && unplaced.fixedVariants.map(\.id) == ["continue", "resume", "opus", "plan"], "a start option whose place is not known is shown, not edited")
        #expect(unplaced.fixedVariants.map(\.isBuiltIn) == [true, true, false, false])
    }

    @Test func theStartOptionsOfAnAgentOfOnesOwnAreItsOwn() {
        let mine = "[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n\n[[agent.mine.variant]]\nid = \"fast\"\ntitle = \"Fast\"\narguments = [\"--fast\"]\n"
        let state = options("mine", text: mine, entries: ["fast": EntryLocation(target: .local, position: 1)], listed: ["fast": ["--fast"]])
        #expect(state.variants.map(\.id) == ["fast"] && state.fixedVariants.isEmpty && state.variants[0].entry == EntryLocation(target: .local, position: 1))
    }

    @Test func aTitleIsChangedInTheFileThatHoldsTheEntryUnderTheCheckOfItsPlace() throws {
        let local = options(entries: ["opus": EntryLocation(target: .local, position: 1), "plan": EntryLocation(target: .shared, position: 2)])
        let change = try #require(AgentVariants.changing(title: " Use Opus 4 ", of: local.variants[0], agent: "claude"))
        #expect(change.target == .local && change.operations.first == .expectEntry("opus", at: 1, in: "agent.claude.variant"))
        let made = try apply(change, to: text)
        #expect(made.agent(id: "claude")?.variants.suffix(2).map(\.title) == ["Use Opus 4", "Plan Mode"])
        #expect(AgentVariants.changing(title: "  ", of: local.variants[0], agent: "claude") == nil && AgentVariants.changing(title: "Use Opus", of: local.variants[0], agent: "claude") == nil)
        let swapped = "[[agent.claude.variant]]\nid = \"plan\"\ntitle = \"Plan Mode\"\n\n[[agent.claude.variant]]\nid = \"opus\"\ntitle = \"Use Opus\"\n"
        #expect(throws: (any Error).self) { try apply(change, to: swapped) }
    }

    @Test func theArgumentsOfAStartOptionAreChangedByPlaceInItsOwnEntry() throws {
        let state = options()
        let plan = state.variants[1]
        func change(_ operations: [ConfigOperation]) throws -> FileChange { try #require(AgentVariants.change(operations, of: plan, agent: "claude")) }
        func plans(_ operations: [ConfigOperation]) throws -> [[String]] {
            try apply(change(operations), to: text).agent(id: "claude")?.variants.filter { !["continue", "resume"].contains($0.id) }.map(\.arguments) ?? []
        }
        #expect(try plans(plan.arguments.adding(" --verbose ")) == [["--model", "opus"], ["--permission-mode", "plan", "--verbose"]])
        #expect(try plans(plan.arguments.removing(at: 1)) == [["--model", "opus"], ["plan"]])
        #expect(try plans(plan.arguments.setting(at: 2, to: "acceptEdits")) == [["--model", "opus"], ["--permission-mode", "acceptEdits"]])
        #expect(try plans(plan.arguments.moving([1], to: 0)) == [["--model", "opus"], ["plan", "--permission-mode"]])
        #expect(try change(plan.arguments.adding("--x")).operations.first == .expectEntry("plan", at: 2, in: "agent.claude.variant"))
        #expect(AgentVariants.change([], of: plan, agent: "claude") == nil)
        let moved = ArgumentList(key: plan.arguments.key, items: ["--permission-mode", "plan"], listed: ["--other"])
        #expect(moved.adding("--x").isEmpty && moved.removing(at: 1).isEmpty && moved.setting(at: 1, to: "--y").isEmpty, "a list that the file does not write as the page shows it is not changed by place")
    }

    @Test func aStartOptionIsMadeWithATitleAndAnIdThatNoStartOptionHas() throws {
        let state = options()
        let made = try #require(AgentVariants.creating(title: " Use Haiku ", agent: state))
        #expect(made.id == "use-haiku")
        let variants = try apply(made.operations, to: text).agent(id: "claude")?.variants ?? []
        #expect(variants.map(\.id) == ["continue", "resume", "opus", "plan", "use-haiku"] && variants.last?.title == "Use Haiku" && variants.last?.arguments == [])
        #expect(AgentVariants.creating(title: "Opus", agent: state)?.id == "opus-2", "the id of a start option that is there is taken")
        #expect(AgentVariants.creating(title: "Continue", agent: state)?.id == "continue-2", "so is the id of a built-in one")
        #expect(AgentVariants.creating(title: "Haiku", agent: state, alsoTaken: ["haiku", "haiku-2"])?.id == "haiku-3", "and one that a file has and the config does not show")
        #expect(AgentVariants.creating(title: "  ", agent: state) == nil)
        #expect(AgentVariants.creating(title: "高速", agent: state)?.id == "variant")
    }

    @Test func aStartOptionIsTakenOutAndTheOthersStay() throws {
        let state = options()
        let change = try #require(AgentVariants.removing(state.variants[0], agent: "claude"))
        #expect(change.operations == [.expectEntry("opus", at: 1, in: "agent.claude.variant"), .removeEntry(at: 1, from: "agent.claude.variant")])
        let left = try apply(change, to: text).agent(id: "claude")?.variants.map(\.id)
        #expect(left == ["continue", "resume", "plan"])
    }

    @Test func theWayAnAgentTakesAFirstPromptIsAWordOrAFlagAndTheBuiltInWayIsTheSettingTakenOut() {
        let claude = options()
        #expect(claude.builtInPromptArgument == "positional" && claude.promptArgument == nil)
        #expect(AgentOptions.operations(settingPromptArgument: " -i ", of: claude) == [.set("agent.claude.prompt_arg", .string("-i"))])
        #expect(AgentOptions.operations(settingPromptArgument: "positional", of: claude).isEmpty && AgentOptions.operations(settingPromptArgument: "", of: claude).isEmpty, "the built-in way is what an agent does when nothing is said")
        let own = options(text: "[agent.claude]\nprompt_arg = \"-i\"\n")
        #expect(own.promptArgument == "-i")
        #expect(AgentOptions.operations(settingPromptArgument: "positional", of: own) == [.unset("agent.claude.prompt_arg")])
        #expect(AgentOptions.operations(settingPromptArgument: "", of: own) == [.unset("agent.claude.prompt_arg")])
        #expect(AgentOptions.operations(settingPromptArgument: "-i", of: own).isEmpty)
        let lazygit = options("lazygit", text: "[agent.lazygit]\nname = \"lazygit\"\ncommand = \"lazygit\"\n", entries: [:], listed: [:])
        #expect(lazygit.builtInPromptArgument == nil && AgentOptions.operations(settingPromptArgument: "positional", of: lazygit) == [.set("agent.lazygit.prompt_arg", .string("positional"))])
        #expect(AgentOptions.operations(settingPromptArgument: "", of: lazygit).isEmpty)
    }
}
