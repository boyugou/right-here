import Foundation
import Testing
@testable import RightHereCore

private func plist(_ data: Data) throws -> [String: Any] {
    try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
}

private func commandString(of document: Data) throws -> String? {
    let actions = try #require(try plist(document)["actions"] as? [[String: Any]])
    let action = try #require(actions.first?["action"] as? [String: Any])
    return (action["ActionParameters"] as? [String: Any])?["COMMAND_STRING"] as? String
}

private func menuTitle(of info: Data) throws -> String? {
    let services = try #require(try plist(info)["NSServices"] as? [[String: Any]])
    return (services.first?["NSMenuItem"] as? [String: String])?["default"]
}

private let facts = FakeSystemFacts(applications: [
    "com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"),
    "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
])

/// From an independent review of the Quick Actions (2026-11-05): what a config (one pulled from the sync folder included) can put into a generated workflow.
@Suite("Quick Actions: config text in the Quick Actions")
struct QuickActionsReviewCoreTests {
    /// Titles full of shell and XML syntax reach the workflow only as property-list text (the menu title, the bundle name); the shell script holds the action id and `rh`'s path, nothing else.
    @Test func hostileTitlesReachTheWorkflowOnlyAsPlistTextAndTheScriptOnlyAsAnActionID() throws {
        let text = #"""
        [general]
        agents = ["claude"]
        terminal = "ghostty"

        [[agent.claude.variant]]
        id = "v1"
        title = "it's \"$(touch /tmp/rh-pwned)\" `id` ; echo $HOME"
        arguments = ["--x"]

        [[preset]]
        id = "p1"
        title = "Review'; rm -rf ~ # ]]> & <b> \\ \"$@\""
        agent = "claude"
        prompt = "Review {files}"

        [[new_file.template]]
        id = "t1"
        title = "Note: a/b/../../c 'x' $(id) 😀 á́́"
        extension = "txt"

        [services]
        items = ["agent.claude.v1", "preset.p1", "new-file.t1", "agent.claude.v1@ghostty", "preset.p1@ghostty"]
        """#
        let parsed = ConfigParser.parse(text)
        #expect(!parsed.hasErrors, "\(parsed.diagnostics.map(\.message))")
        let rh = "/Applications/Right Here.app/Contents/Helpers/rh"
        let specs = ActionRegistry(config: parsed.config, facts: facts).serviceSpecs(rhPath: rh)
        #expect(specs.count == 5, "\(specs.map(\.title))")
        let idPattern = /^[a-z0-9.@-]+$/
        for spec in specs {
            #expect(spec.actionID.wholeMatch(of: idPattern) != nil, "an action id with other characters: \(spec.actionID)")
            #expect(spec.command == ServiceWorkflow.command(rhPath: rh, actionID: spec.actionID))
            #expect(try commandString(of: ServiceWorkflow.workflowDocument(for: spec)) == spec.command)
            #expect(try menuTitle(of: ServiceWorkflow.infoPlist(for: spec)) == spec.title, "the title does not read back from the Info.plist: \(spec.title)")
            let name = ServiceWorkflow.bundleName(for: spec)
            #expect(name.hasPrefix(ServiceWorkflow.namePrefix) && name.hasSuffix(".workflow") && !name.unicodeScalars.contains("/") && !name.unicodeScalars.contains("\0"))
        }
    }

    /// What a Quick Action runs is `rh run --alert <id> --origin services -- <items>`, the entry a Finder click reaches through the runner script. A change of
    /// `services.items` alone matters to the guard of a pull only where the list decides what starts, and both of those places already read it.
    @Test func aChangeOfTheQuickActionsAloneIsListedExactlyWhereItDecidesWhatStarts() {
        func changes(_ before: String, _ after: String) -> [String] {
            LaunchCommands.changes(from: Data(before.utf8), to: Data(after.utf8), overlay: nil).map(\.line)
        }
        // An agent offered while the prompts are off.
        let off = "[general]\nbypass_permissions = true\nagents = [\"claude\"]\n"
        #expect(changes(off, off + "\n[services]\nitems = [\"agent.codex\"]\n").contains { $0.contains("[agent.codex] offered with its permission prompts switched off") })
        // A terminal that starts through a template of its own, named by a Quick Action.
        let remote = "[[app]]\nid = \"remote\"\nname = \"Remote\"\nbundle_id = \"com.example.remote\"\nrole = \"terminal\"\nopen_args = [\"/usr/bin/ssh\", \"host\", \"{dir}\"]\n"
        #expect(changes(remote, remote + "\n[services]\nitems = [\"open.terminal@remote\"]\n").contains { $0.contains("an item of the menu or of the Quick Actions: open.terminal@remote") })
        // What only adds a click for something the config has already (a built-in action, a template of its own): nothing new starts.
        let template = "[[new_file.template]]\nid = \"note\"\ntitle = \"Note\"\nextension = \"md\"\n"
        #expect(changes(template, template + "\n[services]\nitems = [\"new-file.note\", \"copy-path.absolute\", \"agent.claude\", \"reveal\"]\n").isEmpty)
    }

    /// Two templates whose titles APFS takes for one name (U+0412 and U+1C80, which Unicode's case folding maps to one letter and Foundation's did not) are a valid config,
    /// and a pull asks nothing about them (no contents, no program). `fold` gave them two names, and the installer staged both into one folder; it gives them one now, and
    /// the first is kept, as for `Notes` and `notes`.
    @Test func twoTemplatesTheVolumeTakesForOneNameAreAValidConfigThatAPullAsksNothingAbout() throws {
        let base = "[general]\nagents = [\"claude\"]\n"
        let pulled = base + """

        [[new_file.template]]
        id = "one"
        title = "\u{0412}x"
        extension = "txt"

        [[new_file.template]]
        id = "two"
        title = "\u{1C80}x"
        extension = "txt"

        [services]
        items = ["new-file.one", "new-file.two", "copy-path.absolute"]
        """
        let parsed = ConfigParser.parse(pulled)
        #expect(!parsed.hasErrors, "\(parsed.diagnostics.map(\.message))")
        #expect(LaunchCommands.changes(from: Data(base.utf8), to: Data(pulled.utf8), overlay: nil).isEmpty, "a pull would ask about it")
        let specs = ActionRegistry(config: parsed.config, facts: facts).serviceSpecs(rhPath: "/x/rh")
        #expect(specs.map(\.actionID) == ["new-file.one", "new-file.two", "copy-path.absolute"])
        #expect(ServiceWorkflow.distinct(specs).map(\.actionID) == ["new-file.one", "copy-path.absolute"])
    }

    /// The menu takes the first 256 entries of its list, and so do the Quick Actions (they took every entry, from a pulled config that asks nothing).
    @Test func theQuickActionsListHasALimitLikeTheMenus() throws {
        let count = 400
        var pulled = "[general]\nagents = []\n"
        for index in 0..<count { pulled += "\n[[new_file.template]]\nid = \"t\(index)\"\ntitle = \"Kind \(index)\"\nextension = \"txt\"\n" }
        pulled += "\n[services]\nitems = [" + (0..<count).map { "\"new-file.t\($0)\"" }.joined(separator: ", ") + "]\n"
        let parsed = ConfigParser.parse(pulled)
        #expect(!parsed.hasErrors, "\(parsed.diagnostics.prefix(3).map(\.message))")
        #expect(LaunchCommands.changes(from: Data("[general]\nagents = []\n".utf8), to: Data(pulled.utf8), overlay: nil).isEmpty)
        let specs = ServiceWorkflow.distinct(ActionRegistry(config: parsed.config, facts: facts).serviceSpecs(rhPath: "/x/rh"))
        #expect(specs.count <= 256, "\(specs.count) Quick Actions from one pulled config; the menu stops at 256")
    }
}
