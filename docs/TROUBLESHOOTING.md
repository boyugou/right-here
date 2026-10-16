# Troubleshooting

Start with `rh doctor`. Every check says what is wrong and what to run. `rh doctor --json` is the same for
scripts and AI agents, and `rh doctor --probe-launch` proves the whole click chain by opening and closing a
throwaway terminal window.

## The Finder menu does not appear

- `rh doctor` says the extension is switched off or not registered: run `rh install --finder`, or switch on
  Right Here in System Settings, General, Login Items & Extensions, Finder (the app's window has a button).
- `rh doctor` warns that the extension "crashed N times since this copy was installed": macOS keeps a report for each, as
  `~/Library/Logs/DiagnosticReports/FinderExtension-<date>.ips`, and a crashing extension leaves Finder's menu without
  Right Here's entries while it is registered and switched on. Version 0.2.0 crashed this way on macOS 26.5.1 every time Finder asked
  it to watch a folder (ADR 0019). The fix is in `main`; it has not yet been confirmed on that system. Install a current build, then
  look again: if the warning stays, the newest report names the code that crashed, and it is what to attach to a bug report. `rh doctor` and the
  setup window of the direct download both say this (the Mac App Store edition's window cannot read that folder).
- You are inside iCloud Drive (including a Desktop or Documents folder that syncs with iCloud). Finder does not
  show extension menus there; use the Quick Actions instead (right-click, Quick Actions), or give them keyboard
  shortcuts in System Settings, Keyboard, Keyboard Shortcuts, Services.
- The doctor warns that the extension is registered from more than one place (a build folder next to the installed
  app): `rh install --finder` removes the stale copies. macOS drops an extension that is registered twice.
- It worked until a macOS update: `rh install --finder` registers it again.
- You switched the extension on and the menu still does not appear: restart Finder (`killall Finder`; Finder reopens its
  windows). Whether a newly switched-on extension needs that on every macOS version is not verified on the development Mac.
- You run Right Here from a disk image or from Downloads: `rh install --finder` registers the extension of the Right Here.app
  that holds the `rh` it runs from, and an `rh` that is not inside an app takes the one macOS finds by its identifier. The
  registration is by that path, so once the image is ejected or the file is moved, the path it names no longer exists. Move
  Right Here.app to Applications and run `rh install --finder` from there.

## An entry I expect is missing from the menu

`rh menu --container <folder> --explain` prints the menu and then what it leaves out or changes, each with its reason:
an app that is not installed, "select one or more files" for the Agent Presets (a selected folder is not a file),
an agent your per-machine overlay disabled, a default terminal or editor that is not installed on this Mac (the first
installed one is used instead, so "Open in Terminal" still shows, under another name). `rh doctor` has a "Finder menu"
row, and `rh config validate` a warning, when the config leaves the menu empty for a folder.

## I click an item and nothing happens

- `rh doctor` has a line "Last action started from Finder". If it says "none yet" after you clicked, the click did
  not reach `rh`: check the runner script line (`rh install --scripts`) and look at the extension's log:

  ```sh
  /usr/bin/log show --last 10m --predicate 'subsystem == "com.boyugou.righthere.FinderExtension"'
  ```

- `rh doctor --probe-extension` runs the whole chain a click uses, through the extension. It restarts the extension and may show
  a permission prompt.
- A failed action shows an alert and writes a line to `~/Library/Logs/right-here/rh.log`.
- Try the action from a terminal with `--dry-run` to see exactly what it would do: `rh run agent.claude --dry-run
  --container ~/code/project`.

## macOS asks whether Right Here may control the terminal

That is the Automation permission, and it is asked once per terminal. Choose Allow. It is the Finder extension
that asks, because it is the process macOS holds responsible for what `rh` does on its behalf. If you chose Don't
Allow, switch it on in System Settings, Privacy & Security, Automation, or reset the question:

```sh
tccutil reset AppleEvents com.boyugou.righthere.FinderExtension
```

## An action says macOS did not let Right Here look at a folder

Desktop, Documents, Downloads, iCloud Drive and some other folders are protected: a process needs your
permission to look inside them, and it is asked once. If the alert names a path in one of them, choose Allow when
macOS asks (the alert has a button for System Settings, Privacy & Security, Files & Folders; Full Disk Access also
works), then run the action again. Right Here stops there on purpose: it will not guess at what the path is, and a
terminal is never started in some other folder instead. Copying a path, revealing it and opening it in an editor
go ahead without it, because they only pass the path on.

## An action says a path does not exist

Every action checks the paths it is given, so a typo is reported and not quietly replaced by the folder around it.
Check the spelling; `rh run <action> --dry-run <path>` shows what would happen without doing it. A link that points
nowhere counts as existing.

## An agent says "not found", or starts without my aliases

The agent's command is typed into your own login shell, so it sees what a new terminal window sees: nvm, your
PATH and your aliases. If `agy`, `claude`, or `codex` works in a new window of your terminal it works here. `rh agents` shows which
agent commands your login shell finds. If your shell takes a few seconds to start, the agent starts that much
later; that is your shell's startup time, and `rh doctor --probe-launch` reports how long the round trip took.

## The check says `~/.local/bin` is not on PATH, and my terminal has it

A graphical app, and a program an AI assistant starts, gets the `PATH` that launchd gives it: macOS does not read your shell's
startup files for it, so it lacks the folders your `~/.zshrc` adds. Right Here does not trust that `PATH`. When the link `~/.local/bin/rh`
exists and the program's own `PATH` lacks its folder, it starts your login shell the way a new terminal window would (`-lic`, the shell macOS
has on record for you: `dscl . -read /Users/$USER UserShell`) and reads that shell's `PATH`. The row is ok when the folder is there, however it is
spelled (a trailing slash, a `.` part, a symbolic link on the way).

- It still warns: the shell it asked is not the one your terminal runs (a terminal's own shell or `command` setting, a profile with another
  shell), or your startup file adds the folder only in some cases. In the terminal you use, `command -v rh` should print
  `~/.local/bin/rh`; to see what Right Here saw, run your login shell the same way: `"$(dscl . -read /Users/$USER UserShell | awk '{print $2}')" -lic 'echo $PATH'`.
- The row says the login shell "did not say whether that folder is on PATH": the shell was started and gave no answer, because a startup file exits,
  waits for input or takes longer than ten seconds. That is unknown, not wrong, so nothing asks you to change a profile. Make the startup file finish quickly
  (move slow tools and prompts behind a check for an interactive terminal) and look again.

## Running an agent in an isolated git worktree

To start an agent on an isolated branch without dirtying your current branch or working tree, use:
`rh run agent.agy --worktree` or `rh run agent.claude --worktree --branch experiment-1`. Right Here makes a git worktree under
`.right-here/worktrees/` (on a new branch, or on the one `--branch` names), keeps `.right-here` out of `git status` through
`.git/info/exclude`, and starts the agent in the folder you named, inside that worktree. `--dry-run` shows the plan, with the
worktree's path, and makes nothing. A run that fails removes the worktree again when nothing in it changed; a request that is
refused creates nothing. `rh worktree list` and `rh worktree remove` manage them: remove refuses uncommitted work unless you
pass `--force`, and it only removes worktrees Right Here made.

## WezTerm or kitty launch questions

Right Here includes native adapters for WezTerm and kitty without requiring manual template configurations. It finds each
by its bundle identifier, wherever it is installed, and starts it through LaunchServices (`open -n -b`), so `rh run` does not
wait for the window to close. Their own command-line arguments (`start --cwd <folder>` for WezTerm, `--directory <folder>` for
kitty) carry the folder. Neither has been run on the development Mac: `rh doctor --probe-launch` is how to check yours.

## Terminal says it will not start a command in a folder

Terminal types `cd <folder>` into whichever shell its profile starts, and shells disagree about a backslash in a
name, so Terminal will not start an agent in a folder whose name has one (opening the folder alone works). Rename
the folder, or use Ghostty, which is handed the folder and types nothing.

## The agent opens in a window and I want a tab or split

Set `terminal_placement = "tab"` or `terminal_placement = "split-right"` (or `"split-down"`) under `[general]` (Ghostty and iTerm).

## Quick Actions are missing or out of date

`rh install --services` rewrites them from the config. The doctor says when they differ from it. Changing the
system language also changes their names, so run it again after that.

## The config has a mistake

`rh config validate --strict` lists every problem with the file and line it is on and a likely replacement for a typo.
A syntax error says what is wrong (an array that is not closed is reported at the line where it opened). Warnings are
worth fixing: an unknown key only warns because the rest of the file still applies, but what it was meant to set is missing.
With a `config.local.toml`, `validate` also reads `config.toml` on its own, because that is what other Macs read: an
error the overlay hides on this Mac is reported for `config.toml`. A key named like a credential (token, secret, password,
api_key) is an error in `config.toml`: `push` refuses it, and a synced config must not hold one.
A config file that is there but cannot be read (no permission, a folder in its place) is an error that names the file and
the reason, in `rh config validate`, `rh doctor` and `rh init`; it is never taken for a missing config.

A config with a syntax error does not stop `rh`, and it does not stay quiet about it either: each command prints the error on
standard error and uses the defaults for the whole file (`Defaults apply until it is fixed`). That includes `rh run`, which
then acts with the defaults: an action that names no terminal plans the default terminal, not the one you set (a dry run exits
with status 0). The Finder menu uses the defaults too, and it has no standard error to say so. `rh doctor` has a Config file row that fails
until the file is fixed, so look there first when the menu is not what you set.

## Sending a bug report

Run `rh doctor --report` and send its output as it is. It names the versions of rh, of Right Here.app and of macOS, the
processor, every doctor line and the counts of the config check. It holds no text of your config file, and the home folder
(shown as `~`) and the account name are removed from it. (The doctor lines can name an agent or an app you set up.)

## `rh config sync` will not pull or push

The message says why, and nothing was changed. The usual reasons:

- The copy would add or change a terminal template or an agent command. A synced folder can be written by other
  Macs and by sync services, and a config with a program in it runs when you click, so `pull` lists what would change
  and wants `rh config sync pull --allow-commands` once you have read it. `rh config sync status` shows the same list
  first. This is separate from `--force`; the two combine.
- This Mac's config changed since the last sync: `rh config sync status`, then `rh config sync push` to send it or
  `rh config sync pull --force` to replace it (the old file is saved first).
- The copy in the folder is not on this Mac yet (iCloud keeps it online only): open the folder in Finder and let it
  download.
- `push` says the folder cannot be created: it creates the last folder of the path only. Make the parent first (the
  message gives the `mkdir -p` for a folder under your home folder), or choose another folder with
  `rh config sync enable --folder <folder>`.
- `rh config sync status` ends with "fix this machine's config first" (or "the folder's copy"): `push` (or `pull`) would
  refuse that file, and `status` lists why above; `rh config validate` shows the same problems.
- The copy (or this Mac's config) is far larger than a config can be, over 1 MiB: it is not read, and nothing writes
  over it. `rh config sync status` gives its size; if it is the wrong folder or a file that was pasted over the config,
  move it out of the way, then `push` (or `pull`).

## Removing it

`rh uninstall` removes the runner script, Quick Actions, the command link (only when it points at Right Here's `rh`)
and the extension registration, and keeps your config. Then delete Right Here.app.
