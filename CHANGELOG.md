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
- A setup app, thirty languages for the menu, the app, alerts and the permission prompt (machine-translated,
  awaiting native review), a Claude Code plugin and `rh docs` for agents.
- Hardened through three independent review rounds (`docs/decisions/0008-independent-review.md`): shell quoting
  that holds against combining marks, one place that refuses any path that does not exist, bounded and budgeted
  MCP calls, a process runner that stops a login shell for good, an atomic claim for the probe request.
- Verified: the whole chain after a menu click on a real Mac; real-shell round trips of quoting; a notarized,
  stapled DMG. Not yet verified: a real Finder click (see `docs/DESIGN.md`, section 5, Open).
