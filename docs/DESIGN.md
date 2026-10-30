# Right Here: design

Status: working draft. The platform floor is macOS 26 (Apple silicon). Verified claims were tested on macOS 26.x
(build as reported by `sw_vers`) with Xcode 26 or later (see [`development/SETUP.md`](development/SETUP.md)) and
Ghostty 1.3.1.
Each platform claim is marked **verified** (tested on a real Mac), **sourced** (from Apple documentation, a
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

## 2. Goals and non-goals

Goals:

1. The everyday actions are instant and dependable: copy path, open in terminal or editor, start an
   agent, new text or Markdown file.
2. An AI agent can set it up and operate it without anyone clicking through a settings window.
3. No resident process. The Finder menu works whenever Finder runs.
4. Safe by construction: file names are data. They travel as arguments, and where a shell has to read one it is quoted by the single vetted quoting module first (section 9); they never become AppleScript source.
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
| `RightHereCore` | Pure logic: context, path styles, shell quoting, launch plans, planner, terminal adapters, catalogs, config parser and schema, menu builder. Foundation, TOMLDecoder (the config parser) and CryptoKit (the sync hash) only; deterministic; fully unit-tested. |
| `RightHereKit` | macOS runtime: real system facts, process runner, plan executor, config store, installer, doctor, extension manager, Finder query, failure alerts. |
| `RightHereMCP` | The MCP server over the same registry. |
| `rh` | The command-line tool (swift-argument-parser). |
| `Apps/RightHere` | The app: setup and status window, with a preview of the Finder menu. Dormant otherwise. |
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
| 6 | macOS 26 and later, Apple silicon only. | The project's decision; keeps the code free of fallbacks. |
| 7 | Direct distribution first (notarized DMG, Homebrew cask and formula); an App Store "menu only" build later. | [0001](decisions/0001-form-factor.md) |
| 8 | The MCP server is written against the protocol, with fenced file names and a folder-only working directory. | [0005](decisions/0005-mcp-server.md) |
| 9 | Thirty languages from a String Catalog compiled into Swift; human-facing surfaces follow the system language, the CLI and MCP stay English. | [0006](decisions/0006-localization.md) |
| 10 | A Mac App Store edition, if any, is a reduced menu-only app, built only after a one-day sandbox spike. | [0007](decisions/0007-app-store-edition.md) |
| 11 | Independent review and a cold-start usability test follow large changes; findings are reproduced first and each fix has a test that fails without it. | [0008](decisions/0008-independent-review.md) |
| 12 | Prompt presets (`[[preset]]`, `preset.<id>`) type the agent command with a quoted, validated prompt; they are sent when the agent starts, not left in the prompt box. | [0012](decisions/0012-agent-presets.md) |
| 13 | The config can be shared between Macs by copying it through a plain folder (`rh config sync`), with a never-synced per-machine overlay `config.local.toml`; no symlink, no CloudKit. | [0013](decisions/0013-config-sync.md) |
| 14 | An agent launch is resolved once, by one function that the planner, the menu and `rh agents` share. | [0014](decisions/0014-agent-launch-resolution.md) |
| 15 | The Finder extension stays loaded and holds no assertion that keeps the Mac awake. | [0015](decisions/0015-finder-extension-stays-loaded.md) |
| 16 | An agent's permission prompts are skipped only by an explicit per-agent launch option, never by a preset; worktrees live under `.right-here/worktrees` and are never removed by force. | [0016](decisions/0016-agent-permissions-and-worktrees.md) |
| 17 | The setup window has six sections (Overview, Finder menu, Checks, AI Assistants, Worktrees, Folders). | [0017](decisions/0017-setup-window-sections.md) |
| 18 | One idempotent `rh setup`, flags instead of editing the config, and a playbook for AI agents measured with cold agents. | [0018](decisions/0018-setup.md) |
| 19 | The Finder extension does not override the directory-observing methods, and the doctor reads its crash reports. | [0019](decisions/0019-no-swift-override-of-directory-observing.md) |
| 20 | What the config names (an app, an agent) is data: fenced between ⟦user⟧ marks wherever `rh setup` and `rh doctor` quote it in a sentence an agent passes on. | [0020](decisions/0020-names-from-the-config-are-data.md) |
| 21 | A process a test started (`RH_NO_UI`) without a trial home (`RH_HOME`) cannot change the real home or the Finder extension's registration. | [0022](decisions/0022-a-test-cannot-change-the-real-home.md) |
| 22 | The setup window says where the app runs from before it tries, only a first run's Set Up makes a config, and a warning the person may leave is not "needs attention". | [0023](decisions/0023-the-window-says-before-it-tries.md) |
| 23 | A built-in field of an agent (its prompt flag, its permission flag, its continue arguments) is confirmed by the tool's own documentation or help, or it is not there. | [0024](decisions/0024-a-built-in-agent-field-is-confirmed-or-absent.md) |
| 24 | The flags a built-in terminal adapter starts its terminal with are the ones the terminal documents; Alacritty has an adapter, kitty quits with its last window. | [0025](decisions/0025-terminal-launch-flags-are-the-documented-ones.md) |
| 25 | Direction: the window and the agents are two editors of one config file and can do the same things, through one format-preserving editing core; parity is tested; program-defining changes an agent proposes wait for the person. | [0026](decisions/0026-one-config-two-editors.md) |
| 26 | The menu given to Finder holds one small bitmap per icon (an `NSWorkspace` icon holds every size and weighs tens of megabytes), a menu that has grown old is served while a new one is built in the background, and below macOS 27 it has no separators, which Finder draws as empty rows. | [0027](decisions/0027-what-goes-to-finder-is-small-and-never-waited-for.md) |
| 27 | The app icon is an Icon Composer document (`Apps/RightHere/AppIcon.icon`) that Xcode compiles, so macOS draws its light, dark, tinted and clear looks; one exported PNG serves the README, the preview and the website. | [0028](decisions/0028-the-icon-is-an-icon-composer-document.md) |
| 28 | The setup window keeps its own SwiftUI views, restyled as a settings window of macOS 26 (no title bar, section tiles, grouped cards without an edge), so that the headless preview draws the real window. | [0029](decisions/0029-the-window-looks-like-a-settings-window-of-macos-26.md) |

## 5. Platform facts

Verified on macOS 26.x (build as reported by `sw_vers`):

- A Finder Sync extension signed with Developer ID, hardened runtime, sandboxed, with no provisioning
  profile loads. `pluginkit -a <appex>` then `pluginkit -e use -i <id>` makes Finder start it within
  seconds; Finder does not need a restart. Open and Save panels of other apps host it too. On a Mac where the switch in System Settings
  stays off after that, it is the person's to flip: the doctor says `needs-user`, and `rh setup` does not pretend otherwise.
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
  The extension builds a menu every time Finder asks (items, window background, sidebar, toolbar), so the tags
  are stable (`ActionTags`: an action id keeps its number, and the tag also names the kind of menu), and a
  click on an older menu cannot land on whatever stands at that position in a newer one.
- For a background (container) menu, `selectedItemURLs()` is the selection of the previous column in
  column view; the folder that was clicked is `targetedURL()`.
- `osascript -` with arguments delivers each argument unchanged to `on run argv`.
- `open -b com.mitchellh.ghostty <dir>` opens a window in that directory (paths with spaces included),
  also when Ghostty was not running. The Ghostty and Terminal.app AppleScripts compile against the
  installed dictionaries.
- `rh` builds a menu in about 20 ms including process start.
- A generated Quick Action workflow (hand-built `Info.plist` and `document.wflow`, in Automator's
  workflow format) is registered by `pbs`, and runs through
  `/usr/bin/automator` into `rh`, creating a file in the selected folder.
- The MCP server answers `initialize`, `tools/list` and `tools/call` over real stdio.
- A failure alert shown by `rh run --alert` blocks on a window instead of crashing, when started outside Finder.
- The whole chain a menu click uses works: the extension runs the runner script, which runs `rh`, which
  runs `osascript` to control Ghostty (`rh doctor --probe-extension`, 0.4 s). macOS holds the Finder
  extension responsible for the Apple events `rh` sends on its behalf (TCC logs name
  `com.boyugou.righthere.FinderExtension` as the responsible process), so the extension carries the
  `com.apple.security.automation.apple-events` entitlement; without it tccd logs that a hardened
  process lacking it cannot be prompted. Verified only where Ghostty already allowed the control: a first-ever
  permission prompt on a clean system has not been seen.
- An agent launch's typed input runs: `rh doctor --probe-launch` has the extension start a throwaway Ghostty
  session through the runner, `rh` and the Ghostty adapter. The session's folder is named with spaces,
  quotes, `$`, a backslash and a backtick; the typed command (`printf … > file; exit`) ran in that folder in the
  login shell (`/bin/zsh`), so the linefeed after `initial input` does press Return, the working directory
  is honored and nothing needed quoting. 1.1 s when warm (0.3 s to accept the Apple event); one cold run
  took 8.6 s, and the shell's own startup took about 1.7 s in that run. The same command runs in `sh`, `bash` and
  `zsh` in the unit tests.
- The Finder extension's real memory footprint is about 8 MB per process (`footprint`); the 60 MB that `ps`
  shows is shared framework pages. Several extension processes run at once (three were seen, and each
  started a probe when the marker appeared, which is why `rh` claims the marker). The claim is a `rename` to
  a name of the caller's own: eight concurrent `unlink`s of one path were measured returning success in
  393 of 400 rounds on APFS, while `rename` (and `O_EXCL`) never let two callers win in 2000. A request older
  than two minutes is ignored, so an interrupted `rh doctor` cannot open a terminal at some later Finder start.
- Release signing works: `SECURE_TIMESTAMP=1 ./script/build_app.sh` signs every code item with the Developer ID
  identity, hardened runtime and Apple's timestamp (the earlier "timestamps differ" failure was a wrong system
  clock), `script/package_dmg.sh` builds a DMG whose checksum file verifies with `shasum -c`, and the DMG's
  app verifies when mounted. The notarization pipeline (notarytool with a keychain profile, stapling, Gatekeeper
  assessment with `spctl`) runs end to end: Apple accepted the app and the DMG, both are stapled, and Gatekeeper
  reports `accepted` with `source=Notarized Developer ID`.

Sourced:

- FinderSync is not deprecated in macOS 27 (SDK headers). It does not show menus in iCloud Drive,
  including synced Desktop and Documents (Apple Developer Forums 737283). Quick Actions and Services are not affected, which is why they are a second surface.
- macOS 27 hides menu item images unless `preferredImageVisibility = .visible` is set (SDK header).
- App Group naming is sharp on macOS 26 and 27: `cfprefsd` drops writes to a bare `group.*` domain, and
  Group Containers are protected from other teams (Apple documentation). Right Here uses no App Group.
- Homebrew deprecated `post_install` and forbids writing `$HOME` from a formula; the official cask
  repository disables casks that fail Gatekeeper since 2026-09-01. So `rh setup` does the setup at
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
- A first-ever Automation prompt on a system that has never allowed the control.
- Items under Desktop, Documents and Downloads: whether `rh`, started through the runner script, may look at
  them. `lstat` failing with `EACCES` or `EPERM` is treated as "there, but nothing is known" (it is neither
  rejected as a typo nor taken for a folder), and a terminal action on such an item stops with an error that
  names the permission, never opening the folder around it. Only a real click shows whether this happens.
- Quick Actions that start an agent: which process macOS holds responsible for the Apple event (the
  Services runner, not the Finder extension) and so which Automation entry has to be allowed. It cannot be
  probed without a real invocation from Finder; `rh doctor --probe-launch` only covers the extension.
- That the tab placement really lands in a tab: `rh doctor --probe-launch --placement tab` passes (the session
  ran in the right folder) but cannot tell a tab from a window.
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
preset.<id>[@<terminal>]     new-file.<template>          reveal
```

`rh actions` lists what is available on the machine, with reasons for what is not. `rh docs actions` prints
the grammar. Agents come with variants (`agent.claude.continue`, `agent.codex.last`) and launchers: a
terminal id, `default`, `link` (the agent's own deep link) or `desktop` (its desktop app). A preset
(`preset.review`, config `[[preset]]`) sends a prompt template filled in from the selection to its agent as the
first argument ([0012](decisions/0012-agent-presets.md)).

## 7. Menu

`MenuBuilder` turns the config and a context (selected items, or a folder) into a menu tree. The default
layout is: open in terminal, open in editor, one entry per enabled agent, a "More Agent Options" submenu
(variants, alternative launchers and the "Agent Presets" submenu, which only lists presets that fit the selection: files
are needed for a prompt that names them, so a selection of only folders has none),
a separator, New File, Copy Path. `[menu] items` reorders or
replaces it with group names or any action id. Entries that cannot run here (the app is not installed,
the terminal cannot run commands) are not shown; `rh actions --all` and `rh doctor` say why. A default terminal or editor
the config sets that is not installed gives way to the first installed one (a config shared between Macs), and the doctor
says which app is used instead.

`MenuBuilder.explain` builds the same menu and, on the way, collects what the config asks for and the menu leaves out or
changes, with the planner's own sentence as the reason (`rh menu --explain`; `rh doctor` and `rh config validate` use the
same answer to say that a config leaves the menu empty for a folder, which nothing in its text would show). It reports the
default terminal and editor, the agents, the presets, New File, Copy Path and every entry the config names, and not every
uninstalled app of "Open With". The extension calls `build`, which collects nothing.

The plain agent entry starts the agent the way its `launcher` says (typed into the default terminal or the terminal the
agent names; its desktop app; its terminal link). "More Agent Options" offers the other ways and never the same one twice:
with `launcher = "desktop"` it leaves the desktop app out and lists the typed launch in the default terminal, under that
terminal's name. When `agents` is not among the entries there is no plain entry, and nothing is left out.

The extension caches the config by the modification dates of `config.toml` and the optional `config.local.toml` and installed-app lookups for 30 seconds, and
icons for the life of the process, so a right-click costs milliseconds.

The setup window shows this menu without Finder, so that a person can see what the extension will offer and why an
entry is missing (the extension needs System Settings and a Finder relaunch before anything shows).
`MenuPreview.folderMenu` runs `MenuBuilder` on the config and the installed apps as they are when the window opens or
`rh setup` has run, in the language of the window (`general.language`, or the system's), with the context the extension makes for a click on a folder's
background (`HereContext.finder`); `MenuPreview.rows` flattens the tree into the lines the window draws, with a
submenu opening in place. The app carries the extension's glyph catalog (`Apps/FinderExtension/Assets.xcassets`, a
source of both targets in `project.yml`), so the icons are the menu's own. The section "Finder menu" is open unless a
check needs attention (the first-run card and the list of checks keep the focus), until the person opens or closes it
once; it shows nothing when the config has errors (the extension would still offer what is valid in it, but a menu
drawn from a broken config says something that is not true, and the doctor's config row says what is wrong). It is the
menu for a folder: the items a selection of files adds (the agent presets) appear in Finder only. It is the same
code, not a statement about Finder; `docs/development/MANUAL_CHECKS.md` (5) compares the two in a real window.

## 8. Config

TOML, parsed by a pure-Swift library (TOMLDecoder) and checked against a schema that is also the source
of `rh docs config` and of the JSON Schema printed by `rh config schema`. Unknown keys are warnings with a
"did you mean" suggestion; wrong types and unknown references are errors; everything valid still
applies. Setup never rewrites a file that exists, and an edit that is asked for (`rh config set` and its kin) is made in place, in the smallest way, so comments and ordering
stay the person's, with the text before it kept for `rh config undo`. See [0004](decisions/0004-config.md) and [0026](decisions/0026-one-config-two-editors.md). An optional `config.local.toml` is merged over it (by id for apps, presets, templates
and variants, `disabled` to remove ids), and `rh config sync` copies `config.toml` to and from a plain folder; see
[0013](decisions/0013-config-sync.md).

## 9. Security

0. A terminal app handed a file runs it (a `.command` script). The working directory is therefore always
   validated to be a folder before any terminal action; a file becomes its folder, in the planner and again
   in every terminal adapter. Any path an action names that does not exist (a link that points nowhere does)
   is refused, whichever action it is for, so a typo is reported and never replaced by the folder around it,
   and text that is not a path never reaches the clipboard, a terminal or another agent's prompt box. A path
   the system merely refuses to look at (privacy-protected folders) counts as present. `open` runs in `/`: it takes
   an argument that also names a file under its working directory for that file, and a link such as `warp://…` read
   as a path is a relative one, which a cloned repository could hold.
1. File names are data. A path never becomes shell or AppleScript source: values travel as argv entries
   or as AppleScript `on run argv` arguments; the single quoting module works on Unicode scalars (a quote
   followed by a combining mark is still a quote to a shell) and is tested by round-tripping every
   metacharacter with every joining mark, plus a seeded fuzz, through real `sh`, `bash` and `zsh` (and `fish`
   where it is installed; CI installs it). Terminal.app is the one adapter that types the folder (`cd …`)
   into a shell the adapter cannot see (the profile's, not necessarily the account's), so it quotes the folder
   the one way sh, bash, zsh, dash, ksh and fish agree on and refuses a backslash, the character that splits fish
   from the rest (csh and tcsh also expand `!` inside single quotes, which in a new session only makes the `cd`
   fail, so nothing runs).
   Paths are cut at slash scalars, as the kernel cuts them, so a combining mark cannot hide a `..`.
2. Text typed into a terminal is read as keystrokes, so a command line with a line break or any control character
   is refused for typed launches, and so is a folder whose path has one when the terminal types the folder (`cd …`):
   Terminal, iTerm and a terminal defined in the config, whose template may put `{dir}` into a shell line (an adapter
   that says nothing about it is held to that rule). Ghostty, WezTerm and kitty are handed the folder as an argument
   and type none of it, so they take any folder name. Deep links percent-encode everything but unreserved characters. A preset's
   prompt (a template plus file names) is typed as one single-quoted word, and the expanded text is refused when it
   has a control character, a character that shows nothing or changes how the text reads (a tag character spells ASCII
   that the agent reads and the person does not see; a direction override reorders what the person sees), a backslash
   (fish and the other shells read it differently inside quotes), a leading dash (the agent would read an option) or more
   files than `max_files`; see [0012](decisions/0012-agent-presets.md). A preset keeps the agent's permission prompts on,
   so an agent whose command, arguments or first-prompt flag carry its flag that switches them off (a preset types no start option), however it is spelled or quoted (the line is read as bash and zsh read it: quotes, `$'…'`,
   a redirection, an assignment or a wrapper before the program, another case), is not started by one; a command whose words depend on something that is not in it (`$x`, `$(…)`, `{a,b}`, a quote that is never closed, an escape of `$'…'` that bash and zsh read differently, a NUL) is refused for a
   preset as well, since the flag may be behind it; the reading is compared with what `/bin/zsh` and `/bin/bash` make of a thousand generated lines (`ShellWordsRealShellTests`). Presets
   are sent when the agent starts, and a file name becomes part of the instruction the agent reads, so they are for
   folders the person trusts; the built-ins are read-only only in their wording.
3. The sandbox stays on for the extension. What it cannot do is done by `rh` through the runner script,
   which only the user can install and which passes on only the shapes the extension sends (`run --alert <action>
   --origin <origin> [--container <folder>] -- <items>` and the two probes) and builds the command from the parts it
   has checked: a compromised extension cannot call `rh setup`, `rh install`, `rh uninstall` or `rh init --force`, and
   cannot start an agent with its permission prompts off (`--bypass-permissions`), with a prompt of its own (`--arg`) or
   in a new worktree. What it can still ask for is any action of the person's config on files that exist.
4. Configuration is never loaded from the folder being acted on. The one other place a config comes from is the sync
   folder, which item 7 guards.
5. `rh` itself is not privileged and needs no administrator rights anywhere.
6. Tool arguments from an AI agent are validated against the declared schema before anything runs, and the number
   and length of paths are capped. What a call would open or create is added up from its plan (a document, a
   Finder window, a new file: one unit each; a started command or link: three) and charged against twenty-four
   units a minute, so a loop cannot flood the screen however it splits the work; a dry run is free. Only existing
   paths are copied to the clipboard. Tool calls run eight at a time, up to 256 (and 16 MB of requests) are held waiting
   for a turn, a call past that is answered with a server-busy error at once, `ping` and the other quick requests are
   never held up, and a request line is capped at 2 MB.
   Names in logs and plan output have control characters escaped, and so have the characters that draw nothing (the Unicode tag
   characters that spell ASCII, the zero-width space, the byte order mark, a joiner that joins nothing, a run of variation selectors:
   a name that shows as `report.txt` must not carry a sentence for an agent), and the log is private and capped. The values of every
   English sentence the doctor says (on the command line, in `--json` and in the MCP tool) are escaped the same way, whoever builds the sentence,
   and so is every line `rh` prints (line feeds and tabs stay) and every JSON it prints (as JSON escapes, which read back as the same text), and the branch names that the setup window lists for a repository's worktrees (git accepts U+202E in one). So does what a
   config problem quotes from the config (a key, a value, an id): `ConfigDiagnostic` stores its text escaped, since a
   config can arrive from the sync folder and an escape sequence in a key name must not act on a terminal. The names
   and titles a config gives to apps, agents, templates, variants and presets, and the file name and extension of a template,
   are refused when they hold a control
   character, or a character that makes the name read as something else than it says (a direction override, embedding or
   isolate, a zero-width space, a word joiner, a byte order mark, a soft hyphen, a tag character, a mark or letter that Unicode shows as nothing (the combining grapheme joiner U+034F, the
   Khmer inherent vowels U+17B4 and U+17B5, the Hangul fillers), a variation selector that selects nothing where it stands: one of U+FE00 to U+FE0D after an ASCII character, any
   selector after another one, after something that shows nothing (a joiner, U+034F) or at the start, or one of the supplement that is not after an ideograph; U+FE0E and U+FE0F, which pick the text or the
   emoji form, may stand after any character that shows) or when they are longer than 120 characters (240 for the file name and the extension of a template): an error, and the entry is
   left out, on every path that writes one (the window, `rh config`, the MCP tool, a hand edit, the sync folder). The marks
   a script is written with (left-to-right and right-to-left marks, the joiners of Persian and Indic words) stay, and
   `rh actions`, `rh menu`, `rh apps` and `rh agents` print a name with whatever draws nothing in it as escapes in any case. The MCP tools that list them
   (`right_here_actions`, `right_here_menu`, `right_here_catalog`) mark them as data in their text, like the doctor does,
   and keep the structured data plain.
7. A config is more than settings: terminal templates (`open_args`, `run_args`), agent commands, variant arguments,
   first-prompt flags, an agent's own `args`, its `bypass_permissions` and the flag it types (`bypass_permission_arg`), and the contents of a new-file template (written into a file that is then opened)
   decide which program a click starts, and how, and a terminal listed as another kind of app is handed
   files, which it runs (item 0): the config refuses an `[[app]]` with a built-in terminal's bundle identifier (in any case, as the system finds an app by it whatever the case) and another role, and a pull lists one
   that carries the identifier of a terminal the config defines. An assistant that changes one of them, or undoes a change of one, waits for the person's yes (`ConfigTrust`; see [0026](decisions/0026-one-config-two-editors.md)),
   and a proposal that switches the prompts off says which agents would start with which flag, and is applied only to the two files as they were when it was looked at (and, in the window, after the alert that names them).
   A pulled config that puts an agent in the menu or the Quick Actions while the prompts are off is listed too, and a pull is made under the lock that every change of the config takes, so an edit made while it compares and replaces the file is not written over. The sync folder can be written by things this Mac does not
   control (another machine, a sync service, a shared drive), so a config that arrives through it is untrusted input.
   `rh config sync pull` compares it with the config it replaces and refuses, listing what it would add or change (and an agent's
   arguments that it empties: `--sandbox read-only` may be what keeps the agent in its sandbox),
   unless `--allow-commands` is passed; that flag is separate from `--force`, and a refusal writes nothing. `status`
   and `enable` show the same list, and every value in it is printed with control characters escaped. Preset prompts
   are text for an agent, not commands, and stay under item 2. See [0013](decisions/0013-config-sync.md), "Trust".
8. A repository is somebody else's code to git: its hooks (files, and commands named in its configuration), `core.fsmonitor`, filter drivers and a
   partial clone's promisor remote all start programs. Right Here starts git in a repository only through one function (`GitCommand`), which
   switches those off for every command it runs (the person's own filters, Git LFS in the global configuration, still apply), keeps the
   commands that only read to twenty seconds, and reads the list of worktrees NUL-separated; see
   [0016](decisions/0016-agent-permissions-and-worktrees.md), "What git may start", for what was measured.

9. A test cannot change the real home: `rh` started with `RH_NO_UI` and without `RH_HOME` refuses to write the runner script, the command link or the Quick Actions, and to
   change the Finder extension's registration (`RealHomeGuard`; the writes of `rh config sync`, of `rh config` and of the config that `rh init` and `rh setup` make ask it too), and the mutation check stops at the first mutant that changes the runner script, the link or the Quick Actions; see
   [0022](decisions/0022-a-test-cannot-change-the-real-home.md), which says what happened before it.

An independent review and a cold-start usability test shaped several of these; see
[0008](decisions/0008-independent-review.md). The Mac App Store question is in [0007](decisions/0007-app-store-edition.md).

## 10. Working with AI agents

- `rh docs`, `rh actions --json`, `rh agents --json`, `rh apps --json`, `rh menu --json`,
  `rh config validate --json`, `rh config schema`, `rh doctor --json` describe and check everything.
  `rh docs agent-setup` is the playbook an agent follows to set Right Here up for someone.
- The app has a "Copy Setup Prompt for AI" button.
- Agents can start agents: `rh run agent.codex --container <dir>`.
- `rh mcp` is an MCP server over the same registry (twelve tools, including what is selected in Finder and two that read and change the config, ADR 0026),
  and `plugins/right-here` is a Claude Code plugin that starts it and adds skills for setup, opening
  things, and showing the files an agent changed in Finder. File names, and what the doctor and the config check quote
  from the config, are fenced as data in tool output, and so is what `rh setup` and `rh doctor` quote from the config in their text
  and in the `text` of their JSON ([0020](decisions/0020-names-from-the-config-are-data.md)).

## 11. Distribution

Direct first: a notarized, stapled DMG with the app (extension and `rh` inside), a Homebrew cask that
installs the app and links `rh`, and a formula for the CLI alone (Swift build), with `rh setup` doing
the per-user setup. An App Store build would be a menu-only app (sandboxed, no agent launching beyond
user-installed scripts); App Store guideline 2.4.5 and the sandboxed-CLI problems rule out the full
product there. The identifiers derive from `AppIdentity` in one place.

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
`needs_review`; the languages read through since are named in the [changelog](../CHANGELOG.md). The doctor returns a code and values for every sentence it says: the setup window writes them in its
language (`general.language`, or the system's), `rh doctor` and the MCP tool print their English, and `rh doctor --json` has both. The probes, the
parser's and the planner's own sentences (a config error, why an agent cannot start) and text quoted from the config stay
English in every language.

The text of the macOS Automation prompt (`NSAppleEventsUsageDescription`, which Apple's hardened-runtime guidance
asks for next to the apple-events entitlement, and App Review checks) is in `Localization/InfoPlist.xcstrings`.
Xcode compiles that one catalog into a `.lproj` folder per language in both the app and the extension.

## 14. Status

Working and tested headlessly: the core and CLI, the terminal adapters (Ghostty, Terminal.app, iTerm2,
WezTerm, kitty, Alacritty and Warp; cmux is handed the folder), the app and extension, installer, doctor,
Services, the MCP server and plugin, localization. The whole chain after a menu click is verified, typed
launch included (`rh doctor --probe-launch`); not yet confirmed is the click itself (see section 5, "Open").
Notarized, stapled DMGs are built and released (`script/package_dmg.sh`; the versions are in the
[changelog](../CHANGELOG.md)). What comes next is in the [roadmap](../ROADMAP.md).
