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

**Status:** early development, not released. Design notes live in
[`docs/`](docs/INDEX.md).

## Requirements

macOS 26 or later on Apple silicon.

## License

Apache-2.0. See [`LICENSE`](LICENSE).
