import Foundation
import Testing
@testable import RightHereCore

@Suite("ConfigRequest: what is asked, in the words the command line and the MCP tool share")
struct ConfigRequestTests {
    private let document = ConfigDocument("""
    [general]
    agents = ["claude", "codex"]

    [menu]
    items = ["open-terminal", "open-editor", "-", "agents"]

    [[preset]]
    id = "alpha"
    title = "Alpha"
    prompt = "Alpha {files}"

    [[preset]]
    id = "beta"
    title = "Beta"
    prompt = "Beta {files}"
    """ + "\n")

    private func operations(_ request: ConfigRequest) throws -> [ConfigOperation] {
        try request.operations(in: document)
    }

    private func problem(_ request: ConfigRequest) -> String? {
        do {
            _ = try request.operations(in: document)
            return nil
        } catch let problem as ConfigRequest.Problem {
            return "\(problem.errorDescription ?? "")"
        } catch {
            return "(\(type(of: error))) \(error.localizedDescription)"
        }
    }

    @Test func setAndUnsetNameTheSettingAndTakeTheValueAsData() throws {
        #expect(try operations(ConfigRequest(.set, "general.terminal", values: ["ghostty"])) == [.set("general.terminal", .string("ghostty"))])
        #expect(try operations(ConfigRequest(.set, "general.agents", values: ["claude", "codex"])) == [.set("general.agents", .strings(["claude", "codex"]))])
        #expect(try operations(ConfigRequest(.set, "preset.1.max_files", values: ["3"])) == [.set("preset.1.max_files", .integer(3))])
        #expect(try operations(ConfigRequest(.unset, "general.editor")) == [.unset("general.editor")])
        #expect(problem(ConfigRequest(.set, "general.nope", values: ["x"])) == "(EditError) \"general.nope\" is not a setting of the config (`rh docs config` lists them).")
        #expect(problem(ConfigRequest(.set, "general.terminal", values: [])) == "(EditError) \"general.terminal\": it takes one value, and 0 were given (put a text that has spaces in quotes).")
    }

    @Test func itemsAreAddedAtTheEndOrWhereSaidOneAfterTheOther() throws {
        #expect(try operations(ConfigRequest(.add, "menu.items", values: ["open-with"])) == [.insert("open-with", into: "menu.items", at: nil)])
        #expect(try operations(ConfigRequest(.add, "menu.items", values: ["a", "b"], at: "2")) == [.insert("a", into: "menu.items", at: 2), .insert("b", into: "menu.items", at: 3)])
        #expect(try operations(ConfigRequest(.add, "menu.items", values: ["a"], at: "first")) == [.insert("a", into: "menu.items", at: 1)])
        // `last` is after the last item: the list has four.
        #expect(try operations(ConfigRequest(.add, "menu.items", values: ["a", "b"], at: "last")) == [.insert("a", into: "menu.items", at: 5), .insert("b", into: "menu.items", at: 6)])
        #expect(try operations(ConfigRequest(.add, "services.items", values: ["a"], at: "last")) == [.insert("a", into: "services.items", at: 1)], "a list the file does not have yet")
        #expect(problem(ConfigRequest(.add, "menu.items")) == "Name the items to add.")
        #expect(problem(ConfigRequest(.add, "menu.items", values: ["a"], at: "0")) == "at takes a place from 1, first or last, not \"0\".")
        #expect(problem(ConfigRequest(.add, "menu.items", values: ["a"], at: "middle")) == "at takes a place from 1, first or last, not \"middle\".")
    }

    @Test func anEntryIsAddedFromItsFieldsAndAFieldGivenTwiceIsAList() throws {
        let request = ConfigRequest(.add, "preset", values: ["id=review", "title=Code review", "prompt=Review {files} = carefully", "max_files=2"], at: "first")
        #expect(try operations(request) == [.addEntry(to: "preset", fields: [
            ConfigField("id", .string("review")), ConfigField("title", .string("Code review")), ConfigField("prompt", .string("Review {files} = carefully")), ConfigField("max_files", .integer(2))
        ], at: 1)])
        let variant = ConfigRequest(.add, "agent.claude.variant", values: ["id=fast", "title=Fast", "arguments=--fast", "arguments=--quiet"])
        #expect(try operations(variant) == [.addEntry(to: "agent.claude.variant", fields: [
            ConfigField("id", .string("fast")), ConfigField("title", .string("Fast")), ConfigField("arguments", .strings(["--fast", "--quiet"]))
        ], at: nil)])
        #expect(problem(ConfigRequest(.add, "preset")) == "Give the fields of the entry as name=value.")
        #expect(problem(ConfigRequest(.add, "preset", values: ["review"])) == "\"review\" is not a field: write name=value.")
        #expect(problem(ConfigRequest(.add, "preset", values: ["=x"])) == "\"=x\" is not a field: write name=value.")
        #expect(problem(ConfigRequest(.add, "preset", values: ["nope=1"]))?.hasPrefix("(EditError) \"preset.1.nope\" is not a setting") == true)
        #expect(problem(ConfigRequest(.add, "preset", values: ["title=a", "title=b"])) == "(EditError) \"preset.1.title\": it takes one value, and 2 were given (put a text that has spaces in quotes).")
        #expect(problem(ConfigRequest(.add, "general.terminal", values: ["x"])) == "\"general.terminal\" is not a list: use `rh config set` for a setting.")
    }

    @Test func anItemIsNamedByItsTextItsIdOrItsPlace() throws {
        #expect(try operations(ConfigRequest(.remove, "menu.items", item: "open-editor")) == [.remove(at: 2, from: "menu.items")])
        #expect(try operations(ConfigRequest(.remove, "menu.items", item: "-")) == [.remove(at: 3, from: "menu.items")])
        #expect(try operations(ConfigRequest(.remove, "menu.items", position: 4)) == [.remove(at: 4, from: "menu.items")])
        #expect(try operations(ConfigRequest(.remove, "preset", item: "beta")) == [.removeEntry(at: 2, from: "preset")])
        #expect(try operations(ConfigRequest(.remove, "preset", position: 1)) == [.removeEntry(at: 1, from: "preset")])
        // A place wins over a name: it is what was meant when both are given.
        #expect(try operations(ConfigRequest(.remove, "menu.items", item: "agents", position: 1)) == [.remove(at: 1, from: "menu.items")])
        #expect(problem(ConfigRequest(.remove, "menu.items", item: "nope")) == "menu.items has no item \"nope\".")
        #expect(problem(ConfigRequest(.remove, "preset", item: "nope")) == "preset has no entry with the id \"nope\".")
        #expect(problem(ConfigRequest(.remove, "menu.items")) == "Name the item (or give a position).")
        #expect(problem(ConfigRequest(.remove, "menu.items", position: 0)) == "position counts from 1.")
        #expect(problem(ConfigRequest(.remove, "general.terminal", item: "x")) == "\"general.terminal\" is not a list: use `rh config unset` for a setting.")
    }

    @Test func anItemIsMovedToAPlaceOrToTheEnds() throws {
        #expect(try operations(ConfigRequest(.move, "menu.items", item: "agents", to: "1")) == [.move(from: 4, to: 1, in: "menu.items")])
        #expect(try operations(ConfigRequest(.move, "menu.items", item: "open-terminal", to: "last")) == [.move(from: 1, to: 4, in: "menu.items")])
        #expect(try operations(ConfigRequest(.move, "menu.items", item: "agents", to: "first")) == [.move(from: 4, to: 1, in: "menu.items")])
        #expect(try operations(ConfigRequest(.move, "menu.items", position: 2, to: "3")) == [.move(from: 2, to: 3, in: "menu.items")])
        #expect(try operations(ConfigRequest(.move, "preset", item: "beta", to: "first")) == [.moveEntry(from: 2, to: 1, in: "preset")])
        #expect(try operations(ConfigRequest(.move, "preset", item: "alpha", to: "last")) == [.moveEntry(from: 1, to: 2, in: "preset")])
        #expect(problem(ConfigRequest(.move, "menu.items", item: "agents")) == "Say where to move it: to is a place from 1, first or last.")
        #expect(problem(ConfigRequest(.move, "menu.items", item: "agents", to: "0")) == "to takes a place from 1, first or last, not \"0\".")
        #expect(problem(ConfigRequest(.move, "general.terminal", item: "x", to: "1")) == "\"general.terminal\" is not a list.")
    }

    @Test func whatTheFileDoesNotHaveYetIsCountedAsNothing() throws {
        let empty = ConfigDocument("[general]\nterminal = \"ghostty\"\n")
        #expect(try ConfigRequest(.add, "menu.items", values: ["a"], at: "last").operations(in: empty) == [.insert("a", into: "menu.items", at: 1)])
        #expect(try ConfigRequest(.add, "preset", values: ["id=x"], at: "last").operations(in: empty) == [.addEntry(to: "preset", fields: [ConfigField("id", .string("x"))], at: 1)])
        do {
            _ = try ConfigRequest(.remove, "preset", item: "x").operations(in: empty)
            Issue.record("accepted")
        } catch ConfigRequest.Problem.notFound(let text) {
            #expect(text == "preset has no entry with the id \"x\".")
        }
    }

    @Test func aNameWithAControlCharacterIsSaidEscaped() {
        let message = problem(ConfigRequest(.remove, "menu.items", item: "a\u{1B}[31mb")) ?? ""
        #expect(!message.contains("\u{1B}") && message.contains("has no item"), "\(message.debugDescription)")
    }

    @Test func everyVerbHasAName() {
        #expect(ConfigRequest.Verb.allCases.map(\.rawValue) == ["set", "unset", "add", "remove", "move"])
    }

    // MARK: An agent of one's own, as the window makes and takes it out

    @Test func anAgentOfOnesOwnIsMadeFromItsFieldsAndPutInTheMenuInOneChange() throws {
        let made = try operations(ConfigRequest(.add, "agent.lazygit", values: ["name=Lazy Git", "command=lazygit"]))
        #expect(made == [.expect(["claude", "codex"], in: "general.agents"),
                         .addTable("agent.lazygit", fields: [ConfigField("name", .string("Lazy Git")), ConfigField("command", .string("lazygit"))]),
                         .insert("lazygit", into: "general.agents", at: nil)])
        var edited = document
        for operation in made { edited = try operation.apply(to: edited) }
        let config = ConfigParser.parse(edited.text).config
        #expect(config.enabledAgents == ["claude", "codex", "lazygit"] && config.agent(id: "lazygit")?.command == "lazygit" && config.agent(id: "lazygit")?.name == "Lazy Git", "\(edited.text)")
        #expect(ConfigTrust.approvals(for: made).map(\.key) == ["agent.*.command"], "an assistant that asks for it is held for the person")
        // A list of its own: `args` is a list, given by repeating the field.
        let withArgs = try operations(ConfigRequest(.add, "agent.mine", values: ["name=Mine", "command=mine", "args=-v", "args=--fast"]))
        #expect(withArgs.contains(.addTable("agent.mine", fields: [ConfigField("name", .string("Mine")), ConfigField("command", .string("mine")), ConfigField("args", .strings(["-v", "--fast"]))])))
    }

    @Test func aConfigThatDoesNotListTheAgentsGetsTheListFromTheFirstOne() throws {
        let none = ConfigDocument("[general]\nterminal = \"ghostty\"\n")
        let made = try ConfigRequest(.add, "agent.mine", values: ["name=Mine", "command=mine"]).operations(in: none)
        var edited = none
        for operation in made { edited = try operation.apply(to: edited) }
        #expect(ConfigParser.parse(edited.text).config.enabledAgents == ["mine"], "\(edited.text)")
    }

    @Test func anAgentOfOnesOwnIsTakenOutOfTheMenuFirstAndThenOutOfTheConfig() throws {
        let text = "[general]\nagents = [\"claude\", \"mine\"]\n\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n"
        let withAgent = ConfigDocument(text)
        let removed = try ConfigRequest(.remove, "agent.mine").operations(in: withAgent)
        #expect(removed == [.expect(["claude", "mine"], in: "general.agents"), .remove(at: 2, from: "general.agents"), .removeTable("agent.mine")])
        var edited = withAgent
        for operation in removed { edited = try operation.apply(to: edited) }
        #expect(ConfigParser.parse(edited.text).config.enabledAgents == ["claude"] && ConfigParser.parse(edited.text).config.agents["mine"] == nil && !ConfigParser.parse(edited.text).hasErrors, "\(edited.text)")
        // One that the menu does not list has only its table to take out.
        let unlisted = try ConfigRequest(.remove, "agent.other").operations(in: ConfigDocument(text + "\n[agent.other]\nname = \"Other\"\ncommand = \"other\"\n"))
        #expect(unlisted.contains(.removeTable("agent.other")) && !unlisted.contains { if case .remove = $0 { true } else { false } })
    }

    @Test func anAgentOfOnesOwnIsNotMadeOrTakenOutByARequestThatDoesNotNameIt() throws {
        #expect(problem(ConfigRequest(.add, "agent", values: ["name=x", "command=y"]))?.contains("Name the agent") == true)
        #expect(problem(ConfigRequest(.remove, "agent"))?.contains("Name the agent") == true)
        #expect(problem(ConfigRequest(.remove, "agent.nothing"))?.contains("no agent \"nothing\" of your own") == true)
        #expect(problem(ConfigRequest(.add, "agent.mine", values: ["name"]))?.contains("not a field") == true)
        #expect(problem(ConfigRequest(.add, "agent.mine", values: []))?.contains("fields") == true)
        #expect(problem(ConfigRequest(.add, "agent.claude.variant.1", values: ["id=x"])) != nil)
        // The fields are typed by the schema: a command that is not text, a key the table does not have.
        #expect(problem(ConfigRequest(.add, "agent.mine", values: ["name=Mine", "nope=1"])) != nil)
    }
}
