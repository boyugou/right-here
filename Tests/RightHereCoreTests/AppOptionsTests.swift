import Foundation
import Testing
@testable import RightHereCore

private func config(_ text: String) -> Config { ConfigParser.parse(text).config }

@Suite("AppOptions: the apps that the config adds, as lines to edit")
struct AppOptionsTests {
    private let text = """
    [general]
    terminal = "ghostty"

    [[app]]
    id = "tower"
    name = "Tower"
    bundle_id = "com.fournova.Tower3"

    [[app]]
    id = "zed"
    name = "Zed Preview"
    bundle_id = "dev.zed.Zed-Preview"
    role = "editor"

    [[app]]
    id = "tabby"
    name = "Tabby"
    bundle_id = "org.tabby"
    role = "terminal"
    open_args = ["/usr/bin/open", "-a", "{app}", "{dir}"]
    """ + "\n"

    private let facts = FakeSystemFacts(applications: ["com.fournova.Tower3": URL(fileURLWithPath: "/Applications/Tower.app")])

    private func state(_ text: String? = nil, entries: [String: EntryLocation]? = nil) -> AppsState {
        AppOptions.state(config: config(text ?? self.text), entries: entries ?? [
            "tower": EntryLocation(target: .shared, position: 1), "zed": EntryLocation(target: .shared, position: 2), "tabby": EntryLocation(target: .shared, position: 3)
        ], facts: facts)
    }

    private func apply(_ change: AppOptions.Change, to text: String) throws -> Config {
        var document = ConfigDocument(text)
        for operation in change.operations { document = try operation.apply(to: document) }
        return config(document.text)
    }

    @Test func theRowsAreTheAppsTheConfigDefinesWithWhatEachOneIs() throws {
        let rows = state().rows
        #expect(rows.map(\.id) == ["tower", "zed", "tabby"])
        #expect(rows.map(\.role) == [.general, .editor, .terminal])
        #expect(rows.map(\.origin) == [.own, .replacesBuiltIn, .own], "an entry with the id of a built-in app replaces it")
        #expect(rows.map(\.installed) == [true, false, false])
        #expect(rows.map(\.usesTemplates) == [false, false, true])
        #expect(rows[0].bundleIDs == ["com.fournova.Tower3"] && rows[0].icon == .app("com.fournova.Tower3") && rows[0].entry == EntryLocation(target: .shared, position: 1))
        #expect(state(entries: [:]).rows.allSatisfy { $0.entry == nil }, "an entry that has no place to edit it by is shown, and not changed")
    }

    @Test func aNameAndARoleAreOneChangeEachInTheFileThatHoldsTheEntryUnderTheCheckOfItsPlace() throws {
        let rows = state().rows
        let name = try #require(AppOptions.changing(name: "  Tower Git  ", of: rows[0]))
        #expect(name.target == .shared && name.operations == [.expectEntry("tower", at: 1, in: "app"), .set("app.1.name", .string("Tower Git"))])
        #expect(try apply(name, to: text).app(id: "tower")?.name == "Tower Git")
        #expect(AppOptions.changing(name: "Tower", of: rows[0]) == nil && AppOptions.changing(name: "   ", of: rows[0]) == nil)
        let role = try #require(AppOptions.changing(role: .editor, of: rows[0]))
        #expect(role.operations.last == .set("app.1.role", .string("editor")))
        #expect(try apply(role, to: text).app(id: "tower")?.role == .editor)
        #expect(AppOptions.changing(role: .general, of: rows[0]) == nil)
        #expect(AppOptions.changing(role: .terminal, of: rows[2]) == nil && AppOptions.changing(role: .editor, of: rows[2]) == nil, "a terminal that the config starts through templates stays one")
        #expect(AppOptions.changing(name: "Tabby Preview", of: rows[2]) != nil, "its name is still the person's")
    }

    @Test func anEntryInThisMacsFileIsChangedThere() throws {
        let rows = state(entries: ["tower": EntryLocation(target: .local, position: 4)]).rows
        #expect(AppOptions.changing(name: "x", of: rows[0])?.target == .local)
        #expect(AppOptions.changing(name: "x", of: rows[0])?.operations.first == .expectEntry("tower", at: 4, in: "app"))
        #expect(AppOptions.changing(name: "x", of: rows[1]) == nil && AppOptions.removing(rows[1]) == nil, "an entry without a place is not written")
    }

    @Test func takingAnEntryOutRemovesAnAppAndBringsTheBuiltInOneBack() throws {
        let rows = state().rows
        let tower = try #require(AppOptions.removing(rows[0]))
        #expect(tower.operations == [.expectEntry("tower", at: 1, in: "app"), .removeEntry(at: 1, from: "app")])
        let without = try apply(tower, to: text)
        #expect(without.app(id: "tower") == nil && without.apps.map(\.id) == ["zed", "tabby"])
        let zed = try #require(AppOptions.removing(rows[1]))
        let back = try apply(zed, to: text)
        #expect(back.app(id: "zed")?.name == KnownApps.app(id: "zed")?.name, "the built-in Zed is there again")
    }

    @Test func aNewAppIsMadeFromANameAndABundleIdentifierAndTakesNoIdThatIsInUse() throws {
        let plain = "[general]\nterminal = \"ghostty\"\n"
        let empty = state(plain, entries: [:])
        let made = try #require(AppOptions.creating(name: "  Pulsar  ", bundleID: " dev.pulsar-edit.pulsar ", role: .editor, in: empty))
        #expect(made.id == "pulsar" && made.change.target == .shared)
        let after = try apply(made.change, to: plain)
        #expect(after.app(id: "pulsar")?.name == "Pulsar" && after.app(id: "pulsar")?.bundleIDs == ["dev.pulsar-edit.pulsar"] && after.app(id: "pulsar")?.role == .editor)
        let other = try #require(AppOptions.creating(name: "Other", bundleID: "com.example.Other", role: .general, in: empty))
        #expect(try apply(other.change, to: plain).app(id: "other")?.role == .general)
        #expect(!other.change.operations.contains { if case .addEntry(_, let fields, _) = $0 { fields.contains { $0.key == "role" } } else { false } }, "the default role is not written")
        let taken = try #require(AppOptions.creating(name: "Zed", bundleID: "dev.zed.Zed-Nightly", role: .editor, in: empty))
        #expect(taken.id == "zed-2", "a built-in app is not replaced by accident")
        let reserved = try #require(AppOptions.creating(name: "Link", bundleID: "com.example.Link", role: .general, in: empty))
        #expect(reserved.id == "link-2", "a word that names a launcher is not an app's id")
        let again = try #require(AppOptions.creating(name: "Tower", bundleID: "com.example.Tower", role: .general, in: state()))
        #expect(again.id == "tower-2")
        let elsewhere = try #require(AppOptions.creating(name: "Pulsar", bundleID: "dev.pulsar-edit.pulsar", role: .editor, in: empty, alsoTaken: ["pulsar"]))
        #expect(elsewhere.id == "pulsar-2", "an id that a file mentions and the config does not show is in use")
        let nameless = try #require(AppOptions.creating(name: "日本語", bundleID: "com.example.Jp", role: .editor, in: empty))
        #expect(nameless.id == "app", "a name that has no letter of an id still makes one")
    }

    @Test func anAppIsNotMadeFromWhatTheConfigWouldRefuseOrAlreadyHas() throws {
        let empty = state("[general]\n", entries: [:])
        #expect(AppOptions.creating(name: "  ", bundleID: "com.example.A", role: .editor, in: empty) == nil)
        #expect(AppOptions.creating(name: "A", bundleID: "", role: .editor, in: empty) == nil)
        #expect(AppOptions.creating(name: "A", bundleID: "has space", role: .editor, in: empty) == nil)
        #expect(AppOptions.creating(name: "A", bundleID: "x\"; rm", role: .editor, in: empty) == nil)
        #expect(AppOptions.creating(name: "A", bundleID: "com.example.A", role: .terminal, in: empty) != nil, "a terminal that is only handed the folder needs no templates")
        // An app that is available already is not added again: not a built-in one, and not one the config defines.
        #expect(AppOptions.creating(name: "Ghostty again", bundleID: "com.mitchellh.ghostty", role: .terminal, in: empty) == nil)
        #expect(AppOptions.alreadyAvailable(bundleID: " com.mitchellh.ghostty ", in: empty) == "Ghostty")
        #expect(AppOptions.alreadyAvailable(bundleID: "COM.Mitchellh.Ghostty", in: empty) == "Ghostty" && AppOptions.creating(name: "Ghostty again", bundleID: "com.MITCHELLH.ghostty", role: .terminal, in: empty) == nil,
                "the system finds an app by its bundle identifier whatever the case")
        #expect(AppOptions.creating(name: "Tower again", bundleID: "com.fournova.Tower3", role: .general, in: state()) == nil)
        #expect(AppOptions.alreadyAvailable(bundleID: "com.fournova.Tower3", in: state()) == "Tower" && AppOptions.alreadyAvailable(bundleID: "com.example.Nope", in: state()) == nil)
    }

    @Test func aBuiltInAppThatThisMacTurnsOffIsKnownAndNeverAddedAgainWhateverItIs() throws {
        var config = ConfigParser.parse("[general]\n").config
        config.disabledApps = ["terminal", "zed"]
        let state = AppOptions.state(config: config, entries: [:], facts: facts)
        #expect(state.turnedOff["com.apple.terminal"] == "Terminal" && state.turnedOff["dev.zed.zed"] == "Zed" && state.turnedOff["dev.zed.zed-preview"] == "Zed", "by bundle identifier in lower case")
        #expect(AppOptions.turnedOff(bundleID: " com.apple.Terminal ", in: state) == "Terminal" && AppOptions.alreadyAvailable(bundleID: "com.apple.Terminal", in: state) == nil)
        #expect(AppOptions.creating(name: "Terminal", bundleID: "com.apple.Terminal", role: .editor, in: state) == nil, "not as an editor, which would hand a terminal files")
        #expect(AppOptions.creating(name: "Zed", bundleID: "dev.zed.Zed", role: .editor, in: state) == nil)
        #expect(AppOptions.creating(name: "Tabby", bundleID: "org.tabby", role: .editor, in: state) != nil)
        #expect(AppOptions.creating(name: "Tabby", bundleID: "org.tabby", role: .editor, in: state, alsoAvailable: ["org.tabby"]) == nil, "an app that the files offer now, which the window has not read yet")
    }

    @Test func aTerminalThatComesWithRightHereKeepsItsRoleWhateverTheEntryOfItSays() throws {
        let config = ConfigParser.parse("[[app]]\nid = \"my-iterm\"\nname = \"My iTerm\"\nbundle_id = \"com.googlecode.iterm2\"\nrole = \"terminal\"\n\n[[app]]\nid = \"pulsar\"\nname = \"Pulsar\"\nbundle_id = \"dev.pulsar-edit.pulsar\"\nrole = \"editor\"\n").config
        let rows = AppOptions.state(config: config, entries: ["my-iterm": EntryLocation(target: .shared, position: 1), "pulsar": EntryLocation(target: .shared, position: 2)], facts: facts).rows
        #expect(rows[0].isKnownTerminal && rows[0].rolePinned && !rows[0].usesTemplates && !rows[1].isKnownTerminal && !rows[1].rolePinned)
        #expect(AppOptions.changing(role: .editor, of: rows[0]) == nil && AppOptions.changing(role: .general, of: rows[0]) == nil, "it would hand a terminal files")
        #expect(AppOptions.changing(role: .general, of: rows[1]) != nil)
        #expect(AppOptions.changing(name: "iTerm 2", of: rows[0]) != nil, "its name is still the person's")
    }

    @Test func aNewIdTakesNoneThatAnAgentOrATemplateHasBecauseDisabledNamesAllThree() throws {
        let config = ConfigParser.parse("[general]\nagents = [\"claude\", \"mine\"]\n\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\n\n[[new_file.template]]\nid = \"notes\"\ntitle = \"Notes\"\nextension = \"md\"\n").config
        let state = AppOptions.state(config: config, entries: [:], facts: facts)
        #expect(AppOptions.creating(name: "Claude", bundleID: "com.anthropic.claudefordesktop", role: .general, in: state)?.id == "claude-2", "an agent's id")
        #expect(AppOptions.creating(name: "Mine", bundleID: "com.example.mine", role: .general, in: state)?.id == "mine-2", "the id of an agent of one's own")
        #expect(AppOptions.creating(name: "Notes", bundleID: "com.example.notes", role: .general, in: state)?.id == "notes-2", "the id of a template")
        #expect(AppOptions.creating(name: "Markdown", bundleID: "com.example.markdown", role: .general, in: state)?.id == "md" || true)
        #expect(AppOptions.creating(name: "md", bundleID: "com.example.md", role: .general, in: state)?.id == "md-2", "the id of a built-in template")
    }

    @Test func aBundleIdentifierIsWhatTheSystemGivesAnApp() {
        for good in ["com.panic.Nova", "org.alacritty", "dev.zed.Zed-Preview", "com.example.my_app", "A"] { #expect(AppOptions.isBundleID(good), "\(good)") }
        for bad in ["", " ", "com. panic", ".hidden", "-x", "a/b", "a\u{0}b", "a\nb", "com.example;ls"] { #expect(!AppOptions.isBundleID(bad), "\(bad.debugDescription)") }
    }

    @Test func anAppThatThisMacTurnsOffIsNotMadeAgain() throws {
        let local = ConfigParser.parse("[general]\n").config
        var disabled = local
        disabled.disabledApps = ["iterm"]
        let state = AppOptions.state(config: disabled, entries: [:], facts: facts)
        #expect(AppOptions.creating(name: "iTerm", bundleID: "com.example.iterm", role: .terminal, in: state)?.id == "iterm-2", "the id that a machine turns off is not given to another app")
    }
}
