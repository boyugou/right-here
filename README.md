# Right Here

Send "here" (a folder, or whatever you selected in Finder) to your terminals,
editors and AI agents.

Right Here is a small action layer for macOS: a command-line tool (`rh`), a
plain-text config file, and Finder entry points (right-click menu, Quick
Actions, Services). People use the actions from Finder; AI agents use the same
actions from the command line.

- Copy a path in the form you need: absolute, `~`-relative, relative to the git
  root, shell-escaped, or an `@path` mention for an AI agent.
- Open the folder in a terminal or editor: Terminal, Ghostty, VS Code, and any
  app you add.
- Start an AI agent (Claude Code, Codex, and others) in that folder, in the
  terminal you choose.
- Create a new empty text or Markdown file.

## Use

```sh
rh init                      # create ~/.config/right-here/config.toml from what is installed
rh menu                      # preview the Finder menu
rh run agent.claude          # start Claude Code in the current folder, in your terminal
rh run copy-path.git-relative src/main.swift
rh doctor                    # check the setup
```

Right-click in Finder for the same actions (also available as Quick Actions, which cover iCloud Drive
and take keyboard shortcuts). `rh docs` prints the documentation, and everything has `--json` output
for scripts and AI agents.

AI agents can use it directly: `claude mcp add right-here -- rh mcp`, or install the Claude Code
plugin from this repository (`/plugin marketplace add boyugou/right-here`). The menu and the app are
available in thirty languages.

**Status:** early development, not released. Build and install from source with
[`docs/development/SETUP.md`](docs/development/SETUP.md). Design notes live in [`docs/`](docs/INDEX.md).

## Requirements

macOS 26 or later on Apple silicon.

## License

Apache-2.0. See [`LICENSE`](LICENSE).
