<div align="center">

<img src="Apps/RightHere/icon-1024.png" alt="Right Here Icon" width="128" height="128">

# Right Here

**Act on the folder you are looking at. Right here.**<br>
The open-source action layer for macOS: send folders and selections to terminals, editors, and AI agents.

[![License](https://img.shields.io/badge/license-Apache--2.0-blue?style=flat-square)](LICENSE)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)](.)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black?style=flat-square&logo=apple&logoColor=white)](.)
[![MCP Server](https://img.shields.io/badge/MCP-Server%20(stdio)-6B57D2?style=flat-square)](.)
[![Languages](https://img.shields.io/badge/languages-30%20locales-orange?style=flat-square)](.)

[Website](https://boyugou.github.io/right-here/) · [Install](#install) · [CLI Usage](#use) · [Connect AI Assistant](#connect-an-ai-assistant) · [Architecture](#how-it-works) · [Documentation](docs/INDEX.md) · [Changelog](CHANGELOG.md) · [Roadmap](ROADMAP.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)

<br>

<table>
  <tr>
    <td align="center" width="33%"><b>Finder Menu & Workspace App</b></td>
    <td align="center" width="33%"><b>AI Agents & Isolated Worktrees</b></td>
    <td align="center" width="33%"><b>Unified CLI & Automation</b></td>
  </tr>
  <tr>
    <td align="left"><sub>Open any folder or selection in your terminal or editor: Ghostty, Terminal, iTerm2, WezTerm, kitty, VS Code, Cursor, Zed and more. A setup app with a live preview of the Finder menu and diagnostics.</sub></td>
    <td align="left"><sub>Start Claude Code, Codex, Antigravity (<code>agy</code>) or any command-line agent in your own login shell. Run one in an isolated git worktree (<code>--worktree</code>) to keep it away from your working copy.</sub></td>
    <td align="left"><sub>No daemon of its own. Every menu action is an <code>rh run</code> command you can dry-run, with JSON output and an MCP server for AI assistants.</sub></td>
  </tr>
</table>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/setup-dark.png">
  <img src="docs/images/setup-light.png" alt="The Right Here setup window: a sidebar of six sections (Overview, Finder menu, Checks, AI Assistants, Worktrees, Folders) and a preview of the Finder menu for a folder: Open in Ghostty, Open in Visual Studio Code, Claude Code Here, Codex Here, New File and Copy Path." width="640">
</picture>

<sub>The setup window with example data, rendered without a screen from the app's own view.</sub>

</div>

---

Right Here is a macOS action layer: a sandboxed Finder Sync extension, a command-line tool (`rh`), a plain-text configuration file (`~/.config/right-here/config.toml`) and a Model Context Protocol (MCP) server.

Developers use contextual right-clicks in Finder or the native macOS workspace app; AI assistants use the exact same actions from the terminal or over MCP.

- **No daemon of its own.** The Finder extension lives in the extension process Finder starts and keeps loaded (so the menu is there when you right-click); `rh` runs only when something calls it.
- **Isolated git worktrees.** AI coding agents can execute inside dedicated, temporary git worktrees (`--worktree`), ensuring your active git branch and uncommitted modifications remain untouched.
- **Safe by construction.** File names travel as argv entries and AppleScript arguments, never inside a shell string or AppleScript source; a terminal is only ever handed a folder. The extension is sandboxed and has no network entitlement.
- **One set of actions.** Anything in the Finder menu can be previewed, tested and run with `rh run <action>` or over MCP.
- **Local-first configuration.** Configured via standard TOML with JSON Schema validation (`rh config schema`) and optional multi-device sync without third-party servers.
- **Native.** Apple silicon, macOS 26 or later, Dark Mode, and 30 languages including right-to-left ones (machine-translated, awaiting native-speaker review).

**Status: beta.** The core, the command line, the Quick Actions, the MCP server and the plugin are tested with fakes and through real shells. What needs a real Finder and real terminals is not yet confirmed everywhere ([`docs/development/MANUAL_CHECKS.md`](docs/development/MANUAL_CHECKS.md) lists it): the 0.2.0 Finder extension crashed on macOS 26.5.1, the fix is in `main` and not yet confirmed on that system ([ADR 0019](docs/decisions/0019-no-swift-override-of-directory-observing.md)), and only Ghostty and Terminal were tried as terminals.

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
                                         │ runner script           ▼
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
3. Choosing an action hands it to `rh` through a runner script outside the extension's sandbox; `rh` resolves the configured terminal or editor and starts it.
4. When `--worktree` is specified, Right Here branches a clean git worktree under `.right-here/worktrees/`, automatically adds `.right-here` to `.git/info/exclude`, and launches the agent in that isolated environment.

## What you get

Right-click a folder, a file, or the empty canvas of a Finder window:

- **Open in a terminal or editor**: Ghostty and Terminal are verified on a real Mac; iTerm2, WezTerm and kitty are built in but not yet verified (`rh doctor --probe-launch` checks yours); VS Code, Cursor, Zed, Antigravity and other editors.
- **Start an AI agent here**: Claude Code, Codex, Antigravity (`agy`) and others, typed into your chosen terminal. The command is typed into your own interactive login shell, preserving your environment, `PATH`, `nvm`, and aliases.
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

A notarized DMG and a Homebrew cask are built by `script/package_dmg.sh` and `packaging/homebrew` (see [`docs/development/RELEASING.md`](docs/development/RELEASING.md)); downloads will be published with the first public release. Until then, build from source (Xcode 26 or later and `xcodegen`):

```sh
brew install xcodegen
./script/install_local.sh     # build, copy to ~/Applications, then run `rh setup`
```

Then, in three steps:

1. **Set up.** Open Right Here and press **Set Up** (it asks which terminal, editor and AI agents you use), or run `rh setup` in a terminal. It makes your config file, connects Finder and says what is left for you. Run it again at any time: it only does what is missing, and never rewrites a config that exists.
2. **Switch the extension on.** System Settings › General › Login Items & Extensions › Finder › Right Here. The app's window opens that page and notices when you switch it on.
3. **Right-click a folder** in Finder.

Or hand all of it to your AI assistant: **Copy Setup Prompt for AI** in the app, or tell it to run `rh docs agent-setup`.

## Use

```sh
rh setup                      # set everything up (--dry-run shows what it would do)
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
- Agents skip their own permission prompts only when you ask: `bypass_permissions` (off by default). `rh agents`, `rh doctor` and `rh menu --explain` say which agents do, and presets keep their prompts ([ADR 0016](docs/decisions/0016-agent-permissions-and-worktrees.md)).
- Sync across machines: `rh config sync enable` (uses private folder or iCloud Drive; commands are protected by `--allow-commands`).

## Connect an AI Assistant

### Claude Code Plugin

Install the official Right Here plugin in Claude Code for contextual workspace actions and Finder automation ([`plugins/right-here`](plugins/right-here/README.md)):

```sh
/plugin marketplace add boyugou/right-here
/plugin install right-here@right-here
```

### Model Context Protocol (MCP)

To connect Claude Desktop, Cursor, Zed, Windsurf, or Antigravity, add `rh mcp` as a stdio server. These apps start it with the `PATH` that macOS gives
a program launched from the Dock, where a bare `rh` is not found, so give the full path of `rh`: the link that `rh setup` makes in `~/.local/bin` (write it out, as in the example: JSON does not expand `~`) or the copy
inside the app. The app's **AI Assistants** section has a **Copy MCP Configuration** button that writes the snippet with the right path for this Mac.

```json
{
  "mcpServers": {
    "right-here": {
      "command": "/Users/you/.local/bin/rh",
      "args": ["mcp"]
    }
  }
}
```

The server provides typed tools:
- `right_here_actions`, `right_here_menu`, `right_here_catalog`: what can be done here, the menu, the terminals, editors and agents.
- `right_here_run`: run an action (`agent.*`, `copy-path.*`, `new-file.*`); use `dry_run` first.
- `right_here_finder_selection`: the current Finder selection or window folder.
- `right_here_doctor`, `right_here_config_validate`, `right_here_docs`: diagnostics and the built-in guides.
- `right_here_bookmarks`: pinned and recent folders.
- `right_here_worktree`: list, create or remove the isolated git worktrees Right Here made (never forced, never one you made yourself).

### Automated Setup via AI

Right Here provides an onboarding guide for AI assistants ([`docs/AGENT_SETUP.md`](docs/AGENT_SETUP.md), also `rh docs agent-setup`). The assistant asks which terminal, editor and AI agents you use, runs `rh setup` once with your answers, tells you what only you can do (such as switching the Finder extension on) and checks the result.
- In **Right Here.app**, click **Copy Setup Prompt for AI** and paste the prompt into your assistant.
- Or tell your assistant to run `rh docs agent-setup` and follow it.

## Safety & App Store Readiness

- **Data isolation**: File paths are strictly processed as argv arguments and AppleScript descriptors, preventing shell injection vulnerabilities.
- **Type verification**: Terminal actions verify that target directories are valid containers before launching.
- **No telemetry**: no analytics, no network connections of its own, nothing leaves your Mac. The sandboxed extension has no network entitlement.
- **Mac App Store**: a sandboxed, menu-only edition is drafted (scope and open questions in the design notes); it is not submitted.
- See [`docs/DESIGN.md`](docs/DESIGN.md) and [`docs/appstore/METADATA.md`](docs/appstore/METADATA.md).

## Languages

Right Here ships in 30 languages, right-to-left ones included: Arabic, Bengali, German, Greek, English, Spanish, Persian, French, Hebrew, Hindi, Indonesian, Italian, Japanese, Korean, Marathi, Malay, Dutch, Polish, Portuguese (Brazil), Romanian, Russian, Tamil, Telugu, Thai, Turkish, Ukrainian, Urdu, Vietnamese, Simplified Chinese and Traditional Chinese. The translations are machine-made and not yet reviewed by native speakers.

The command-line interface stays in English for predictable scripting.

## License

Apache-2.0. See [`LICENSE`](LICENSE) for details.
