# Contributing

Right Here is Apache-2.0. Start with [`CLAUDE.md`](CLAUDE.md) (it is written for agents but is the shortest
statement of the rules) and [`docs/INDEX.md`](docs/INDEX.md).

## Build and test

```sh
swift build && swift test         # unit tests; none touches your home folder, Finder or an installed terminal
./script/verify_all.sh            # what CI runs: build, tests, localization catalog, config schema, embedded docs, the docs check (commands and links), public-safety check
./script/install_local.sh         # build the app and install it for yourself
```

macOS 26 or later on Apple silicon, Xcode 26 or later, `xcodegen` (`brew install xcodegen`).

## Rules that matter

- **No GPL code.** Read other projects' docs and issues for the problem; write the code yourself.
- **File names are data.** Never put one into a shell command or AppleScript source; pass it as an argument. Text
  made safe for a shell works on Unicode scalars, not `Character`s (a quote followed by a combining mark is still a
  quote to a shell).
- **A terminal is only ever handed a folder.**
- **Tests that can fail.** A fix for a defect comes with a test that fails without it; tests that guard against bad
  input generate it (the quoting tests round-trip every metacharacter with every joining mark through real shells).
  Nothing in the tests may open a window, send an Apple event or touch your real config: use fake system facts, a
  fake process runner, a temporary folder, or `RH_HOME` and `RH_CONFIG_DIR`.
- **Strings people see** go through `Localization/Localizable.xcstrings` in all thirty languages; run
  `script/compile_localizations.py` and `script/verify_localizations.py`.
- **Platform claims are checked on a real machine** and written down in `docs/DESIGN.md` as verified, sourced or open.
- `docs/TROUBLESHOOTING.md` is embedded for `rh docs troubleshooting` and the MCP server: after editing it run
  `script/compile_docs.py` (`verify_all.sh` checks).
- Commit in small steps; every commit builds and passes the tests. Do not commit emails, machine paths or keys
  (`script/verify_public_safety.sh` checks).

## Reviewing a translation

All thirty translations were written with AI help and are marked `needs_review`. If you read one of the languages:
open `Localization/Localizable.xcstrings` (and `InfoPlist.xcstrings` for the permission prompt text), fix what reads
badly (macOS's own wording for that language is the model), change `"state"` to `"translated"` for each entry you
checked, then run `./script/compile_localizations.py` and `./script/verify_localizations.py`.
`./script/preview_setup.sh out.png <language>` shows how the setup window reads.

## Looking at the setup window

`./script/preview_setup.sh out.png [language] [--dark]` renders it to an image without a screen.
