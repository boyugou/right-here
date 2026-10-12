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
- Independent reviews in eight rounds (see `docs/decisions/0008-independent-review.md`), every finding fixed
  with a test that fails on the old code, and a mutation check (`script/mutation_check.py`) that removes each
  protection in a throwaway clone and expects a test to fail.
- Thirty languages for the menu, the app, alerts and the permission-prompt text (machine-translated,
  awaiting review).
- A strict, self-describing config: unique ids, no silent shadowing, `--strict`, replacements in
  diagnostics, a JSON Schema with required keys and patterns, a backup on `rh init --force`.

## Next

The items that need a person at the machine are listed with their steps in
[`docs/development/MANUAL_CHECKS.md`](docs/development/MANUAL_CHECKS.md).

- Confirm a real Finder click reaching `rh` (everything after it, typed launch included, is verified by
  `rh doctor --probe-launch`), and the first-ever Automation prompt on a clean machine.
- Publish a release: tag, GitHub release with the notarized DMG and its checksum, then the Homebrew cask and
  formula (the pipeline is verified; publishing needs the repository to be public, the owner's call).
- Built-in adapters for iTerm2, WezTerm, kitty, Alacritty, Warp, cmux, to be written and checked on a machine that
  has them (none is installed on the development machine); a config-defined launcher (`open_args`, `run_args`)
  exists for the meantime.
- Native-speaker review of the translations.
- A menu-only App Store build (scope and risks in the design notes).

## Open

- Whether Quick Actions appear on a folder background.
- The items, sidebar and toolbar menus on a real run.
- Which process macOS holds responsible when a Quick Action controls a terminal.
- Whether `rh`, started through the runner script, can look at items under Desktop, Documents and Downloads
  (privacy-protected folders). If it cannot, an action on such an item stops with an error that names the
  permission to grant instead of opening some other folder; only a real click shows which case this is.
