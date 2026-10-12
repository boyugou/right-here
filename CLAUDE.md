# CLAUDE.md — Right Here

Operating manual for agents working in this repository. Start with
`docs/INDEX.md`; the design and the reasoning behind it are in `docs/DESIGN.md`
and `docs/decisions/`.

Right Here is a macOS action layer: the `rh` command-line tool, a plain-text
config, and Finder entry points (FinderSync menu, Quick Actions, Services) that
send a folder or selection to terminals, editors and AI agents.

## Layout

```
Sources/RightHereCore/   pure logic (context, paths, quoting, plan, planner, adapters, config, menu)
Sources/RightHereKit/    macOS runtime (facts, process runner, executor, installer, doctor)
Sources/RightHereMCP/    the MCP server
Sources/rh/              the command-line tool
Localization/            Localizable.xcstrings, the source of every user-visible string
plugins/right-here/      the Claude Code plugin (MCP launcher and skills)
Apps/RightHere/          the app (setup window)
Apps/FinderExtension/    the Finder Sync extension
project.yml              XcodeGen project; the .xcodeproj is generated, not committed
script/                  build_app.sh, install_local.sh
docs/                    DESIGN.md, decisions/, development/
```

## Hard rules

1. **No GPL code.** The project is Apache-2.0. Never copy or paraphrase code
   from GPL projects (RClick, cmux and others). Read their docs and issues for
   the problem domain only; write the implementation from scratch.
2. **Never interpolate user-derived text into a shell command or an AppleScript
   source.** Paths and file names are data. Pass them as argv entries, as
   AppleScript `on run argv` arguments, or through the single vetted quoting
   module (`ShellQuoting`) with tests. Text typed into a terminal rejects
   newline and carriage return in any user-derived part.
3. **A terminal app must only ever be handed a folder.** Handing it a file runs it. The working
   directory is validated in `HereContext.workingDirectory` and again in every adapter.
4. **The core is pure.** Planning (action + context + config + system facts to a
   `LaunchPlan`) is deterministic and unit-tested. Side effects live only in the
   runtime layer. Tests never touch the real home directory, the real Finder or
   installed apps; they use temporary directories and fake system facts.
5. **The Finder extension stays thin and fast.** Building a menu does no network
   and no I/O beyond a cached read of the config. Anything that needs more runs
   in `rh`.
6. **Repository hygiene.** Tracked files contain no email addresses, no
   developer-machine paths, no keys or credentials, and no personal name inside a
   signing identity. Commit with the GitHub noreply address already configured in
   this clone.
7. **Platform.** macOS 26 or later, Apple silicon, Swift 6 with strict
   concurrency. No older-OS fallbacks.

## Working agreements

- Decisions that shape the product or architecture get a short record in
  `docs/decisions/` stating the choice, the alternatives and the evidence. Claims
  about macOS behavior are verified on the real machine and the result is
  written down; do not rely on memory of older macOS versions.
- Swift style: no force unwraps outside tests, `Sendable` across actors, comments
  only for a non-obvious reason (a hidden constraint, a platform quirk).
- User-visible strings (menu titles, app and alert text) go through `Localization/Localizable.xcstrings`:
  add a `LocalizationKey`, an English entry and all thirty translations, run
  `script/compile_localizations.py`, and `script/verify_localizations.py` must pass. CLI and MCP output
  stays English.
- Check desktop behavior through the product's own chain, never by driving the person's apps from your own
  shell. `rh doctor --probe-launch` runs extension, runner script, `rh` and the terminal (a window opens and
  closes). An Apple event or UI-scripting call from your shell would make macOS grant your host app standing
  control of their terminals. Tests never open windows: CLI tests use a terminal that cannot run commands, and
  everything else uses fake runners.
- A claim about what the file system or the OS guarantees is measured before anything is built on it: eight
  concurrent `unlink`s of one path mostly all succeeded on APFS, so "whoever unlinks wins" was wrong, while
  `rename` and `O_EXCL` held in thousands of rounds (`ProbeMarker`).
- Tests that run the real `rh` give it an empty home for the login shell (the person's startup files must not
  run) and a config that does not open or reveal anything; every fix gets a test that fails against the old code.
- To look at the setup window without a screen, render the SwiftUI view to a PNG with `ImageRenderer` from a
  scratch package that links the app's view files; `-AppleLanguages "(de)"` switches the language.
- Before pushing run `./script/verify_all.sh` (build, tests, catalog, config schema, embedded docs, the `rh` commands
  the docs show, public-safety check).
- Python tooling uses `uv`.
- Commit in small steps; every commit builds and its tests pass.

## Build and test

```sh
swift build
swift test
```
