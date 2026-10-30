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
Localization/            Localizable.xcstrings (every user-visible string), languages.json (the shipped languages)
plugins/right-here/      the Claude Code plugin (MCP launcher and skills)
Apps/RightHere/          the app (setup window)
Apps/FinderExtension/    the Finder Sync extension
project.yml              XcodeGen project; the .xcodeproj is generated, not committed
script/                  build_app.sh, install_local.sh
docs/                    DESIGN.md, decisions/, development/
```

## Hard rules

1. **No code from GPL-licensed projects.** The project is Apache-2.0. Never copy or
   paraphrase it. Read other projects' docs and issues for the problem domain
   only; write the implementation from scratch.
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
   signing identity. Commit with your GitHub noreply address.
7. **Platform.** macOS 26 or later, Apple silicon, Swift 6 with strict
   concurrency. No older-OS fallbacks.
8. **No backward compatibility.** The project has no existing users. Change or delete on-disk formats, JSON
   output, config keys, action ids and command-line output when a cleaner design calls for it; do not add
   deprecated aliases, migration code or tests that keep an old shape working. The safety rules and the tests that
   pin real behaviour stay.

## Working agreements

- Decisions that shape the product or architecture get a short record in
  `docs/decisions/` stating the choice, the alternatives and the evidence. Claims
  about macOS behavior are verified on the real machine and the result is
  written down; do not rely on memory of older macOS versions.
- Swift style: no force unwraps outside tests, `Sendable` across actors, comments
  only for a non-obvious reason (a hidden constraint, a platform quirk).
- A setting is not finished until `ConfigTrust` decides whether an assistant may change it by itself and `ConfigParity` says how a person changes it in the window (a control, or text on the Config
  page for now); tests fail for a setting of the schema that is in neither.
- User-visible strings (menu titles, app and alert text, the doctor's sentences) go through
  `Localization/Localizable.xcstrings`: add the entry with its English text and a translation in every language of
  `Localization/languages.json` (the one list of languages; `script/merge_translations.py` adds translations after
  checking them), then run `script/compile_localizations.py`, which generates `LocalizationKey` and a typed
  `LocalizedMessage` constructor for each key (there is no Swift to write by hand), and `script/verify_localizations.py`
  must pass. A text with values numbers its placeholders (`%1$@`) and is written with
  `localizer.render(.menuOpenIn(name))`. CLI and MCP output stays English.
- Check desktop behavior through the product's own chain, never by driving the person's apps from your own
  shell. `rh doctor --probe-launch` runs extension, runner script, `rh` and the terminal (a window opens and
  closes). An Apple event or UI-scripting call from your shell would make macOS grant your host app standing
  control of their terminals. Tests never open windows: CLI tests use a terminal that cannot run commands, and
  everything else uses fake runners. The CLI harness also sets `RH_NO_UI=1`, under which `rh` shows no alert and never starts `open` or
  `osascript`, so no test can put a dialog or window on screen, and puts a watchdog on every `rh` it starts.
- A test that runs the real `rh` and means to write anything under the home gives it `RH_HOME`; `rh` started with `RH_NO_UI` (the harness) and no `RH_HOME` refuses to change the real home
  or the extension's registration (`RealHomeGuard`, ADR 0022), and `script/mutation_check.py` stops at the first mutant that changes them. A test of that guard is a unit test with a home it
  names, never a run of the real `rh` that would do the damage if the guard were gone.
- A claim about what the file system or the OS guarantees is measured before anything is built on it. Never use
  `unlink` as an exclusive claim (concurrent unlinks of one path can all succeed on APFS); claim with `rename` or
  `O_EXCL` (`ProbeMarker`).
- Tests that run the real `rh` give it an empty home for the login shell (the person's startup files must not
  run) and a config that does not open or reveal anything; every fix gets a test that fails against the old code.
- To look at the setup window without a screen, render the SwiftUI view to a PNG with `ImageRenderer` from a
  scratch package that links the app's view files: `./script/preview_setup.sh out.png de` (the language is its second
  argument). `--gallery` renders every sentence the doctor can say, to look for text that does not fit; `--demo` renders
  canned checks and a canned Finder menu (`--submenus` opens its submenus) that show nothing of this Mac, which is what
  a screenshot for the website must use. Those pictures show a stand-in for each control that AppKit draws (a switch, a text
  field, the segmented control, the config's text); `--real-controls` draws the real ones in a window that is never put on screen, so look at it
  after changing how a control is made (ADR 0029, 10 and 11: two such controls drew differently from their stand-ins).
- Before pushing run `./script/verify_all.sh` (build, tests, the app and extension build, the same with Xcode 26 when it is installed
  beside a newer one (CI builds with it, and its Swift crashed on code that a newer Swift compiled), catalog, the window's control styles, config schema,
  embedded docs, the docs check (commands and links), public-safety check).
- After changing a protection that `docs/DESIGN.md` section 9 relies on, run `./script/mutation_check.py`: it removes
  each protection in a throwaway clone and expects a test to fail. Add an entry when you add a protection.
- Python tooling uses `uv`.
- Commit in small steps; every commit builds and its tests pass.

## Build and test

```sh
swift build
swift test
```
