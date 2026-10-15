# Right Here for Claude Code

This plugin connects Claude Code directly to [Right Here](https://github.com/boyugou/right-here), the open-source macOS action layer, exposing Finder integration, terminal & editor launchers, and AI automation tools.

## Requirements

- A Mac running macOS 26 or later on Apple silicon with Right Here installed.
- Claude Code.

## Install

```sh
/plugin marketplace add boyugou/right-here
/plugin install right-here@right-here
```

Then start a new Claude Code session.

## What it adds

| Component | What it does |
|-----------|--------------|
| MCP server `right-here` | Exposes 10 typed tools (`right_here_run`, `right_here_actions`, `right_here_menu`, `right_here_finder_selection`, `right_here_doctor`, `right_here_config_validate`, `right_here_catalog`, `right_here_docs`, `right_here_bookmarks`, `right_here_worktree`). `rh docs mcp` describes them. |
| `/right-here:setup` | Asks which terminal, editor and AI agents you use, runs `rh setup` once with your answers, tells you what only you can do, and checks the result. |
| `/right-here:open-here` | Resolves the user's active Finder selection or a directory path, and opens it in their configured terminal, IDE, or AI agent. |
| `/right-here:review-changes` | Reveals modified workspace files in native Finder windows for interactive visual review. |

## How it works

The plugin launches `rh mcp` via the bundled launcher script (`scripts/right-here-mcp`). It communicates over standard input and output with zero network telemetry. All actions are budgeted and rate-limited for security and safety.
