# Changelog

## 0.1.0 (not released yet)

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
- Verified: the whole chain after a menu click on a real Mac; real-shell round trips of quoting; a notarized,
  stapled DMG. Not yet verified: a real Finder click (see `docs/DESIGN.md`, section 5, Open).
