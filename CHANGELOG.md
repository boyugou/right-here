# Changelog

## Unreleased

- Finder extension: on macOS 26.5.1 it crashed each time Finder asked it to watch a folder, so the context menu showed none of its
  entries while every doctor check passed. It no longer overrides the directory-observing methods, which did nothing (ADR 0019).
  `rh doctor` now warns when the extension has crashed since it was installed, and names the newest crash report.
- The check for the `rh` link no longer tells a person to put `~/.local/bin` on their PATH when a new terminal already has it (issue 5: the setup window and
  a program an AI assistant starts have launchd's PATH, which says nothing about a terminal). It asks the login shell, reads the folder however it is spelled
  (trailing slash, `.` part, symbolic link), and says "did not say" instead of "not on PATH" when the shell gives no answer. The row for the Services
  workflows is called Quick Actions, as the rest of the window says, and the AI Assistants section shows `rh setup` as code, without its backticks.
- New: `rh setup` puts everything in place in one command and can be run again at any time: the config file, the runner script, the `rh` link, the
  Quick Actions and the Finder extension, then the checks, and it says what only you can do. `--terminal`, `--editor` and `--agents` say what you
  use instead of editing TOML (also on `rh init`), `--dry-run` shows the plan and `--json` is the report for an AI agent. A config that exists is
  never rewritten: the report lists the edit to make. `rh install` now repairs one named piece, the doctor's fixes say `rh setup`, and the setup
  window's first run offers what is installed and runs the same setup (ADR 0018).
- `rh docs agent-setup` is a procedure for an AI agent (ask the person first, look with a dry run, make the edits an existing config needs, run
  setup once, tell the person what only they can do, check, hand back), and the prompt the app copies and the plugin's setup skill follow it. It
  was tried with cold agents on three personas (`docs/development/SETUP_EVALUATION.md`); what they found is fixed: a trial lists the PATH line and the
  permission prompt, a dry run counts the Quick Actions of the config it would write, and the doctor warns about Claude Code's link handler only
  where something starts Claude Code through the link.
- The setup window is rebuilt: six sections (Overview, Finder menu, Checks, AI Assistants, Worktrees, Folders), every text in the
  thirty-language catalog, and a check that fails the gate when a view shows a literal. The preview script renders each section
  (`--tab`). The version comes from one place, `AppIdentity.version`, which `script/verify_version.py` checks against the project, the changelog and
  the Homebrew files.
- `rh run`: a plan's text is never cut and every value in it is a JSON-quoted string; a refusal names the file or folder at fault; options that
  would do nothing (`--bypass-permissions`, `--safe`, `--arg`, `--worktree`, `--branch` on an action that is not an agent) are errors and `-y` is
  gone; `--worktree --dry-run` plans without creating anything and a failed run leaves no worktree behind; `--language` lets Shortcuts name a new
  file in the person's language; a misspelt command gets a did-you-mean.
- Agents: starting with the agent's own permission prompts off is a launch option (`general.bypass_permissions`, `[agent.<id>]
  bypass_permissions`, `args`), off by default. A preset never gets it. The doctor, `rh agents`, `rh menu --explain` and the plan say when it
  is on, and the sync guard lists it (ADR 0016).
- Worktrees: only worktrees that Right Here made are removed, never forced, and a branch is deleted only when merged; branch names are validated;
  the repository's own hooks, `core.fsmonitor` program and filters do not run while a worktree is made; the MCP worktree tool is annotated as
  able to delete and its list is fenced.
- New: `rh doctor --report` (versions, the doctor's rows, counts of the config check; the home folder as `~`), `rh docs start` and `rh docs mcp`
  (built from the tools), `rh menu --explain`, `rh config show` (every file of the config) and `rh config path --all`.
- Terminals: WezTerm and kitty start through LaunchServices so that nothing waits for the window (not verified on a real machine);
  `terminal_placement = "split"` is gone (use `split-right`); `preset.<id>@default` is gone.
- Finder extension: it no longer keeps the Mac from sleeping, its menu cache lives 30 seconds, and its warm-up no longer races the main
  thread (ADR 0015).
- `state.toml` (pinned and recent folders) is readable only by you, and a pin is an absolute path.
- Packaging: the cask has the checksum of the v0.2.0 DMG; the App Store upload uses an API key and no password; the App Group is gone.

## 0.2.0 (2026-10-14)

- Finder menu: a prebuilt menu for single folders (the first right-click no longer waits for a build), the extension stays loaded, facts and
  directory lookups are cached.
- A built-in iTerm2 adapter (AppleScript, 3.0 and later), more editors detected (Trae, Positron, Fleet, RustRover, CLion, GoLand), a new app icon,
  a setup window with its action buttons pinned at the bottom.
- Copy Path: a single configured style gets a short title.

## 0.1.0 (2026-10-14)

First version, running on macOS 26 and later (Apple silicon).

- `rh`: run actions (copy a path in ten forms, open a folder in a terminal or editor, start an AI agent in a
  terminal, create a file, reveal), preview the Finder menu, list actions, apps and agents, validate the config,
  check the setup (`rh doctor`, with probes that prove the Finder click chain and a typed terminal launch),
  install and uninstall, serve an MCP server.
- Finder: a sandboxed Finder Sync extension (right-click menu and toolbar item) and Quick Actions, both generated
  from one config; Ghostty and Terminal.app adapters (new window, or a new Ghostty tab); agents typed into your
  own login shell, with Claude Code, Codex, Gemini CLI, opencode, aider and Amp built in and any command addable.
- A plain-text TOML config with a schema, unknown-key suggestions, `--strict` validation and a JSON Schema.
- The setup window previews the Finder menu as the extension builds it from your config (the same code, the same
  icons, submenus that open in place), so you see what you get before the extension is switched on.
- A setup app, thirty languages for the menu, the app (its list of checks: `rh doctor --json` gives each
  detail and fix as a code, its values and the English text), alerts and the permission prompt (machine-translated,
  awaiting native-speaker review), a Claude Code plugin and `rh docs` for agents.
- Hardened through repeated independent reviews and a mutation check (`docs/decisions/0008-independent-review.md`)
  that removes each protection and expects a test to fail: shell quoting that holds against combining
  marks, one place that refuses any path that does not exist, bounded and budgeted MCP calls, a process runner
  that stops a login shell for good, an atomic claim for the probe request, parsers that refuse nesting deep
  enough to overflow the stack, and installs that keep the old Services and link when they fail halfway.
- Config sync: an optional per-machine overlay `config.local.toml` (merged by id, with `disabled`), and
  `rh config sync` (enable, status, pull, push, disable) that copies the config through a plain folder such as iCloud
  Drive, with refusals for local or remote changes, secrets and invalid files, atomic writes and doctor checks. The
  folder is not trusted with programs: a pull that would add or change a terminal template or an agent command is
  refused, with the list, unless `--allow-commands`.
- Config problems name the file and the line they are on, in the order of the file, and say what is wrong: a syntax
  error says what it is (an array that is not closed is reported at the line where it opened), a value of the wrong kind
  says what it is (`expected a string, found an integer`), a choice lists the valid values, a key in the wrong table says
  where it belongs, and a display name that is typed for an id (`Visual Studio Code`) finds it. With a `config.local.toml`,
  `rh config validate` also reads `config.toml` on its own, because other Macs do: an error the overlay hides on this Mac
  is still reported (and refused by `push`), and so is a key named like a credential, which `push` refuses. `rh config show` prints each file that makes up the config under a header
  naming it, and `rh config path --all` lists them. A config that cannot be read is an error naming the reason, names and
  titles with control characters are refused, and a launcher an agent cannot use is a warning.
- The sync folder is not trusted with time or memory either: a file in it (or this Mac's config) past 1 MiB is never read,
  and `status` says so; an unreadable local config is no longer taken for a missing one that a plain `pull` replaces; an
  empty `--folder` is refused; `push` says it creates only the last folder and how to make the parent; `status` advises
  nothing that `push` or `pull` would refuse; a shared preset left out because its agent is disabled on this Mac is a note.
- Terminals without a built-in adapter can be defined in the config (`open_args`, `run_args`); copied paths use
  the spelling the file system stores.
- The menu says what it leaves out: `rh menu --explain` lists, with the reason, the entries the config asks for that are
  not there (an app that is not installed, no file selected for the presets, an agent the overlay disabled) and the
  defaults another app replaced; `rh doctor` and `rh config validate` say when a config leaves the menu empty for a
  folder. A default terminal or editor that is not installed (a config shared between Macs) gives way to the first
  installed one, and the doctor names both; an agent that is set to start in its desktop app or by its link keeps a
  typed launch in the default terminal under More Agent Options; Agent Presets are not offered for a selection of only
  folders; a new file is never handed to the system's default app when no editor is installed; each element of a
  variant's `arguments` is typed as one quoted argument.
- Verified: the whole chain after a menu click on a real Mac; real-shell round trips of quoting; a notarized,
  stapled DMG. Not yet verified: a real Finder click (see `docs/DESIGN.md`, section 5, Open).
