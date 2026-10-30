# Right Here for Claude Code

This plugin connects Claude Code to [Right Here](https://github.com/boyugou/right-here). With it, Claude Code can:

- set Right Here up,
- open a folder in your terminal, your editor or an agent,
- show you in Finder the files that it changed.

## What you need

- A Mac with Apple silicon and macOS 26 or later.
- Right Here, installed.
- Claude Code.

## Install

```sh
/plugin marketplace add boyugou/right-here
/plugin install right-here@right-here
```

Then start a new Claude Code session.

## What it adds

| Part | What it does |
| --- | --- |
| `/right-here:setup` | Asks which terminal, editor and agents you use. Runs `rh setup` once with your answers. Tells you what only you can do, and checks the result. |
| `/right-here:open-here` | Finds the folder that you mean: your Finder selection, a path, or the current project. Opens it in your terminal, your editor or an agent. |
| `/right-here:review-changes` | Shows the files that Claude Code changed in Finder, so that you can look at them. |
| The MCP server `right-here` | Gives Claude Code the 12 tools of `rh mcp`. `rh docs mcp` describes them. |

The MCP tools:

| Tool | What it does |
| --- | --- |
| `right_here_actions`, `right_here_menu`, `right_here_catalog` | List the actions, the Finder menu, and the terminals, editors and agents. |
| `right_here_run` | Runs an action. Use `dry_run` first. |
| `right_here_finder_selection` | Reads what is selected in Finder. |
| `right_here_config_get`, `right_here_config_edit`, `right_here_config_validate` | Read, change and check the config file. |
| `right_here_doctor`, `right_here_docs` | Check the setup, and read the guides. |
| `right_here_bookmarks`, `right_here_worktree` | List pinned and recent folders. Manage the git worktrees that Right Here made. |

## How it works

1. Claude Code starts `scripts/right-here-mcp`.
2. The script finds `rh`: on your `PATH`, in `~/.local/bin`, in Homebrew, or inside Right Here.app.
3. The script starts `rh mcp`. Claude Code and `rh` talk through standard input and output.

`scripts/right-here-mcp --print-path` prints which `rh` it uses.

- **No network.** The plugin and `rh` make no network connections of their own.
- **A limit on what opens.** The tools open or create about 24 documents, or 8 started commands, in a minute.
- **Your approval for what starts.** An AI assistant cannot change by itself which program a click starts, or turn off an agent's
  permission prompts. It proposes the change. You apply it on the **Config** page of the app, or with `rh config pending`.
