# Contributing

Right Here is licensed under Apache-2.0, and contributions are welcome. By taking part you agree to the
[Code of Conduct](CODE_OF_CONDUCT.md). Report a vulnerability privately as described in [`SECURITY.md`](SECURITY.md).
[`docs/INDEX.md`](docs/INDEX.md) lists the design notes and decision records. [`CLAUDE.md`](CLAUDE.md) holds
instructions for coding agents; everything a human needs is on this page.

## Setup

You need macOS 26 or later on Apple silicon, Xcode 26 or later and `xcodegen` (`brew install xcodegen`). Optional
but useful: `fish`, `dash` and `ksh` (the quoting tests round-trip through every shell found), and `uv` for the
Python scripts.

```sh
swift build                       # the libraries and rh
swift test                        # unit tests; none touches your home folder, Finder or an installed terminal
./script/verify_all.sh            # what CI runs, plus the app and extension build: tests, localization catalog,
                                  # config schema, embedded docs, the docs check (commands and links), public-safety check
./script/install_local.sh         # build the app and install it for yourself
./script/mutation_check.py        # after touching quoting, planning, MCP limits or the probe: do the tests still
                                  # notice when a protection is taken away? (slow: works on a throwaway clone of HEAD)
```

Run `./script/verify_all.sh` before opening a pull request. The project layout is in `CLAUDE.md` and
[`docs/DESIGN.md`](docs/DESIGN.md); [`docs/development/SETUP.md`](docs/development/SETUP.md) covers building and
installing in more detail.

## Tests

- A fix for a defect comes with a test that fails without the fix. Tests that guard against bad input generate it:
  the quoting tests round-trip every shell metacharacter with every joining mark through real shells.
- Nothing in the tests may open a window, send an Apple event or touch your real config. Use fake system facts, a
  fake process runner, a temporary folder, or `RH_HOME` and `RH_CONFIG_DIR`. Tests that run the real `rh` give it an
  empty home so your shell startup files do not run.
- To see an action without side effects, use `rh run <id> --dry-run`. To check the click chain on a real Mac, use
  `rh doctor --probe-launch` (a terminal window opens and closes).

## Style and rules

- Swift 6 with strict concurrency; no force unwraps outside tests; values crossing actors are `Sendable`. Comments
  explain a non-obvious reason (a platform quirk, a hidden constraint), not what the code does.
- **File names are data.** Never put one into a shell command or AppleScript source; pass it as an argument, or
  use `ShellQuoting`. Quoting works on Unicode scalars, not `Character`s (a quote followed by a combining mark is
  still a quote to a shell).
- **A terminal is only ever handed a folder.** Handing it a file runs it.
- The core (`Sources/RightHereCore`) is pure: planning is deterministic and unit-tested; side effects live in
  `Sources/RightHereKit`. The Finder extension stays thin and does no network or other I/O beyond a cached config read.
- **No code from GPL-licensed projects.** Read other projects' docs and issues for the problem; write the code
  yourself.
- Platform claims are checked on a real Mac and written down in `docs/DESIGN.md` as verified, sourced or open.
- Do not commit email addresses, machine-specific paths or keys (`script/verify_public_safety.sh` checks).
- Commit in small steps; every commit builds and passes the tests.
- `docs/TROUBLESHOOTING.md` and other embedded guides are compiled into the tool: after editing them run
  `script/compile_docs.py` (`verify_all.sh` checks).

## Adding a terminal

For a terminal that can be driven from its command line, no code is needed: define an `[[app]]` with
`role = "terminal"`, `open_args` and `run_args` in the config (see `rh docs config` and
[`docs/development/MANUAL_CHECKS.md`](docs/development/MANUAL_CHECKS.md)), and check it with `rh config validate`
and `rh run ... --dry-run`. For a built-in terminal, add one row to `KnownApps.terminals` in
`Sources/RightHereCore/Catalog/AppDescriptor.swift`: its `driver` says how it is started (`.openFolder` hands it the
folder, `.template(TerminalLaunch(open:run:))` starts it from an argument vector, as `[[app]]` does in the config) and
its `defaultRank` where it stands when the first installed terminal is picked (leave it out and it is never picked that
way). A terminal that needs code of its own, such as a scripting dictionary, also gets a `Driver` case and an adapter
beside `GhosttyAdapter` in `Sources/RightHereCore/Terminals/`, which `TerminalAdapters.adapter(for:)` maps the driver
to. The adapter must validate that the working directory is a folder, pass paths as arguments (never as script text),
and come with tests in `TerminalAdapterTests`. Say in the pull request which terminal version you checked it against.
An editor is one row in `KnownApps.editors` (a `defaultRank` makes it a candidate for the default editor).

## Adding an agent

Add an `AgentDescriptor` to `Sources/RightHereCore/Catalog/AgentDescriptor.swift` (id, display name, command,
variants, icon bundle identifier) and include it in `AgentDescriptor.all`. A person can also add any agent in their
config without code. Cover it in the planner tests.

## Adding or fixing a language

All thirty translations are machine-generated and marked `needs_review`; corrections from native speakers are
especially welcome. Open `Localization/Localizable.xcstrings` (and `Localization/InfoPlist.xcstrings` for the
permission prompt text), fix what reads badly (macOS's own wording for that language is the model), change
`"state"` to `"translated"` for each entry you checked, then run `./script/compile_localizations.py` and
`./script/verify_localizations.py`. `./script/preview_setup.sh out.png <language>` renders the setup window to an
image (add `--dark` for dark mode).

To add a language:

1. Add it to `Localization/languages.json`: its code, its English name, its script (ISO 15924) and `"rtl": true` if it is
   written right to left. That list is the only one; the scripts and the tests read it.
2. `./script/verify_localizations.py --missing <code>` lists every string the language lacks, in the three catalogs.
3. Write the translations as JSON, `{"key": {"translations": {"<code>": "text"}}}`, one file per catalog, and add them
   with `./script/merge_translations.py file.json` (add `--catalog InfoPlist.xcstrings` or `AppShortcuts.xcstrings`
   for the others). It checks each text (placeholders, the commands between backticks, the script of the language),
   puts the right-to-left mark where a right-to-left text needs one, marks the texts `needs_review` and writes nothing
   unless every text passes. Keep `%@` and `%1$@` and the text between backticks as they are.
4. `./script/compile_localizations.py`, then `./script/verify_localizations.py` must pass and `swift test` must stay green.
   Look at the setup window in the new language with `./script/preview_setup.sh out.png <code>`.

To add a user-visible string: add its entry to `Localization/Localizable.xcstrings` (English text, a comment for the
translator, a translation in every language; `./script/merge_translations.py` takes a file with the English text, the
comment and a `{language code: text}` dictionary, the same way as above), then run `./script/compile_localizations.py`.
That generates the `LocalizationKey` case and a typed `LocalizedMessage` constructor, so there is no Swift to write by
hand: use `localizer.string(.groupCopyPath)` for a text without values and `localizer.render(.menuOpenIn(name))` for one with
values. A text with several values numbers its placeholders (`%1$@ in %2$@`). The command line and MCP output stay
English.
