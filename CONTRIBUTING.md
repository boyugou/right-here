# Contributing

Contributions are welcome. Right Here uses the Apache-2.0 license.

- When you take part, you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
- Report a vulnerability in private. [`SECURITY.md`](SECURITY.md) says how.
- [`docs/INDEX.md`](docs/INDEX.md) lists the design notes and the decision records.
- [`CLAUDE.md`](CLAUDE.md) is for coding agents. This page has everything that a person needs.

## Your contribution's license

- What you contribute is licensed under the Apache License 2.0, as section 5 of the license says for every contribution to a
  project under it. You keep the copyright of what you write.
- Sign off each commit (`git commit -s`). The sign-off says that you may contribute the change under the project's license, as
  the [Developer Certificate of Origin 1.1](https://developercertificate.org) puts it.
- Add your name to [`AUTHORS`](AUTHORS) in your first pull request, if you like. NOTICE says "The Right Here Authors" for all of us.
- Write the code yourself. Do not copy code from another project, above all a GPL one; read other projects' documentation, not their
  code.

## What you need

| Tool | Why |
| --- | --- |
| A Mac with Apple silicon and macOS 26 or later | Right Here runs only there. |
| Xcode 26 or later (the full app) | `swift test` and the app build need it. The Command Line Tools alone run only `swift build`. |
| `xcodegen` (`brew install xcodegen`) | It makes the Xcode project. The repository does not keep the `.xcodeproj`. |
| `uv` (`brew install uv`) | The gate runs its Python checks with it. |
| `git` | — |
| `fish`, `dash`, `ksh` (optional) | The quoting tests try every shell that they find. |

## Build and test

```sh
swift build                    # the libraries and rh
swift test                     # the tests; none of them touches your home folder, Finder or your apps
./script/verify_all.sh         # the gate: what CI runs
./script/install_local.sh      # builds the app and installs it for you
./script/mutation_check.py     # removes each protection in a copy of HEAD and expects a test to fail (slow)
```

The gate builds `rh`, the app and the Finder extension. It runs the tests and checks:

- the translations,
- the config schema,
- the guides that `rh docs` prints,
- the commands and the links in the documents,
- that no file has an email address, a path of your Mac or a key.

Run the gate before you open a pull request. Run `./script/mutation_check.py` after you change a protection. For example:
quoting, planning, the limits of the MCP server, or the probe.

[`docs/development/SETUP.md`](docs/development/SETUP.md) gives more about the build and the install.

## Tests

- **A fix comes with a test that fails without the fix.**
- **A test makes its bad input.** For example, the quoting tests send every shell metacharacter, with every combining mark, through
  real shells.
- **A test does not open a window, send an Apple event or touch your config.** Use fake system facts, a fake process runner, a
  temporary folder, or `RH_HOME` and `RH_CONFIG_DIR`.
- **A test that runs the real `rh` gives it an empty home.** Then your shell's startup files do not run.

To see what an action does without doing it, run `rh run <id> --dry-run`. To check a click on a real Mac, run
`rh doctor --probe-launch`. A terminal window opens and closes.

## Rules

- **Swift 6 with strict concurrency.** Do not force-unwrap outside tests. A value that goes from one actor to another is
  `Sendable`.
- **A comment gives a reason that the code cannot show.** For example: a quirk of macOS, or a hidden constraint.
- **File names are data.** Never put a file name into the text of a shell command or of an AppleScript. Give it as an argument, or
  quote it with `ShellQuoting`.
- **`ShellQuoting` works on Unicode scalars.** A quote that a combining mark follows is still a quote to a shell.
- **A terminal only gets folders.** A terminal runs a file that it gets.
- **The core is pure.** `Sources/RightHereCore` plans an action and does nothing else. Its tests are unit tests. The side effects
  are in `Sources/RightHereKit`.
- **The Finder extension stays small.** It uses no network. It reads only the cached config.
- **No code from GPL projects.** Read other projects' documents and issues to learn the problem. Write the code yourself.
- **A claim about macOS is checked on a real Mac.** [`docs/DESIGN.md`](docs/DESIGN.md) marks each claim as verified, sourced or
  open.
- **Commit in small steps.** Each commit builds, and its tests pass.
- **Text that people read follows [`docs/development/WRITING.md`](docs/development/WRITING.md).** `uv run script/writing_report.py`
  measures it.
- **`rh` contains its guides.** After you change `docs/TROUBLESHOOTING.md` or another guide, run `script/compile_docs.py`. The gate
  checks this.

## Add a terminal

**A terminal that its command line can start needs no code.**

1. Add an `[[app]]` entry with `role = "terminal"`, `open_args` and `run_args` to your config. `rh docs config` explains them.
2. Run `rh config validate`.
3. Run `rh run <action> --dry-run` to see the command.
4. Try it on a real Mac. [`docs/development/MANUAL_CHECKS.md`](docs/development/MANUAL_CHECKS.md) lists what to try.

**A built-in terminal is one row** in `KnownApps.terminals` (`Sources/RightHereCore/Catalog/AppDescriptor.swift`):

| Field | Meaning |
| --- | --- |
| `driver` | How Right Here starts it. `.openFolder` gives it the folder. `.template(TerminalLaunch(open:run:))` starts it from a list of arguments, as an `[[app]]` entry does. |
| `defaultRank` | Its place when Right Here picks the first installed terminal. Lower comes first. Without it, Right Here never picks it, but a config can name it. |

**A terminal that needs its own code** (for example, a scripting dictionary) also gets:

1. a case in `AppDescriptor.Driver`,
2. an adapter next to `GhosttyAdapter` in `Sources/RightHereCore/Terminals/`,
3. a line in `TerminalAdapters.adapter(for:)` that maps the case to the adapter,
4. tests in `TerminalAdapterTests`.

The adapter checks that the working directory is a folder. It gives paths as arguments, never as script text. In the pull request,
say which version of the terminal you tried.

**An editor is one row** in `KnownApps.editors`. A `defaultRank` makes it a candidate for the default editor.

## Add an agent

1. Add an `AgentDescriptor` to `Sources/RightHereCore/Catalog/AgentDescriptor.swift`: its id, name, command, start options and icon.
2. Add it to `AgentDescriptor.all`.
3. Add it to the planner tests.

A person can also add an agent in the config, with no code.

## Fix a translation

Right Here is in English and 29 other languages. Machines made all 29 translations, and they wait for review. A correction from a native speaker helps a lot.

1. Open `Localization/Localizable.xcstrings`. The text of the permission prompts is in `Localization/InfoPlist.xcstrings`, the
   Shortcuts actions are in `Localization/AppIntents.xcstrings`, and their Siri and Spotlight phrases in `Localization/AppShortcuts.xcstrings`.
2. Fix what reads badly. Use the words that macOS itself uses in that language.
3. Change `"state"` to `"translated"` in each entry that you checked.
4. Run `./script/compile_localizations.py` and `./script/verify_localizations.py`.
5. Look at the setup window in that language: `./script/preview_setup.sh out.png <language>`.

`preview_setup.sh` takes these options:

| Option | What it renders |
| --- | --- |
| `--dark` | The window in dark mode. |
| `--gallery` | Every sentence that the doctor can say, one row each. Use it to find text that does not fit. |
| `--demo` | A healthy setup with a sample Finder menu. It shows nothing of your Mac, except the icons of the apps. |

## Add a language

1. **Add the language to `Localization/languages.json`.** Give its code, its English name and its script (ISO 15924). Add
   `"rtl": true` if it is written from right to left. The scripts and the tests read only this list.
2. **List the missing strings.** `./script/verify_localizations.py --missing <code>` lists them, in all four catalogs.
3. **Write the translations** in a JSON file for each catalog: `{"key": {"translations": {"<code>": "text"}}}`.
4. **Add them** with `./script/merge_translations.py file.json`. For the other catalogs, add `--catalog AppIntents.xcstrings`,
   `InfoPlist.xcstrings` or `AppShortcuts.xcstrings`.
5. **Run** `./script/compile_localizations.py`. Then `./script/verify_localizations.py` and `swift test` must pass.
6. **Check the words of macOS** with `./script/verify_macos_wording.py`.
7. **Look at the window** with `./script/preview_setup.sh out.png <code>`.

`merge_translations.py` checks the placeholders, the commands between backticks and the script of the language. It adds the
right-to-left mark where a text needs it. It writes nothing unless every text passes. It marks each text `needs_review`.
`--reviewed` marks them `translated`. Use it only for a native speaker's correction of their own language.

Keep `%@`, `%1$@` and the text between backticks as they are.

`verify_macos_wording.py` reads the words of macOS from the resources of this Mac. It compares them with the names of the System
Settings panes and the Finder menu items in our text. The answer depends on the macOS version, so the gate does not run it. Run it
before you change one of those names.

## Add a string that people see

1. Add an entry to `Localization/Localizable.xcstrings`. Give the English text, a comment for the translator, and a translation
   in every language. `./script/merge_translations.py` takes a file with all three.
2. Run `./script/compile_localizations.py`. It makes the `LocalizationKey` case and a typed `LocalizedMessage` constructor. You
   write no Swift for this.
3. Use the text:
   - without values: `localizer.string(.groupCopyPath)`,
   - with values: `localizer.render(.menuOpenIn(name))`.

A text with more than one value numbers its placeholders: `%1$@ in %2$@`.

The output of `rh` and of the MCP server stays in English.

**A sentence of the doctor** is a catalog entry:

- `doctor.<check>.<state>` for what the doctor found,
- `doctor.fix.<what>` for what to do.

The doctor makes a row like this:
`DoctorCheck(.services, status: .warn, detail: .doctorServicesDiffer(a, b, c), fix: .doctorFixInstallServices)`. `rh`, the MCP
server and the setup window show the same message. `rh` and the MCP server show it in English.
