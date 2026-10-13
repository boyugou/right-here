# Right Here

Send "here" (a folder, or whatever you selected in Finder) to your terminals, editors and AI agents.

Right Here is a small action layer for macOS: a command-line tool (`rh`), a plain-text config file, and
Finder entry points (a right-click menu and Quick Actions). People use the actions from Finder; AI agents
use the same actions from the command line or over MCP.

## What you get

Right-click a folder, a file or the empty background of a Finder window:

- **Open in a terminal or editor**: Ghostty, Terminal, VS Code, and any app you add.
- **Start an AI agent here**: "Claude Code Here", "Codex Here" and others, in the terminal you choose. The
  command is typed into your own login shell, so nvm, your PATH and your aliases apply, and the shell stays
  open when the agent exits. More options sit one level down: continue the last session, resume one, the
  agent's own terminal link, its desktop app.
  Claude Code and Codex each exist as a command-line tool and as a desktop app. "Claude Code Here" and
  "Codex Here" type the command into a terminal; "in Desktop App" opens the desktop app on the folder. To make
  the desktop app an agent's main entry, set `launcher = "desktop"` under `[agent.claude]` (or `codex`) in the
  config; `rh docs config` lists the launchers (a terminal id, `default`, `link` or `desktop`).
- **New file**: an empty text or Markdown file (or your own templates), then reveal it or open it.
- **Copy Path**: absolute, `~`-relative, relative to the git root, file name, shell-escaped, or an `@path`
  mention to paste into an agent's prompt.

Everything is also a command: `rh run agent.claude`, `rh run copy-path.git-relative src/main.swift`.
Add `--dry-run --json` to see exactly what an action would do before it does it.

There is no resident process: the Finder extension only exists while Finder runs, and `rh` runs only
when something calls it.

## Install

Right Here is not released yet. Build and install it from source (Xcode 26 or later, `xcodegen`):

```sh
brew install xcodegen
./script/install_local.sh     # build, copy to ~/Applications, link rh into ~/.local/bin, enable the extension
rh doctor                     # check everything
```

If `rh doctor` says the Finder extension is switched off, turn on Right Here in System Settings, General,
Login Items & Extensions, Finder. Notarized downloads and a Homebrew cask are on the
[roadmap](ROADMAP.md). Details: [`docs/development/SETUP.md`](docs/development/SETUP.md).

## Use

```sh
rh init                       # create ~/.config/right-here/config.toml from what is installed
rh menu                       # preview the Finder menu
rh actions                    # every action available here (--all adds the ones that are not, and why)
rh run agent.claude           # start Claude Code in the current folder, in your terminal
rh run copy-path.git-relative src/main.swift
rh run new-file.md --container ~/notes
rh doctor                     # check the setup
rh doctor --probe-launch      # prove a click can start a command in your terminal (a window opens and closes)
```

Shell completions: `rh --generate-completion-script zsh` (or `bash`, `fish`) prints a script; the Homebrew
formula installs them, and a man page (`man rh`).

The app's setup window shows the same menu under "Finder menu", with its own icons and submenus that open in place,
whether or not the Finder extension is switched on yet.

The Finder menu is not shown inside iCloud Drive (including a synced Desktop or Documents folder), a
limit of Finder extensions. The same actions are installed as **Quick Actions**, which work there and take
keyboard shortcuts: System Settings, Keyboard, Keyboard Shortcuts, Services, Files and Folders.

The first time an action controls a terminal, macOS asks whether Right Here may. Allow it once. If something
does not work, start with `rh doctor` and [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

## Configure

One TOML file, `~/.config/right-here/config.toml`, which the app never rewrites. For example:

```toml
[general]
terminal = "ghostty"
terminal_placement = "tab"           # a new tab in the front Ghostty window instead of a new window
editor = "vscode"
agents = ["claude", "codex", "lazygit"]   # what the menu offers, in order (custom agents too)

[menu]
items = ["open-terminal", "open-editor", "agents", "-", "new-file", "copy-path"]

[new_file]
then = "open"                        # open a new file after creating it...

[[new_file.template]]                # ...Markdown in Typora (defining templates replaces the built-in two)
id = "md"
title = "Markdown Document"
extension = "md"
open_with = "typora"

[agent.claude]
command = "claude --model opus"      # what is typed into the shell

[agent.lazygit]                      # any command you want started in the folder works like an agent
name = "lazygit"
command = "lazygit"
```

A terminal without a built-in adapter (WezTerm, kitty, Alacritty, ...) can start agents too, if you say how: give its
`[[app]]` entry `role = "terminal"` and `run_args`, an argument vector with `{dir}`, `{command}`, `{shell}` and `{app}`
placeholders (see `rh docs config`). Right Here has not tried those terminals, so check with `rh run agent.claude@<id> --dry-run`
and then for real.

`rh docs config` lists every key with defaults, `rh config validate` checks the file (each problem names its file and
line; unknown keys come with a "did you mean"; `--strict` also fails on warnings), `rh config show` prints the files that
make up the config, `rh config schema` prints a JSON Schema for your editor. `rh init --force` saves your old file
before replacing it.

To use one config on several Macs, `rh config sync enable` keeps a copy in a folder (iCloud Drive by default,
or any folder), and a `config.local.toml` next to the config holds what differs per machine (`rh docs sync`). The
folder is not trusted with programs: a pull that would add or change a terminal template or an agent command is
refused, with the list, until you pass `--allow-commands`.

## For AI agents

- `claude mcp add right-here -- rh mcp` adds an MCP server over the same actions: list and run them, read
  the menu, see what is selected in Finder, run the doctor, validate the config.
- Or install the Claude Code plugin from this repository (`/plugin marketplace add boyugou/right-here`),
  which also brings skills for setup, opening things, and showing the files an agent changed in Finder.
- `rh docs agent-setup` is the playbook an agent follows to set Right Here up for someone; the app has a
  "Copy Setup Prompt for AI" button that starts it.

File names in tool output are marked as data, and a terminal is only ever handed a folder.

## Safety

File names are data: they travel as argument-vector entries and AppleScript arguments, never as shell or
AppleScript source, and the quoting code is tested by round-tripping awkward names through real `sh`,
`bash` and `zsh` (and `fish` where it is installed). A terminal app that is handed a file would run it, so every terminal action validates
that its working directory is a folder. The Finder extension stays sandboxed; what it cannot do is done by
`rh` through a script only you can install. Configuration is never read from the folder being acted on.
Right Here makes no network connections and collects nothing: there is no network code, and the sandboxed
extension has no network entitlement. See [`docs/DESIGN.md`](docs/DESIGN.md), section 9.

## Languages

The menu, the app and alerts follow the system language, in thirty languages. The translations were
machine-generated, are marked for native-speaker review, are under Apache-2.0, and corrections are welcome
(see [`CONTRIBUTING.md`](CONTRIBUTING.md)); the command line stays English.

## Requirements and status

macOS 26 or later on Apple silicon. Early development: the core, the command line, the Finder extension,
Quick Actions, the MCP server and the plugin work and are tested. Design notes and decisions live in
[`docs/`](docs/INDEX.md); what is next is in the [roadmap](ROADMAP.md).

## License

Apache-2.0. See [`LICENSE`](LICENSE).
