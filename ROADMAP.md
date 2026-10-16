# Roadmap

## Working

- Core: actions, planner, config, menu, catalogs, path styles, quoting (with real-shell tests).
- `rh`: run, actions, menu, agents, apps, pin, unpin, pins, recents, worktree, config, setup, init, install, uninstall, docs, doctor, finder, mcp, probe.
- `rh setup`: the whole first-time job in one idempotent command (the config from what is installed or from `--terminal`, `--editor` and `--agents`, the runner
  script, the command link, the Quick Actions, the Finder extension, then the checks), with a plain and a `--json` report that ends in what only the person can do. The
  setup window's first run runs the same code. The playbook an AI agent follows (`rh docs agent-setup`) was tried with cold agents on three personas
  ([`docs/development/SETUP_EVALUATION.md`](docs/development/SETUP_EVALUATION.md)).
- Terminal adapters: Ghostty (1.3 and later for commands; window and tab) and Terminal.app are tried on a real Mac. The Ghostty and iTerm2 splits, iTerm2 (3.0 and later),
  WezTerm and kitty are built in and not yet tried on a real Mac (`rh doctor --probe-launch` checks yours). Agent launchers: typed, terminal link, desktop app.
- Agents in isolated git worktrees (`rh worktree`, `rh run --worktree`, the MCP tool), pinned and recent folders, and an agent's permission prompts skipped only when
  you ask for it per agent (`bypass_permissions`, off by default, never for a preset).
- `rh doctor --probe-launch`: a throwaway terminal session started through the Finder extension proves a
  typed command runs, in the right folder, in the login shell.
- The app (summary, details, a launch test button) with its icon, and the Finder extension; installer;
  `rh doctor`.
- Finder Services (Quick Actions) generated from the config; the doctor notices when they drift from it.
- A notarized, stapled DMG builds with `script/package_dmg.sh` and is published to GitHub Releases (`v0.2.0`) with checksum verification (Apple accepted; Gatekeeper accepts).
- Premium macOS app icon (dark frosted obsidian folder + illuminated cyan-violet targeting reticle with `>_` terminal prompt).
- Zero-latency Finder extension: prebuilt in-memory `NSMenu` templates, automatic termination prevention, and fact caching.
- MCP server and the Claude Code plugin (setup, open-here and review-changes skills).
- Hardened through repeated independent reviews and a mutation check (`docs/decisions/0008-independent-review.md`):
  every finding is fixed with a test that fails on the old code, and `script/mutation_check.py` removes each
  protection in a throwaway clone and expects a test to fail.
- Thirty languages for the menu, the app (the setup window's check rows included: the doctor returns a code and
  values for each sentence, and the window writes them in the system language), alerts and the permission-prompt
  text (machine-translated, awaiting native-speaker review). Only the two probes, the parser's and the planner's own
  sentences (the first error of a config, why an agent cannot start) and text quoted from the config stay English.
- A strict, self-describing config: unique ids, no silent shadowing, `--strict`, replacements in
  diagnostics, a JSON Schema with required keys and patterns, a backup on `rh init --force`.
- App Intents: native Shortcuts and Spotlight actions (`OpenInTerminalIntent`, `StartAgentIntent`, `NewFileIntent`, `CopyPathIntent`) that execute safely without requiring the Finder extension.
- Config sync: `rh config sync` (push, pull, status) syncing across Macs through iCloud Drive or any local folder, with `--allow-commands` safety protection for executable templates.
- Setup window: six sections (Overview, Finder menu preview, Checks, AI Assistants, Worktrees, Folders) with live status; its first run offers what is installed
  and sets it up. `rh doctor` also notices a Finder extension that crashed since it was installed.
- Official Claude Code plugin with dedicated skills (`setup`, `open-here`, `review-changes`).

## Next

The items that need a person with a real Finder and terminals are listed with their steps in
[`docs/development/MANUAL_CHECKS.md`](docs/development/MANUAL_CHECKS.md).

- Confirm a real Finder click reaching `rh` (everything after it, typed launch included, is verified by
  `rh doctor --probe-launch`), and the first-ever Automation prompt on a clean system.
- Homebrew cask and formula for distribution.
- Trying iTerm2, WezTerm and kitty on a real Mac, and built-in adapters for Alacritty, Warp and cmux, to be written and checked against the real terminals; a
  config-defined launcher (`open_args`, `run_args`) exists for the meantime.
- Native-speaker review of the translations.
- A menu-only App Store build (scope and risks in the design notes).

## Ideas, ranked

Researched against macOS 26 as of October 2026; each needs a short decision record before it is built.

1. **Project-local overrides** (`.right-here.toml` at the git root) behind an explicit trust step pinned to the file
   content, as direnv does. Reverses the rule that config is never read from the acted-on folder, so it needs its own
   record and mutation entries first.
2. **Recent folders and pins as App Intent entities**, so Shortcuts and Spotlight can choose one.

## Open

- Whether Quick Actions appear on a folder background.
- The items, sidebar and toolbar menus on a real run.
- Which process macOS holds responsible when a Quick Action controls a terminal.
- Whether `rh`, started through the runner script, can look at items under Desktop, Documents and Downloads
  (privacy-protected folders). If it cannot, an action on such an item stops with an error that names the
  permission to grant instead of opening some other folder; only a real click shows which case this is.
