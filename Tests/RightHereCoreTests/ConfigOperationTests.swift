import Foundation
import Testing
@testable import RightHereCore

@Suite("ConfigOperation: what the window, rh config and the MCP tool ask for")
struct ConfigOperationTests {
    private static let sample = """
    # Mine.
    [general]
    terminal = "ghostty" # keep
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
    """ + "\n"

    private let document = ConfigDocument(sample)

    @Test func eachOperationDoesWhatTheDocumentMethodDoes() throws {
        let fields = [ConfigField("id", .string("gamma")), ConfigField("title", .string("Gamma")), ConfigField("prompt", .string("Gamma {files}"))]
        let cases: [(ConfigOperation, ConfigDocument)] = [
            (.set("general.terminal", .string("terminal")), try document.setting("general.terminal", to: .string("terminal"))),
            (.unset("general.terminal"), try document.removing("general.terminal")),
            (.insert("open-with", into: "menu.items", at: 2), try document.insertingElement("open-with", into: "menu.items", at: 2)),
            (.insert("open-with", into: "menu.items", at: nil), try document.insertingElement("open-with", into: "menu.items")),
            (.remove(at: 2, from: "menu.items"), try document.removingElement(at: 2, from: "menu.items")),
            (.move(from: 4, to: 1, in: "menu.items"), try document.movingElement(from: 4, to: 1, in: "menu.items")),
            (.addEntry(to: "preset", fields: fields, at: 2), try document.addingEntry(to: "preset", fields: fields.map { ($0.key, $0.value) }, at: 2)),
            (.removeEntry(at: 1, from: "preset"), try document.removingEntry(at: 1, from: "preset")),
            (.moveEntry(from: 2, to: 1, in: "preset"), try document.movingEntry(from: 2, to: 1, in: "preset")),
            (.replaceText("[general]\nterminal = \"iterm\"\n"), try document.replacingText("[general]\nterminal = \"iterm\"\n"))
        ]
        for (operation, expected) in cases {
            let applied = try operation.apply(to: document)
            #expect(applied.text == expected.text, "\(operation.summary)")
            #expect(applied.text != document.text, "\(operation.summary) changed nothing")
        }
    }

    @Test func unsettingWhatIsNotSetChangesNothingButAnUnknownSettingIsRefused() throws {
        #expect(try ConfigOperation.unset("general.editor").apply(to: document).text == document.text)
        #expect(throws: ConfigDocument.EditError.unknownKey("general.nope")) { try ConfigOperation.unset("general.nope").apply(to: document) }
        // A table is not a value, whether the file has it or not.
        for path in ["general", "preset", "agent.claude"] {
            do {
                _ = try ConfigOperation.unset(path).apply(to: document)
                Issue.record("unsetting \(path) was accepted")
            } catch ConfigDocument.EditError.wrongKind(path: _, expected: _) {
            } catch {
                Issue.record("unsetting \(path): \(error)")
            }
        }
    }

    @Test func theSummaryIsOneLineThatSaysWhatWasAsked() {
        let cases: [(ConfigOperation, String)] = [
            (.set("general.terminal", .string("ghostty")), "set general.terminal = \"ghostty\""),
            (.set("general.bypass_permissions", .boolean(true)), "set general.bypass_permissions = true"),
            (.set("general.agents", .strings(["claude", "codex"])), "set general.agents = [\"claude\", \"codex\"]"),
            (.unset("general.editor"), "unset general.editor"),
            (.insert("open-with", into: "menu.items", at: 2), "add \"open-with\" to menu.items at 2"),
            (.insert("open-with", into: "menu.items", at: nil), "add \"open-with\" to menu.items"),
            (.remove(at: 3, from: "menu.items"), "remove item 3 of menu.items"),
            (.move(from: 3, to: 1, in: "menu.items"), "move item 3 of menu.items to 1"),
            (.addEntry(to: "preset", fields: [ConfigField("id", .string("review"))], at: nil), "add the preset entry \"review\""),
            (.addEntry(to: "preset", fields: [ConfigField("id", .string("review"))], at: 2), "add the preset entry \"review\" at 2"),
            (.removeEntry(at: 2, from: "preset"), "remove entry 2 of preset"),
            (.moveEntry(from: 2, to: 1, in: "preset"), "move entry 2 of preset to 1"),
            (.replaceText("anything"), "edit the text of the file")
        ]
        for (operation, summary) in cases { #expect(operation.summary == summary) }
        let long = ConfigOperation.set("general.agents", .strings((0..<40).map { "agent-\($0)" })).summary
        #expect(long.count == 90 && long.hasSuffix("..."), "a long value is cut: \(long.count)")
    }

    @Test func aSummaryNeverHoldsACharacterThatDrawsNothingOrTurnsTheLineAround() {
        // A value an assistant proposes is shown to the person as the summary; U+202E turns what follows it around, U+200B and a tag character draw nothing.
        let sneaky = "claude\u{202E}x\u{200B}y\u{E0041}z"
        for operation: ConfigOperation in [.set("agent.claude.command", .string(sneaky)), .insert(sneaky, into: "agent.claude.args", at: nil), .set("agent.claude.args", .strings([sneaky])),
                                           .addEntry(to: "app", fields: [ConfigField("id", .string(sneaky))], at: nil)] {
            let summary = operation.summary
            #expect(!summary.unicodeScalars.contains { [0x202E, 0x200B, 0xE0041].contains($0.value) }, "\(summary.debugDescription)")
            #expect(summary.contains("\\u202e") && summary.contains("\\u200b"), "\(summary)")
        }
        #expect(ConfigOperation.set("general.terminal", .string("ghostty")).summary == "set general.terminal = \"ghostty\"", "ordinary text is as it was")
    }

    @Test func aTextWithALineBreakIsSummarisedOnOneLine() {
        #expect(!ConfigOperation.set("copy_path.title", .string("a\nb")).summary.contains("\n"))
        #expect(ConfigOperation.set("copy_path.title", .string("a\nb")).summary == "set copy_path.title = \"a\\nb\"")
    }

    @Test func theSettingsItWritesAreNamedWithAndWithoutPositions() {
        #expect(ConfigOperation.set("general.terminal", .string("x")).settingPaths == ["general.terminal"])
        #expect(ConfigOperation.move(from: 1, to: 2, in: "menu.items").settingPaths == ["menu.items"])
        #expect(ConfigOperation.addEntry(to: "preset", fields: [], at: nil).settingPaths == [])
        #expect(ConfigOperation.set("preset.2.prompt", .string("x")).writtenKeys == ["preset.*.prompt"])
        #expect(ConfigOperation.set("agent.claude.args", .strings([])).writtenKeys == ["agent.*.args"])
        let fields = [ConfigField("id", .string("a")), ConfigField("prompt", .string("b"))]
        #expect(ConfigOperation.addEntry(to: "preset", fields: fields, at: nil).writtenKeys == ["preset.*.id", "preset.*.prompt"])
        let variant = [ConfigField("id", .string("fast")), ConfigField("arguments", .strings(["--fast"]))]
        #expect(ConfigOperation.addEntry(to: "agent.claude.variant", fields: variant, at: nil).writtenKeys == ["agent.*.variant.*.id", "agent.*.variant.*.arguments"])
        #expect(ConfigOperation.removeEntry(at: 2, from: "preset").writtenKeys == ["preset.*"])
        #expect(ConfigOperation.replaceText("x").writtenKeys == ["*"] && ConfigOperation.replaceText("x").settingPaths.isEmpty)
    }

    @Test func aCheckWritesNothingAndIsNotAWrittenSetting() throws {
        let check = ConfigOperation.expect(["claude", "codex"], in: "general.agents")
        #expect(check.isCheck && !ConfigOperation.set("general.terminal", .string("x")).isCheck)
        #expect(check.writtenKeys.isEmpty && check.settingPaths.isEmpty)
        #expect(check.summary == "check that general.agents is as it was read")
        #expect(try check.apply(to: document).text == document.text)
        #expect(ConfigTrust.approvals(for: [.expect(nil, in: "menu.items")]).isEmpty)
    }

    @Test func aCheckRefusesAListThatIsNotExactlyWhatWasRead() throws {
        let changed = ConfigDocument.EditError.changedMeanwhile("general.agents")
        #expect(throws: changed) { try ConfigOperation.expect(["claude"], in: "general.agents").apply(to: document) }
        #expect(throws: changed) { try ConfigOperation.expect(["codex", "claude"], in: "general.agents").apply(to: document) }
        #expect(throws: changed) { try ConfigOperation.expect(["claude", "codex", "gemini"], in: "general.agents").apply(to: document) }
        #expect(throws: changed) { try ConfigOperation.expect(nil, in: "general.agents").apply(to: document) }
        // A list the file does not write is not an empty one.
        #expect(try ConfigOperation.expect(nil, in: "services.items").apply(to: document).text == document.text)
        #expect(throws: ConfigDocument.EditError.changedMeanwhile("services.items")) { try ConfigOperation.expect([], in: "services.items").apply(to: document) }
        let empty = ConfigDocument("[menu]\nitems = []\n")
        #expect(try ConfigOperation.expect([], in: "menu.items").apply(to: empty).text == empty.text)
        #expect(throws: ConfigDocument.EditError.changedMeanwhile("menu.items")) { try ConfigOperation.expect(nil, in: "menu.items").apply(to: empty) }
        // It guards what follows it: the removal is not made on a list that is not the one that was shown.
        let removal: [ConfigOperation] = [.expect(["open-terminal", "open-editor", "-", "agents"], in: "menu.items"), .remove(at: 2, from: "menu.items")]
        var edited = document
        for operation in removal { edited = try operation.apply(to: edited) }
        #expect(try edited.elements(of: "menu.items") == ["open-terminal", "-", "agents"])
        let other = try document.insertingElement("presets", into: "menu.items", at: 1)
        #expect(throws: ConfigDocument.EditError.changedMeanwhile("menu.items")) {
            var changed = other
            for operation in removal { changed = try operation.apply(to: changed) }
        }
    }

    @Test func anEntryCheckRefusesAnEntryThatIsNotTheOneItWasForAndWritesNothing() throws {
        let document = ConfigDocument("[[preset]]\nid = \"alpha\"\ntitle = \"Alpha\"\nprompt = \"A {files}\"\n\n[[preset]]\nid = \"beta\"\ntitle = \"Beta\"\nprompt = \"B {files}\"\n")
        #expect(document.entryID(at: 2, in: "preset") == "beta" && document.entryID(at: 3, in: "preset") == nil && document.entryID(at: 1, in: "app") == nil)
        let check = ConfigOperation.expectEntry("beta", at: 2, in: "preset")
        #expect(check.isCheck && check.writtenKeys.isEmpty && check.settingPaths.isEmpty && ConfigTrust.approvals(for: [check]).isEmpty)
        #expect(check.summary == "check that entry 2 of preset is the one it was for")
        #expect(try check.apply(to: document).text == document.text)
        #expect(throws: ConfigDocument.EditError.changedMeanwhile("preset.1")) { try ConfigOperation.expectEntry("beta", at: 1, in: "preset").apply(to: document) }
        #expect(throws: ConfigDocument.EditError.changedMeanwhile("preset.3")) { try ConfigOperation.expectEntry("beta", at: 3, in: "preset").apply(to: document) }
        let moved = try document.movingEntry(from: 2, to: 1, in: "preset")
        #expect(throws: ConfigDocument.EditError.changedMeanwhile("preset.2")) { try check.apply(to: moved) }
        let data = try JSONEncoder().encode([check])
        #expect(try JSONDecoder().decode([ConfigOperation].self, from: data) == [check])
    }

    @Test func theCommentsOfAListThatHasNoItemOrNoItemAnyMoreAreTheListsAndStay() throws {
        let empty = ConfigDocument("[menu]\nitems = [\n    # nothing yet\n]\n")
        let filled = try empty.insertingElement("presets", into: "menu.items")
        #expect(filled.text.contains("# nothing yet") && filled.text.contains("\"presets\""), "\(filled.text)")
        #expect(try filled.elements(of: "menu.items") == ["presets"])
        let list = ConfigDocument("[menu]\nitems = [ # my menu\n    \"copy-path\", # the one\n    # trailing note\n]\n")
        let emptied = try list.removingElement(at: 1, from: "menu.items")
        #expect(emptied.text.contains("# my menu") && emptied.text.contains("# trailing note") && !emptied.text.contains("copy-path") && !emptied.text.contains("# the one"), "\(emptied.text)")
        #expect(try emptied.elements(of: "menu.items") == [])
    }

    @Test func aKeyWrittenInQuotesWithADotInItIsNotTheSettingItSpells() throws {
        let text = "\"general.terminal\" = \"kitty\"\n\n[general]\nterminal = \"ghostty\"\n"
        #expect(ConfigDocument(text).rawValue(at: "general.terminal") == "\"ghostty\"")
    }

    @Test func anItemOfAListCannotBeEmpty() {
        let document = ConfigDocument("[menu]\nitems = [\"agents\"]\n")
        #expect(throws: ConfigDocument.EditError.self) { try document.insertingElement("", into: "menu.items") }
        #expect(throws: ConfigDocument.EditError.self) { try document.insertingElement("  ", into: "menu.items") }
        #expect(throws: ConfigDocument.EditError.self) { try document.setting("menu.items", to: .strings(["agents", ""])) }
        #expect(throws: ConfigDocument.EditError.self) { try ConfigDocument("").insertingElement("", into: "menu.items") }
        #expect((try? document.setting("menu.items", to: .strings([]))) != nil, "a list with nothing in it is fine")
    }

    @Test func theSummaryOfAListIsOneLineWhateverItsLayoutWouldBe() {
        let summary = ConfigOperation.set("menu.items", .strings(MenuBuilder.defaultItems)).summary
        #expect(!summary.contains("  ") && !summary.contains("\n"), "\(summary)")
        #expect(summary.hasPrefix("set menu.items = [\"open-terminal\", \"open-editor\", \"open-with\""))
    }

    @Test func aTableMadeWithAProgramIsProposedAndSaysWhatItWrites() throws {
        let fields = [ConfigField("name", .string("lazygit")), ConfigField("command", .string("lazygit"))]
        let operation = ConfigOperation.addTable("agent.lazygit", fields: fields)
        #expect(operation.summary == "add the agent.lazygit table" && operation.settingPaths.isEmpty && !operation.isCheck)
        #expect(operation.writtenKeys == ["agent.*.name", "agent.*.command"])
        #expect(ConfigTrust.approvals(for: [operation]).map(\.key) == ["agent.*.command"], "the command is the program that starts the agent")
        let data = try JSONEncoder().encode([operation])
        #expect(try JSONDecoder().decode([ConfigOperation].self, from: data) == [operation])
        let applied = try operation.apply(to: ConfigDocument("")).text
        #expect(applied == "[agent.lazygit]\nname = \"lazygit\"\ncommand = \"lazygit\"\n")
    }

    @Test func aTableTakenOutIsProposedAndSaysWhatItRemoves() throws {
        let operation = ConfigOperation.removeTable("agent.lazygit")
        #expect(operation.summary == "remove the agent.lazygit table" && operation.settingPaths.isEmpty && !operation.isCheck && operation.writtenKeys == ["agent.*"])
        // What is taken out may be the override that keeps a built-in agent asking, or the program of an agent of one's own: it waits for the person.
        #expect(ConfigTrust.approvals(for: [operation]).map(\.key) == ["agent.*.command"])
        #expect(ConfigTrust.approvals(for: [.removeTable("agent.claude")]).map(\.key) == ["agent.*.command"])
        let data = try JSONEncoder().encode([operation])
        #expect(try JSONDecoder().decode([ConfigOperation].self, from: data) == [operation])
        let applied = try operation.apply(to: ConfigDocument("[agent.lazygit]\nname = \"lazygit\"\ncommand = \"lazygit\"\n")).text
        #expect(applied.isEmpty)
        #expect(throws: ConfigDocument.EditError.notFound("agent.lazygit")) { try operation.apply(to: ConfigDocument("")) }
    }

    @Test func aCheckOfSomethingThatIsNotAListOfTextIsRefusedAsSuch() {
        #expect(throws: ConfigDocument.EditError.self) { try ConfigOperation.expect(nil, in: "general.terminal").apply(to: document) }
        #expect(throws: ConfigDocument.EditError.self) { try ConfigOperation.expect(nil, in: "nonsense.items").apply(to: document) }
    }

    @Test func aCheckTravelsThroughJSONLikeTheOtherOperations() throws {
        let operations: [ConfigOperation] = [.expect(["a", "b"], in: "menu.items"), .expect(nil, in: "services.items"), .remove(at: 1, from: "menu.items")]
        let data = try JSONEncoder().encode(operations)
        #expect(try JSONDecoder().decode([ConfigOperation].self, from: data) == operations)
    }

    @Test func theItemsOfAListAreReadAsTheFileWritesThem() throws {
        let text = """
        [menu]
        items = [
            "open-terminal", # first
            # about this one
            'open-editor',
            "-", "copy-path",
        ]
        [general]
        agents = []
        """ + "\n"
        let document = ConfigDocument(text)
        #expect(try document.elements(of: "menu.items") == ["open-terminal", "open-editor", "-", "copy-path"])
        #expect(try document.elements(of: "general.agents") == [])
        #expect(try document.elements(of: "services.items") == nil, "not written is not empty")
        #expect(try ConfigDocument("[general]\nagents = [\"claude\", \"codex\"]\n").elements(of: "general.agents") == ["claude", "codex"])
        #expect(throws: ConfigDocument.EditError.self) { try document.elements(of: "general.terminal") }
    }
}

@Suite("ConfigDocument: values from arguments, lookups, and the overlay as a document")
struct ConfigDocumentArgumentTests {
    private func value(_ arguments: [String], _ path: String) throws -> ConfigDocument.Value {
        try ConfigDocument.value(from: arguments, at: path)
    }

    @Test func aTextIsTakenAsItIsAndNeverReadAsTOML() throws {
        #expect(try value(["ghostty"], "general.terminal") == .string("ghostty"))
        #expect(try value(["a \"quoted\" \\ text; $(rm -rf ~)"], "copy_path.title") == .string("a \"quoted\" \\ text; $(rm -rf ~)"))
        #expect(try value(["[\"claude\"]"], "copy_path.title") == .string("[\"claude\"]"))
        #expect(try value([""], "copy_path.title") == .string(""))
    }

    @Test func aNumberAndATruthValueAreChecked() throws {
        #expect(try value(["3"], "preset.1.max_files") == .integer(3))
        #expect(try value(["-1"], "preset.1.max_files") == .integer(-1))
        #expect(throws: ConfigDocument.EditError.self) { try value(["three"], "preset.1.max_files") }
        #expect(try value(["true"], "general.bypass_permissions") == .boolean(true))
        #expect(try value(["false"], "general.bypass_permissions") == .boolean(false))
        for wrong in ["yes", "True", "1", ""] {
            #expect(throws: ConfigDocument.EditError.self, "\"\(wrong)\"") { try value([wrong], "general.bypass_permissions") }
        }
    }

    @Test func aListTakesAnyNumberOfTextsAndEverythingElseExactlyOne() throws {
        #expect(try value(["claude", "codex"], "general.agents") == .strings(["claude", "codex"]))
        #expect(try value([], "general.agents") == .strings([]))
        for arguments in [[], ["a", "b"]] {
            #expect(throws: ConfigDocument.EditError.self, "\(arguments)") { try value(arguments, "general.terminal") }
        }
    }

    @Test func aTableIsNotAValueAndAnUnknownSettingIsRefused() {
        #expect(throws: ConfigDocument.EditError.self) { try value(["x"], "general") }
        #expect(throws: ConfigDocument.EditError.self) { try value(["x"], "preset") }
        #expect(throws: ConfigDocument.EditError.unknownKey("general.nope")) { try value(["x"], "general.nope") }
        #expect(throws: ConfigDocument.EditError.invalidPath("")) { try value(["x"], "") }
    }

    @Test func theMessageForANumberThatIsNotOneEscapesWhatWasTyped() {
        do {
            _ = try value(["\u{1B}[31m"], "preset.1.max_files")
            Issue.record("accepted")
        } catch {
            #expect(!(error.localizedDescription).contains("\u{1B}"), "\(error.localizedDescription.debugDescription)")
        }
    }

    @Test func anElementIsFoundByItsTextWhateverItsLayout() throws {
        let document = ConfigDocument("""
        [menu]
        items = [
            "open-terminal", # first
            # about this one
            'open-editor',
            "-",
        ]
        [general]
        agents = ["claude", "codex"]
        """ + "\n")
        #expect(try document.position(ofElement: "open-terminal", in: "menu.items") == 1)
        #expect(try document.position(ofElement: "open-editor", in: "menu.items") == 2)
        #expect(try document.position(ofElement: "-", in: "menu.items") == 3)
        #expect(try document.position(ofElement: "codex", in: "general.agents") == 2)
        #expect(try document.position(ofElement: "missing", in: "menu.items") == nil)
        #expect(try document.position(ofElement: "x", in: "services.items") == nil, "a list the file does not write has no elements")
        #expect(document.elementCount(of: "menu.items") == 3)
        #expect(document.elementCount(of: "general.agents") == 2)
        #expect(document.elementCount(of: "services.items") == 0)
        #expect(throws: ConfigDocument.EditError.self) { try document.position(ofElement: "x", in: "general.terminal") }
    }

    @Test func theFirstOfTwoEqualElementsIsTheOneFound() throws {
        let document = ConfigDocument("[menu]\nitems = [\"-\", \"a\", \"-\"]\n")
        #expect(try document.position(ofElement: "-", in: "menu.items") == 1)
    }

    @Test func theSchemaNodeOfASettingIsPublic() throws {
        #expect(try ConfigDocument.node(at: "general.terminal").kind == .string)
        #expect(try ConfigDocument.node(at: "preset").kind == .tableArray)
        #expect(try ConfigDocument.node(at: "preset.2.title").kind == .string)
        #expect(throws: ConfigDocument.EditError.self) { try ConfigDocument.node(at: "nope") }
    }
}

@Suite("ConfigDocument.Validation: the overlay is read over the shared file")
struct ConfigDocumentValidationTests {
    private static let base = """
    [[app]]
    id = "tower"
    name = "Tower"
    bundle_id = "com.fournova.Tower3"
    role = "terminal"

    [general]
    terminal = "ghostty"
    """ + "\n"

    @Test func anOverlayMayNameWhatOnlyTheSharedFileDefines() throws {
        let overlay = "[general]\nterminal = \"ghostty\"\n"
        let edited = try ConfigDocument(overlay, validation: .overlay(over: Self.base)).setting("general.terminal", to: .string("tower"))
        #expect(edited.text == "[general]\nterminal = \"tower\"\n")
        // Read on its own, that overlay names a terminal nobody defines.
        #expect(throws: ConfigDocument.EditError.self) { try ConfigDocument(overlay).setting("general.terminal", to: .string("tower")) }
    }

    @Test func anErrorOfTheOverlayRefusesTheEditAndOneOfTheSharedFileDoesNot() throws {
        let overlay = ConfigDocument("[general]\nterminal = \"ghostty\"\n", validation: .overlay(over: Self.base))
        #expect(throws: ConfigDocument.EditError.self) { try overlay.setting("general.terminal", to: .string("nonsense")) }
        // The shared file has an error of its own, one that the overlay does not hide (it cannot be read at all): the overlay is edited all the same.
        let broken = "[general\nterminal = \"ghostty\"\n"
        #expect(!ConfigLayers.load(base: .text(broken), local: .text("[general]\nterminal = \"ghostty\"\n")).diagnostics.filter { $0.severity == .error && $0.file == nil }.isEmpty,
                "the shared file's error is among the diagnostics of the pair, which is what the overlay's check must not blame the overlay for")
        let edited = try ConfigDocument("[general]\nterminal = \"ghostty\"\n", validation: .overlay(over: broken)).setting("general.terminal", to: .string("iterm"))
        #expect(edited.text.contains("iterm"))
    }

    @Test func anOverlayThatDoesNotExistYetIsAnEmptyOne() throws {
        let edited = try ConfigDocument("", validation: .overlay(over: Self.base)).setting("general.terminal", to: .string("tower"))
        #expect(edited.text == "[general]\nterminal = \"tower\"\n")
    }

    @Test func theValidationTravelsWithTheDocumentThroughEveryEdit() throws {
        var document = ConfigDocument("[general]\nterminal = \"ghostty\"\n", validation: .overlay(over: Self.base))
        document = try document.setting("general.terminal", to: .string("tower"))
        document = try document.insertingElement("claude", into: "general.agents")
        document = try document.setting("general.terminal", to: .string("tower"))
        #expect(document.text.contains("tower"))
    }

    @Test func twoDocumentsAreEqualWhenTheirTextIs() {
        #expect(ConfigDocument("a = 1\n") == ConfigDocument("a = 1\n", validation: .overlay(over: nil)))
        #expect(ConfigDocument("a = 1\n") != ConfigDocument("a = 2\n"))
    }

    @Test func anArgumentWithABackslashIsRefusedWhereItIsWritten() throws {
        // At the start the agent would be refused for it (`AgentLaunchResolution`): the page that wrote it said nothing, and every start failed.
        let base = ConfigDocument("[agent.claude]\nargs = [\"-p\"]\n\n[[agent.claude.variant]]\nid = \"x\"\ntitle = \"X\"\narguments = [\"--a\"]\n")
        for operation in [ConfigOperation.set("agent.claude.args", .strings(["C:\\temp"])), .insert("C:\\temp", into: "agent.claude.args", at: nil), .replace(at: 1, in: "agent.claude.args", with: "a\\b"),
                          .set("agent.claude.variant.1.arguments", .strings(["a\\b"])), .insert("a\\b", into: "agent.claude.variant.1.arguments", at: nil)] {
            #expect(throws: ConfigDocument.EditError.self, "\(operation.summary)") { try operation.apply(to: base) }
        }
        do { _ = try ConfigOperation.insert("C:\\temp", into: "agent.claude.args", at: nil).apply(to: base) } catch {
            #expect("\(error.localizedDescription)".contains("a backslash is refused when the agent starts"), "\(error.localizedDescription)")
        }
        // Only an argument of an agent: a path in a menu title or a list of text of another kind is not what this is about.
        #expect(try ConfigOperation.set("copy_path.title", .string("C:\\x")).apply(to: base).text.contains("C:"))
        #expect(try ConfigOperation.insert("a", into: "agent.claude.args", at: nil).apply(to: base).text.contains("\"a\""))
    }

    @Test func anItemWrittenAnotherWayKeepsItsComments() throws {
        let base = ConfigDocument("[agent.claude]\nargs = [\n    # keep the model fixed\n    \"--modle\",\n    \"opus\", # the best one\n    \"--verbose\",\n]\n")
        let fixed = try ConfigOperation.replace(at: 1, in: "agent.claude.args", with: "--model").apply(to: base)
        #expect(fixed.text == "[agent.claude]\nargs = [\n    # keep the model fixed\n    \"--model\",\n    \"opus\", # the best one\n    \"--verbose\",\n]\n", "\(fixed.text)")
        let changed = try ConfigOperation.replace(at: 2, in: "agent.claude.args", with: "sonnet").apply(to: fixed)
        #expect(changed.text.contains("\"sonnet\", # the best one") && changed.text.contains("# keep the model fixed"), "\(changed.text)")
        #expect(try ConfigDocument.node(at: "agent.claude.args").kind == .stringArray)
        #expect(throws: ConfigDocument.EditError.self) { try ConfigOperation.replace(at: 4, in: "agent.claude.args", with: "x").apply(to: base) }
        #expect(throws: ConfigDocument.EditError.self) { try ConfigOperation.replace(at: 1, in: "agent.claude.args", with: "  ").apply(to: base) }
        #expect(throws: ConfigDocument.EditError.self) { try ConfigOperation.replace(at: 1, in: "general.terminal", with: "x").apply(to: base) }
        #expect(ConfigOperation.replace(at: 1, in: "agent.claude.args", with: "x").summary == "replace item 1 of agent.claude.args with \"x\"")
        #expect(ConfigTrust.approvals(for: [.replace(at: 1, in: "agent.claude.args", with: "x")]).map(\.key) == ["agent.*.args"], "an argument written another way is a program setting changed")
        let data = try JSONEncoder().encode([ConfigOperation.replace(at: 1, in: "agent.claude.args", with: "x")])
        #expect(try JSONDecoder().decode([ConfigOperation].self, from: data) == [.replace(at: 1, in: "agent.claude.args", with: "x")])
    }
}
