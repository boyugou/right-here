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
Sources/rh/              the command-line tool
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
3. **The core is pure.** Planning (action + context + config + system facts to a
   `LaunchPlan`) is deterministic and unit-tested. Side effects live only in the
   runtime layer. Tests never touch the real home directory, the real Finder or
   installed apps; they use temporary directories and fake system facts.
4. **The Finder extension stays thin and fast.** Building a menu does no network
   and no I/O beyond a cached read of the config. Anything that needs more runs
   in `rh`.
5. **Repository hygiene.** Tracked files contain no email addresses, no
   developer-machine paths, no keys or credentials, and no personal name inside a
   signing identity. Commit with the GitHub noreply address already configured in
   this clone.
6. **Platform.** macOS 26 or later, Apple silicon, Swift 6 with strict
   concurrency. No older-OS fallbacks.

## Working agreements

- Decisions that shape the product or architecture get a short record in
  `docs/decisions/` stating the choice, the alternatives and the evidence. Claims
  about macOS behavior are verified on the real machine and the result is
  written down; do not rely on memory of older macOS versions.
- Swift style: no force unwraps outside tests, `Sendable` across actors, comments
  only for a non-obvious reason (a hidden constraint, a platform quirk).
- User-visible strings go through String Catalogs; never hard-code a menu title.
- Python tooling uses `uv`.
- Commit in small steps; every commit builds and its tests pass.

## Build and test

```sh
swift build
swift test
```
