<div align="center">

<img src="Apps/RightHere/icon-1024.png" alt="Right Here Icon" width="128" height="128">

# Right Here

**Act on the folder you are looking at. Right here.**<br>
The open-source action layer for macOS: send folders and selections to terminals, editors, and AI agents.

[![License](https://img.shields.io/badge/license-Apache--2.0-blue?style=flat-square)](LICENSE)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](.)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black?style=flat-square&logo=apple&logoColor=white)](.)
[![Notarized DMG](https://img.shields.io/badge/Download-Notarized%20DMG-brightgreen?style=flat-square&logo=apple)](https://github.com/boyugou/right-here/releases/latest)
[![MCP Server](https://img.shields.io/badge/MCP-Server%20(stdio)-6B57D2?style=flat-square)](.)
[![Languages](https://img.shields.io/badge/languages-30%20locales-orange?style=flat-square)](.)

[Website](https://boyugou.github.io/right-here/) · [Download for Mac](https://github.com/boyugou/right-here/releases/latest) · [Install Guide](#install) · [CLI Usage](#use) · [Connect AI Assistant](#connect-an-ai-assistant) · [Architecture](#how-it-works) · [Documentation](docs/INDEX.md)

<br>

<table>
  <tr>
    <td align="center" width="33%"><b>Finder Menu & Workspace App</b></td>
    <td align="center" width="33%"><b>AI Agents & Isolated Worktrees</b></td>
    <td align="center" width="33%"><b>Unified CLI & Automation</b></td>
  </tr>
  <tr>
    <td align="left"><sub>Open any folder or selection in Ghostty, Terminal, iTerm2, WezTerm, kitty, VS Code, Cursor, Zed, or Antigravity. Rich SwiftUI Master-Detail workspace app with live menu preview, diagnostics, and bookmark manager.</sub></td>
    <td align="left"><sub>Launch Google Antigravity (<code>agy</code>), Claude Code, or Codex in your authentic login shell. Run agents inside isolated git worktrees (<code>--worktree</code>) to protect your working branch from uncommitted edits.</sub></td>
    <td align="left"><sub>Zero resident daemons. The sandboxed FinderSync extension responds in ~0.15ms. Every GUI action maps 1:1 to an audited <code>rh run</code> command with dry-run verification, JSON output, and stdio MCP server.</sub></td>
  </tr>
</table>

</div>

---

Right Here is a lightweight, ultra-fast macOS action layer composed of a sandboxed FinderSync extension, an audited command-line tool (`rh`), a plain-text configuration file (`~/.config/right-here/config.toml`), and a Model Context Protocol (MCP) server.

Developers use contextual right-clicks in Finder or the native macOS workspace app; AI assistants use the exact same actions from the terminal or over MCP.

- **Zero resident daemons.** No background memory footprint or battery drain. The FinderSync extension activates on demand in ~0.15ms, and `rh` runs only when invoked.
- **Isolated git worktrees.** AI coding agents can execute inside dedicated, temporary git worktrees (`--worktree`), ensuring your active git branch and uncommitted modifications remain untouched.
- **Robust safety & sandboxing.** File paths travel strictly as raw argv arguments and AppleScript descriptors, never concatenated into shell strings. The sandboxed extension has zero network entitlements.
- **Deterministic 1:1 parity.** Anything clickable in Finder can be simulated, tested, and executed via `rh run <action>` and the stdio MCP server.
- **Local-first configuration.** Configured via standard TOML with JSON Schema validation (`rh config schema`) and optional multi-device sync without third-party servers.
- **Native everywhere.** Supports Apple silicon, macOS 26+, native Dark Mode, and 30 languages with bidirectional right-to-left script support (Arabic, Hebrew, Persian, Urdu).

## How it works

```
┌──────────────┐   MCP (stdio)   ┌───────────────┐        ┌──────────────────┐
│ AI assistant │ ◄─────────────► │    rh mcp     │ ◄────► │  RightHereCore   │
│(Claude, agy) │    typed tools  │ (MCP server)  │        │  Config & Models │
└──────────────┘                 └───────────────┘        └────────┬─────────┘
                                                                   │
┌──────────────┐   right-click   ┌───────────────┐                 │
│ Finder / You │ ◄─────────────► │ FinderSync    │ ◄───────────────┤
└──────────────┘                 │ (Extension)   │                 │
                                 └───────┬───────┘                 │
                                         │ posix_spawn             ▼
                                         ▼                ┌──────────────────┐
                                 ┌───────────────┐        │  macOS Apps      │
                                 │ rh runner     │ ◄────► │  Terminals & IDEs│
                                 │ (~/.local/bin)│        └────────┬─────────┘
                                 └───────┬───────┘                 │
                                         │ --worktree              │
                                         ▼                         ▼
                                ┌─────────────────┐       ┌──────────────────┐
                                │ .right-here/    │       │ Isolated Worktree│
                                │ worktrees/      │       │ (Clean Git State)│
                                └─────────────────┘       └──────────────────┘
```

When you right-click in Finder or run an action:
1. The **FinderSync Extension** resolves the container folder or selection.
2. It generates menu nodes in accordance with your `config.toml`.
3. Selecting an action invokes `rh` runner via `posix_spawn`, which resolves the configured terminal or editor adapter and dispatches the task safely into your environment.
4. When `--worktree` is specified, Right Here branches a clean git worktree under `.right-here/worktrees/`, automatically adds `.right-here` to `.git/info/exclude`, and launches the agent in that isolated environment.

## What you get

Right-click a folder, a file, or the empty canvas of a Finder window:

- **Open in a terminal or editor**: Ghostty, Terminal, iTerm2, WezTerm, kitty, VS Code, Cursor, Zed, and Antigravity.
- **Start an AI agent here**: Launch Google Antigravity (`agy`), Claude Code, or Codex directly inside your chosen terminal. The command is typed into your own interactive login shell, preserving your environment, `PATH`, `nvm`, and aliases.
- **Isolated Git Worktrees**: Run agents in dedicated worktree branches (`rh run agent.agy --worktree`), protecting your active working tree from partial AI edits.
- **Folder Bookmarks & Pins**: Pin frequently accessed project directories (`rh pin <folder>`), list them (`rh pins`), and inspect recent project directories (`rh recents`).
- **New file from templates**: Instantly create empty text or Markdown files (or custom project templates), automatically revealing or opening them.
- **Copy Path in any format**: Absolute, `~`-relative, git-repository-relative, bare filename, shell-escaped, or formatted as `@path` mentions ready for AI prompts.

Every action is accessible via the CLI:
```sh
rh run agent.claude
rh run agent.agy --worktree
rh run copy-path.git-relative src/main.swift
rh run new-file.md --container ~/notes
```
Add `--dry-run --json` to inspect the exact planned execution before running.

## Install

### Download DMG (Recommended)

1. Download the latest release from [GitHub Releases](https://github.com/boyugou/right-here/releases/latest).
2. Open `RightHere-macOS-arm64.dmg` and drag **Right Here.app** into `/Applications`.
3. Open **Right Here.app** and follow the guided setup to enable the Finder extension in macOS System Settings.

### Build from source

Requires Xcode 26 or later and `xcodegen`:

```sh
brew install xcodegen
./script/install_local.sh     # build, copy to ~/Applications, link rh into ~/.local/bin, enable extension
rh doctor                     # verify all diagnostics pass
```

If `rh doctor` indicates the extension needs activation, toggle Right Here under **System Settings › General › Login Items & Extensions › Finder**.

## Use

```sh
rh init                       # create ~/.config/right-here/config.toml
rh menu                       # preview the Finder menu (--explain shows filtered items)
rh actions                    # list all actions available in the current directory
rh run agent.claude           # launch Claude Code in current directory
rh run agent.agy --worktree   # launch Antigravity in an isolated git worktree
rh worktree list              # list active git worktrees
rh pins                       # list pinned directories
rh doctor                     # run full diagnostic health check
rh doctor --probe-launch      # test terminal AppleEvent automation launch
```

Shell completions:
```sh
rh --generate-completion-script zsh > ~/.zfunc/_rh
```

## Configure

Configuration is stored in `~/.config/right-here/config.toml`, validated strictly against a schema:

```toml
[general]
terminal = "ghostty"
terminal_placement = "tab"                     # open in tab instead of new window
editor = "vscode"
agents = ["claude", "agy", "codex", "lazygit"] # enabled agents in menu order

[menu]
items = ["open-terminal", "open-editor", "agents", "-", "new-file", "copy-path"]

[new_file]
then = "open"

[[new_file.template]]
id = "md"
title = "Markdown Document"
extension = "md"
open_with = "typora"

[agent.claude]
command = "claude --model opus"

[agent.agy]
name = "Antigravity"
command = "agy"

[agent.lazygit]
name = "lazygit"
command = "lazygit"
```

- Validate configuration: `rh config validate` (supports `--strict`).
- Inspect configuration files: `rh config show`.
- Export schema: `rh config schema`.
- Sync across machines: `rh config sync enable` (uses private folder or iCloud Drive; commands are protected by `--allow-commands`).

## Connect an AI Assistant

### Claude Code Plugin

Install the official Right Here plugin in Claude Code for contextual workspace actions and Finder automation ([`plugins/right-here`](plugins/right-here/README.md)):

```sh
/plugin marketplace add boyugou/right-here
/plugin install right-here@right-here
```

### Model Context Protocol (MCP)

To connect Claude Desktop, Cursor, Zed, Windsurf, or Antigravity, add `rh mcp` as a stdio server:

```json
{
  "mcpServers": {
    "right-here": {
      "command": "rh",
      "args": ["mcp"]
    }
  }
}
```

The server provides typed tools:
- `right_here_actions`: List available contextual actions for any path.
- `right_here_run`: Execute an action (`agent.*`, `copy-path.*`, `new-file.*`) with dry-run support.
- `right_here_finder`: Query current Finder selection or active window folder.
- `right_here_worktree`: Create, list, or remove isolated git worktrees.

### Automated Setup via AI

Right Here provides an automated onboarding guide for AI assistants:
- Run `rh docs agent-setup` for the full agent playbook.
- In **Right Here.app**, click **Copy Setup Prompt for AI** to have your assistant verify dependencies and configure your system.

## Safety & App Store Readiness

- **Data isolation**: File paths are strictly processed as argv arguments and AppleScript descriptors, preventing shell injection vulnerabilities.
- **Type verification**: Terminal actions verify that target directories are valid containers before launching.
- **Zero telemetry**: Right Here contains no analytics, network trackers, or resident daemons. The sandboxed extension has zero network entitlements.
- **App Store / TestFlight target**: Right Here includes a sandboxed, menu-only App Store edition draft adhering to strict Apple Sandbox requirements with zero temporary entitlements.
- See [`docs/DESIGN.md`](docs/DESIGN.md) and [`docs/appstore/METADATA.md`](docs/appstore/METADATA.md).

## Languages

Right Here supports 30 languages with native scripts and right-to-left layout support (Arabic, Bengali, German, Greek, English, Spanish, Persian, French, Hebrew, Hindi, Indonesian, Italian, Japanese, Korean, Marathi, Malay, Dutch, Polish, Portuguese, Russian, Swedish, Tamil, Telugu, Thai, Turkish, Ukrainian, Urdu, Vietnamese, Simplified Chinese, Traditional Chinese).

The command-line interface stays in English for predictable scripting.

## License

Apache-2.0. See [`LICENSE`](LICENSE) for details.
