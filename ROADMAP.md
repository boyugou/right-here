# Roadmap

## Working

- Core: actions, planner, config, menu, catalogs, path styles, quoting (with real-shell tests).
- `rh`: run, actions, menu, agents, apps, config, init, install, uninstall, docs, doctor, finder, mcp, probe.
- Terminal adapters: Ghostty (1.3 and later for commands, new window or new tab), Terminal.app. Agent
  launchers: typed, terminal link, desktop app.
- `rh doctor --probe-launch`: a throwaway terminal session started through the Finder extension proves a
  typed command runs, in the right folder, in the login shell.
- The app (summary, details, a launch test button) with its icon, and the Finder extension; installer;
  `rh doctor`.
- Finder Services (Quick Actions) generated from the config; the doctor notices when they drift from it.
- A notarized, stapled DMG builds with `script/package_dmg.sh` (Apple accepted it; Gatekeeper accepts it).
- MCP server and the Claude Code plugin (setup, open-here and review-changes skills).
- Hardened through repeated independent reviews and a mutation check (`docs/decisions/0008-independent-review.md`):
  every finding is fixed with a test that fails on the old code, and `script/mutation_check.py` removes each
  protection in a throwaway clone and expects a test to fail.
- Thirty languages for the menu, the app, alerts and the permission-prompt text (machine-translated,
  awaiting native-speaker review).
- A strict, self-describing config: unique ids, no silent shadowing, `--strict`, replacements in
  diagnostics, a JSON Schema with required keys and patterns, a backup on `rh init --force`.

## Next

The items that need a person with a real Finder and terminals are listed with their steps in
[`docs/development/MANUAL_CHECKS.md`](docs/development/MANUAL_CHECKS.md).

- Confirm a real Finder click reaching `rh` (everything after it, typed launch included, is verified by
  `rh doctor --probe-launch`), and the first-ever Automation prompt on a clean system.
- Publish a release: tag, GitHub release with the notarized DMG and its checksum, then the Homebrew cask and
  formula (the release pipeline is verified; publishing needs the repository to be public).
- Built-in adapters for iTerm2, WezTerm, kitty, Alacritty, Warp, cmux, to be written and checked against the real
  terminals (not yet tested with these terminals); a config-defined launcher (`open_args`, `run_args`) exists
  for the meantime.
- Native-speaker review of the translations.
- The setup window's check rows: the titles are translated; the detail and fix lines come from the doctor and are
  English in every language. Translating them needs the doctor to return keys and arguments, not sentences.
- A menu-only App Store build (scope and risks in the design notes).

## Ideas, ranked

Researched against macOS 26 as of October 2026; each needs a short decision record before it is built.

1. **App Intents** (Shortcuts and Spotlight actions) that run `rh run <id>` with the folder as argv: a second entry
   point that does not depend on the Finder extension (Apple has not announced a Finder Sync deprecation, but
   developer forums report it failing to load on some macOS 26 machines).
2. **Recent and pinned folders**: `rh recents`, `rh pin`, a private state file, offered as intent entities.
3. **Agent prompt presets that carry the selection** (`[[preset]]` with `{files}` as `@` mentions), typed safely and
   prefilled, never auto-submitted by default.
4. **Project-local overrides** (`.right-here.toml` at the git root) behind an explicit trust step pinned to the file
   content, as direnv does. Reverses the rule that config is never read from the acted-on folder, so it needs its own
   record and mutation entries first.
5. A three-step **first-run setup** that waits for the Finder extension to turn green.
6. **Quick Actions as a primary path** in the setup window and doctor, with suggested keyboard shortcuts.
7. **Menu personalization** in the setup app, writing an include file so the hand-written config is never rewritten.
8. **Config sync**: a per-machine `config.local.toml` overlay and `rh config sync` copying through a folder the person
   chooses (iCloud Drive or any other); no symlink (the extension cannot read through one), no CloudKit.
9. Git-aware actions (agent in a new worktree), split-pane placement for Ghostty, an activity tab in the app.

## Open

- Whether Quick Actions appear on a folder background.
- The items, sidebar and toolbar menus on a real run.
- Which process macOS holds responsible when a Quick Action controls a terminal.
- Whether `rh`, started through the runner script, can look at items under Desktop, Documents and Downloads
  (privacy-protected folders). If it cannot, an action on such an item stops with an error that names the
  permission to grant instead of opening some other folder; only a real click shows which case this is.
