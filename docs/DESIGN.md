# Right Here: design

Status: working draft, 2026-10-12. Written against macOS 27.2 (build 26B5101f), Xcode 27.1, Ghostty 1.3.1.
Each platform claim is marked **verified** (tested on that machine), **sourced** (from Apple documentation, a
primary source or an issue tracker, with the source named) or **open** (not yet checked).

## 1. What it is

Right Here sends "here" (a folder, or whatever is selected in Finder) to terminals, editors and AI agents.

- A command-line tool, `rh`, is the core. It runs actions: copy a path in the form you need, open a
  folder in a terminal or editor, start an AI agent there, create a file.
- A plain-text config (`~/.config/right-here/config.toml`) says what is offered and how.
- Finder is one surface over the same actions: a right-click menu from a Finder extension, and Quick
  Actions (Services, which also take keyboard shortcuts). AI agents are another surface: they call `rh`
  or its MCP server and read the same config.

The form was chosen by what works, not by what is customary. A Finder menu cannot exist without an app
bundle that carries the extension, so there is an app. Everything the menu does is done by `rh`, which
is also what people and agents use directly, and which Homebrew can install on its own.

### Why this and not another RClick

The existing tools are Finder-menu apps (OpenInTerminal, RClick, iRightMouse and others). Reading their
issue trackers (2026-10-11) shows the recurring failures: the extension stops appearing after a macOS
update, actions silently do nothing under the sandbox, the menu needs a resident helper, terminals open
the wrong way, paths are not escaped. None of them pairs a documented text config with a CLI, none copies
git-root-relative or `@path` references, and none launches an AI agent in a terminal the user chose.
People ask for agent launching elsewhere (claude-code issue 54614, the claude-code-now launcher with 627
stars asking for Ghostty and Codex support). That is the opening: make the small daily actions fast and
dependable, and make them equally usable by people and by agents.

## 2. Goals and non-goals

Goals:

1. The everyday actions are instant and dependable: copy path, open in terminal or editor, start an
   agent, new text or Markdown file.
2. An AI agent can set it up and operate it without anyone clicking through a settings window.
3. No resident process. The Finder menu works whenever Finder runs.
4. Safe by construction: file names are data and never become shell or AppleScript source.
5. Open source (Apache-2.0), notarized direct distribution first, App Store possible later.

Non-goals: a file manager, a terminal, an AI chat interface, changing Finder's own behavior (that needs
code injection with SIP off), and loading executable configuration from project folders (a cloned
repository must not be able to run commands because it was right-clicked).

## 3. Architecture

```
 Finder right-click ──┐
 Finder toolbar ──────┤   FinderSync extension (sandboxed, thin)
 Quick Actions ───────┤        │ copy path: done in place
                      │        │ everything else: NSUserUnixTask
 Terminal, scripts ───┤        ▼
 MCP, AI agents ──────┴──►  rh  ──►  Planner (pure) ──► LaunchPlan ──► Executor
                                         ▲                               open · osascript ·
                                config.toml + catalogs                  pasteboard · new file
```

| Module | Role |
|---|---|
| `RightHereCore` | Pure logic: context, path styles, shell quoting, launch plans, planner, terminal adapters, catalogs, config parser and schema, menu builder. Foundation only; deterministic; fully unit-tested. |
| `RightHereKit` | macOS runtime: real system facts, process runner, plan executor, config store, installer, doctor, extension manager, Finder query, failure alerts. |
| `RightHereMCP` | The MCP server over the same registry. |
| `rh` | The command-line tool (swift-argument-parser). |
| `Apps/RightHere` | The app: setup and status window. Dormant otherwise. |
| `Apps/FinderExtension` | The Finder Sync extension. Builds the menu and hands actions over. |

The key idea is the **launch plan**: planning turns an action, a context, the config and facts about the
machine into plain data (`LaunchPlan`: open an app, open a URL, run AppleScript with arguments, copy to
the clipboard, create a file). The executor carries it out. `rh run --dry-run --json` prints the plan, so
an agent can inspect an action before it runs, and tests assert on plans without touching the system.

## 4. Decisions

Short records with the full reasoning are in [`decisions/`](decisions/).

| # | Decision | Why |
|---|---|---|
| 1 | CLI core, app bundle for the Finder extension, Homebrew-friendly. | [0001](decisions/0001-form-factor.md) |
| 2 | The extension is thin and stateless, reads the config directly, and has no App Group. | [0002](decisions/0002-finder-extension.md) |
| 3 | The extension reaches `rh` through a runner script run by `NSUserUnixTask`. | [0002](decisions/0002-finder-extension.md) |
| 4 | Agents start by typing the command into the user's own login shell. | [0003](decisions/0003-agent-launch.md) |
| 5 | The config is TOML, described by a schema; the app does not rewrite it. | [0004](decisions/0004-config.md) |
| 6 | macOS 26 and later, Apple silicon only. | The owner's call; keeps the code free of fallbacks. |
| 7 | Direct distribution first (notarized DMG, Homebrew cask and formula); an App Store "menu only" build later. | [0001](decisions/0001-form-factor.md) |
| 8 | The MCP server is written against the protocol, with fenced file names and a folder-only working directory. | [0005](decisions/0005-mcp-server.md) |
| 9 | Thirty languages from a String Catalog compiled into Swift; human-facing surfaces follow the system language, the CLI and MCP stay English. | [0006](decisions/0006-localization.md) |

## 5. Platform facts

Verified on this machine (macOS 27.2, 2026-10-11):

- A Finder Sync extension signed with Developer ID, hardened runtime, sandboxed, with no provisioning
  profile loads. `pluginkit -a <appex>` then `pluginkit -e use -i <id>` makes Finder start it within
  seconds; Finder does not need a restart. Open and Save panels of other apps host it too.
- Registering the same extension identifier from two places (an Xcode build folder and the installed
  app) makes launchd remove every running instance. The installer unregisters stale copies.
- A sandboxed extension finds the real home with `getpwuid`. A `temporary-exception.files.home-relative-path.read-only`
  entry makes exactly that folder readable; reading anything else is denied.
- `NSWorkspace.urlForApplication` and `icon(forFile:)` work in the sandbox.
- `NSUserUnixTask` runs a script from `~/Library/Application Scripts/<extension bundle id>/` outside the
  sandbox, as the user: arguments arrive intact (spaces, quotes, `$HOME`, newlines), PATH is only
  `/usr/bin:/bin:/usr/sbin:/sbin` plus whatever launchd carries, and the parent process is
  `com.apple.foundation.UserScriptService`. So the script names `rh` by absolute path.
- Finder serializes the menu: only `NSMenuItem.tag` survives to the action method, not `representedObject`.
- For a background (container) menu, `selectedItemURLs()` is the selection of the previous column in
  column view; the folder that was clicked is `targetedURL()`.
- `osascript -` with arguments delivers each argument unchanged to `on run argv`.
- `open -b com.mitchellh.ghostty <dir>` opens a window in that directory (paths with spaces included),
  also when Ghostty was not running. The Ghostty and Terminal.app AppleScripts compile against the
  installed dictionaries.
- `rh` builds a menu in about 20 ms including process start.
- A generated Quick Action workflow (hand-built `Info.plist` and `document.wflow`, in the format of the
  workflows already in `~/Library/Services`) is registered by `pbs`, and runs through
  `/usr/bin/automator` into `rh`, creating a file in the selected folder.
- The MCP server answers `initialize`, `tools/list` and `tools/call` over real stdio.
- A failure alert shown by `rh run --alert` blocks on a window instead of crashing, when started outside Finder.
- The whole chain a menu click uses works: the extension runs the runner script, which runs `rh`, which
  runs `osascript` to control Ghostty (`rh doctor --probe-extension`, 0.4 s). macOS holds the Finder
  extension responsible for the Apple events `rh` sends on its behalf (TCC logs name
  `com.boyugou.righthere.FinderExtension` as the responsible process), so the extension carries the
  `com.apple.security.automation.apple-events` entitlement; without it tccd logs that a hardened
  process lacking it cannot be prompted. Verified only where Ghostty already allowed the control: a first-ever
  permission prompt on a clean machine has not been seen.
- An agent launch's typed input runs: `rh doctor --probe-launch` has the extension start a throwaway Ghostty
  session through the runner, `rh` and the Ghostty adapter. The session's folder is named with spaces,
  quotes, `$`, a backslash and a backtick; the typed command (`printf … > file; exit`) ran in that folder in the
  login shell (`/bin/zsh`), so the linefeed after `initial input` does press Return, the working directory
  is honored and nothing needed quoting. 1.1 s when warm (0.3 s to accept the Apple event); one cold run
  took 8.6 s, and the shell's own startup is about 1.7 s here. The same command runs in `sh`, `bash` and
  `zsh` in the unit tests.

Sourced:

- FinderSync is not deprecated in macOS 27 (SDK headers). It does not show menus in iCloud Drive,
  including synced Desktop and Documents (Apple Developer Forums 737283; reproduced on 27.0 by the
  `newfile` project). Quick Actions and Services are not affected, which is why they are a second surface.
- macOS 27 hides menu item images unless `preferredImageVisibility = .visible` is set (SDK header).
- The breakages reported for Finder tools on macOS 26 and 27 were App Group naming: `cfprefsd` drops
  writes to a bare `group.*` domain, and Group Containers are protected from other teams (OpenInTerminal
  pull request 285; Apple documentation). Right Here uses no App Group.
- Homebrew 7.0 deprecated `post_install` and forbids writing `$HOME` from a formula; the official cask
  repository disables casks that fail Gatekeeper since 2026-09-01. So `rh install` does the setup at
  runtime and the app is notarized.
- A shell started by a GUI app has no nvm or alias: `zsh -lc` does not find `claude` (nvm is initialized
  in `.zshrc`), `zsh -lic` does. Text typed into a terminal's shell gets the full interactive setup.
- Claude Code registers `claude-cli://open?cwd=…&q=…`, which opens its last-used terminal in a folder with
  a prefilled, unsent prompt (code.claude.com/docs/en/deep-links). Codex has `codex://threads/new?path=`
  for its desktop app. Ghostty 1.3.1 supports AppleScript, with `new surface configuration`,
  `initial working directory` and `initial input`.

Open (to check on a real run, in the order they matter):

- A real Finder click reaching `rh`: the tag dispatch of the menu action. Everything after it is verified
  (above). The extension and `rh` log each step at notice level (`log show --predicate 'subsystem ==
  "com.boyugou.righthere.FinderExtension"'`, and `~/Library/Logs/right-here/rh.log`).
- A first-ever Automation prompt on a machine that has never allowed the control.
- Quick Actions that start an agent: which process macOS holds responsible for the Apple event (the
  Services runner, not the Finder extension) and so which Automation entry has to be allowed. It cannot be
  probed without a real invocation from Finder; `rh doctor --probe-launch` only covers the extension.
- The items, sidebar and toolbar menus (the container menu has been observed).
- Whether Quick Actions appear on a folder's empty background.
- A cold start of Terminal.app or Ghostty through AppleScript may open an extra startup window.

## 6. Actions and ids

An action id is stable text that people and agents write:

```
copy-path.<style>            absolute, tilde, git-relative, name, parent, shell-escaped, shell-quoted,
                             file-url, ai-mention, markdown-link
open.terminal[@<terminal>]   open.editor   open.app.<app>
agent.<agent>[.<variant>][@<launcher>]
new-file.<template>          reveal
```

`rh actions` lists what is available on the machine, with reasons for what is not. `rh docs actions` prints
the grammar. Agents come with variants (`agent.claude.continue`, `agent.codex.last`) and launchers: a
terminal id, `default`, `link` (the agent's own deep link) or `desktop` (its desktop app).

## 7. Menu

`MenuBuilder` turns the config and a context (selected items, or a folder) into a menu tree. The default
layout is: open in terminal, open in editor, one entry per enabled agent, a "More Agent Options" submenu
(variants and alternative launchers), a separator, New File, Copy Path. `[menu] items` reorders or
replaces it with group names or any action id. Entries that cannot run here (the app is not installed,
the terminal cannot run commands) are not shown; `rh actions --all` and `rh doctor` say why.

The extension caches the config by modification time and installed-app lookups for 30 seconds, and
icons for the life of the process, so a right-click costs milliseconds.

## 8. Config

TOML, parsed by a pure-Swift library (TOMLDecoder) and checked against a schema that is also the source
of `rh docs config` and of the JSON Schema printed by `rh config schema`. Unknown keys are warnings with a
"did you mean" suggestion; wrong types and unknown references are errors; everything valid still
applies. The app never rewrites the file, so comments and ordering stay the owner's. See
[0004](decisions/0004-config.md).

## 9. Security

0. A terminal app handed a file runs it (a `.command` script). The working directory is therefore always
   validated to be a folder before any terminal action; a file becomes its folder and a missing path is
   refused, on the planner, in every terminal adapter and on the MCP path.
1. File names are data. A path never becomes shell or AppleScript source: values travel as argv entries
   or as AppleScript `on run argv` arguments; the single quoting module is tested by round-tripping
   awkward names through real `sh`, `bash` and `zsh`.
2. Text typed into a terminal is read as keystrokes, so a path with a line break or any control character
   is refused for typed launches. Deep links percent-encode everything but unreserved characters.
3. The sandbox stays on for the extension. What it cannot do is done by `rh` through the runner script,
   which only the user can install.
4. Configuration is never loaded from the folder being acted on.
5. `rh` itself is not privileged and needs no administrator rights anywhere.

## 10. Working with AI agents

- `rh docs`, `rh actions --json`, `rh agents --json`, `rh apps --json`, `rh menu --json`,
  `rh config validate --json`, `rh config schema`, `rh doctor --json` describe and check everything.
  `rh docs agent-setup` is the playbook an agent follows to set Right Here up for someone.
- The app has a "Copy Setup Prompt for AI" button.
- Agents can start agents: `rh run agent.codex --container <dir>`.
- `rh mcp` is an MCP server over the same registry (eight tools, including what is selected in Finder),
  and `plugins/right-here` is a Claude Code plugin that starts it and adds skills for setup, opening
  things, and showing the files an agent changed in Finder. File names in tool output are fenced as data.

## 11. Distribution

Direct first: a notarized, stapled DMG with the app (extension and `rh` inside), a Homebrew cask that
installs the app and links `rh`, and a formula for the CLI alone (Swift build), with `rh install` doing
the per-user setup. An App Store build would be a menu-only app (sandboxed, no agent launching beyond
user-installed scripts); App Store guideline 2.4.5 and the sandboxed-CLI problems rule out the full
product there. The name is a working name; the identifiers derive from `AppIdentity` in one place.

## 12. Risks

| Risk | Mitigation |
|---|---|
| macOS updates break the extension. | Services and `rh` keep working; `rh doctor` detects and repairs. |
| No menu in iCloud Drive. | Services and Quick Actions; documented. |
| Automation prompt confusion. | `rh run --alert` explains and links to the Settings page. |
| Config symlinked outside the sandbox exception. | `rh doctor` warns. |
| Agent CLIs change flags. | Variants are data in one catalog; the adapter list is small. |

## 13. Localization

Thirty languages from `Localization/Localizable.xcstrings`, compiled into Swift (see
[0006](decisions/0006-localization.md)). The initial translations are AI-generated and marked
`needs_review`.

The text of the macOS Automation prompt (`NSAppleEventsUsageDescription`, which Apple's hardened-runtime guidance
asks for next to the apple-events entitlement, and App Review checks) is in `Localization/InfoPlist.xcstrings`.
Xcode compiles that one catalog into a `.lproj` folder per language in both the app and the extension.

## 14. Status

Working and tested headlessly: the core and CLI, Ghostty and Terminal.app adapters, the app and
extension, installer, doctor, Services, the MCP server and plugin, localization. The whole chain after
a menu click is verified, typed launch included (`rh doctor --probe-launch`); not yet confirmed is the
click itself (see section 5, "Open"). Next: notarized packaging and adapters for other terminals. See the
[roadmap](../ROADMAP.md).
