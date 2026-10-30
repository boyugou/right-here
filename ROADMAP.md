# Roadmap

## Working

**The product**

- **The Finder menu.** Open in a terminal or an editor, Open With, start an agent, agent presets, New File and Copy Path. The extension builds
  the menu from prebuilt templates and does no network or other slow work.
- **`rh`.** The commands: run, actions, menu, agents, apps, pin, unpin, pins, recents, worktree, config, setup, init, install, uninstall, docs,
  doctor, finder, mcp and probe.
- **`rh setup`.** One command does the whole first setup, and you can run it again at any time. Its report ends with what only you can do,
  also as `--json`. The first run of the setup window runs the same code.
- **The setup window.** Eight pages: Overview, Finder menu, Agents, Config, Checks, AI Assistants, Worktrees and Folders. You can change almost
  every setting there, and each change can be undone ([ADR 0026](docs/decisions/0026-one-config-two-editors.md)). Install or Repair says each
  step while it runs; a check that the window can fix has a button under it; the Agents page says which agents your login shell finds, and
  where; a change that renames or adds a Quick Action updates it at once.
- **One copy of the app.** An older copy, or a second copy of one version, says which copy to keep and sets nothing up, from the window or from
  `rh setup`. The doctor lists the installed copies when there is more than one.
- **Quick Actions**, made from the config. The doctor notices when they differ from it.
- **Shortcuts and Spotlight.** Four App Intents: Open in Terminal, Start AI Agent, Create New File and Copy Path. Each can take a
  pinned or recent folder picked from a list (a Saved Folder) instead of a folder given as a file.
- **AI assistants.** The MCP server (12 tools) and the Claude Code plugin with three skills. An assistant cannot change by itself which program
  a click starts: it proposes the change, and you apply it.
- **Agents in git worktrees**, pinned and recent folders, and agents that start without their permission prompts only when you turn that on.
- **Config sync** through iCloud Drive or any folder. A pull asks before it takes a program from the folder.
- **30 languages** for the menu, the window, the alerts and the permission texts. They follow the Mac's language, or the one chosen on the
  Overview (`general.language`). Machines made the translations, and they wait for review.

**Terminals**

- Tried on a real Mac: Ghostty (1.3 and later for commands; window and tab) and Terminal.
- Built in, not tried yet: iTerm2 (3.0 and later, with tabs and splits), WezTerm, kitty and Alacritty. `rh doctor --probe-launch` checks yours.
- Warp opens a window or tab in a folder through the `warp://` links its documentation gives (not tried yet); it cannot run a
  command. cmux is handed the folder. A config entry (`open_args`, `run_args`) can make any terminal start agents.

**Quality**

- Repeated independent reviews ([ADR 0008](docs/decisions/0008-independent-review.md)). Each finding is fixed with a test that fails on the
  old code.
- A mutation check: `script/mutation_check.py` removes each protection in a copy of the code and expects a test to fail.
- `rh doctor --probe-launch` starts a terminal through the Finder extension, to prove that a click reaches a login shell in the right folder.
- The setup guide for AI assistants (`rh docs agent-setup`) was tested with new agents in five setups
  ([`docs/development/SETUP_EVALUATION.md`](docs/development/SETUP_EVALUATION.md)).

**Distribution**

- A notarized DMG is attached to each release on GitHub (the latest is `v1.0.0`).
- A Homebrew cask is in `packaging/homebrew`. It needs a tap.

## Next

[`docs/development/MANUAL_CHECKS.md`](docs/development/MANUAL_CHECKS.md) lists the steps of the checks that need a real Finder and real
terminals.

- Try a click on items in Desktop, Documents and Downloads, and the first Automation prompt on a new Mac.
- Try iTerm2, WezTerm, kitty, Alacritty and Warp on a real Mac. Agents in Warp (only through a saved Tab Config) and in cmux (its
  socket takes outside programs only when the person allows it) wait for someone who uses them (ADR 0025).
- The cask in a tap, so that `brew install --cask right-here` works.
- Review of the translations by native speakers.
- A menu-only edition for the App Store (the design notes give its scope and risks).

## Ideas, ranked

Each idea needs a short decision record before it is built.

None at the moment. Project-local settings (a `.right-here.toml` at the git root, behind a step of trust) were considered and not built:
the menu could not show them, what is left is a terminal placement, and an agent in the folder could grant the trust itself
([ADR 0031](docs/decisions/0031-no-settings-from-the-folder-acted-on.md)).

## Open

- Whether Quick Actions show on the empty part of a Finder window.
- The menus of the toolbar and the sidebar on a real run.
- Which process macOS holds responsible when a Quick Action controls a terminal.
- Whether `rh`, started through the runner script, can look at items in Desktop, Documents and Downloads. If it cannot, the action stops with
  an error that names the permission. It never opens another folder instead. Only a real click shows which case it is.
