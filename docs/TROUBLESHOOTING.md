# Troubleshooting

Start with `rh doctor`. Each check says what is wrong and what to do.

- `rh doctor --json` gives the same checks to scripts and AI agents.
- `rh doctor --probe-launch` tests the whole path of a click. It opens a terminal window and closes it again.

## The window says to move Right Here to your Applications folder

**Why:** the app runs from the disk image, from another volume (a USB stick, a network share), or from the temporary copy that macOS
makes of a downloaded app. Setup writes files that point to the app: the runner script, the `rh` link and the Quick Actions. They stop
working when that place goes away. So **Set Up** and **Install or Repair** wait, and `rh setup` refuses.

**Fix:**

1. Drag Right Here.app into your Applications folder.
2. Eject the disk image.
3. Open Right Here from Applications.

An `rh` that is not inside an app (from Homebrew, or one that you built) does not get this check.

## The Finder menu does not show

Find the line of `rh doctor` that matches what you see:

- **The extension is switched off or not registered.** Run `rh install --finder`. Or turn on Right Here in System Settings, General,
  Login Items & Extensions, Finder. The setup window has a button that opens this page.
- **"Not registered" right after an update, and `rh setup` does not change it.** Two copies of Right Here.app are on the Mac, and macOS
  then registers neither. This happens when Finder's **Keep Both** made a copy, or when you renamed an old copy.
  1. List the copies: `mdfind 'kMDItemCFBundleIdentifier == "com.boyugou.righthere"'`.
  2. Move every copy except the one in Applications to the Trash.
  3. Run `rh setup` again.
- **"This build of it crashed N times in the last week".** macOS keeps a report of each crash in
  `~/Library/Logs/DiagnosticReports/FinderExtension-<date>.ips`. A crashing extension leaves the Finder menu without Right Here's lines.
  An early version crashed in this way on macOS 26.5.1 (ADR 0019). Install the current release and look again. If the warning stays,
  attach the newest report to a bug report.
- **The folder is inside iCloud Drive.** This includes a Desktop or Documents folder that syncs with iCloud. Finder shows no extension
  menus there. Use the Quick Actions: right-click, then **Quick Actions**. You can give them keyboard shortcuts in System Settings,
  Keyboard, Keyboard Shortcuts, Services.
- **The extension is registered from more than one place**, for example a build folder next to the installed app. Run
  `rh install --finder`. It removes the old copies. macOS drops an extension that is registered twice.
- **It worked until a macOS update, or until you replaced the app.** Run `rh setup`, or `rh install --finder`. This registers the
  extension again.
- **You turned the extension on, and the menu still does not show.** Restart Finder with `killall Finder`. Finder opens its windows
  again.
- **You run Right Here from a disk image or from Downloads.** The registration names the path of the app. When you eject the image or
  move the app, that path is gone. Move Right Here.app to Applications and run `rh install --finder` from there.

## `rh setup` fails on my config file

`rh setup` never rewrites a config file. If the file is there but cannot be used, the config step fails. It names the file and the line.

**Why:** one of these:

- The text is not TOML. For example, a table header is not closed, or a value is not in quotes.
- The file cannot be read: no permission, too large, or not UTF-8.
- `config.toml` or `config.local.toml` is a link to a file that is not there. A dotfiles manager makes such a link before you clone its
  repository.

The other steps still run, but no Quick Actions are made from the file. The exit status is 1.

**Fix:** correct the line (`rh config validate` says what is wrong), or restore the file that the link points to. Then run `rh setup`
again. To start the config again, run `rh setup --force`. It saves the old file next to the new one.

## `rh setup` says another setup is running

Setups take turns. This keeps the setup window, `rh setup` in a terminal and an AI agent's setup from undoing each other's Quick Actions.

- A second setup waits for the first one. After two minutes it stops with this message.
- Wait for the other setup to finish (the setup window shows its progress), or stop it. Then run `rh setup` again.
- The lock is `.setup.lock` in the config folder. It is released when its holder ends, so there is nothing to delete.

## An entry is missing from the menu

Run `rh menu --container <folder> --explain`. It prints the menu, and then each entry that it leaves out or changes, with the reason.
For example:

- An app is not installed.
- The Agent Presets need one or more selected files. A selected folder is not a file.
- This Mac's own file, `config.local.toml`, turns an agent off.
- The default terminal or editor is not installed on this Mac. The first installed one is used instead, so "Open in …" still shows,
  with another name.

`rh doctor` has a "Finder menu" row for a menu that would be empty, and `rh config validate` warns about it.

## I click an item and nothing happens

1. Look at the line "Last action started from Finder" of `rh doctor`. If it says "none yet" after your click, the click did not reach
   `rh`. Check the runner script with `rh install --scripts`.
2. Read the log of the extension:

   ```sh
   /usr/bin/log show --last 10m --predicate 'subsystem == "com.boyugou.righthere.FinderExtension"'
   ```

3. Run `rh doctor --probe-extension`. It runs the whole path of a click through the extension. It restarts the extension, and macOS
   may ask for a permission.
4. Run the action from a terminal with `--dry-run` to see what it would do:
   `rh run agent.claude --dry-run --container ~/code/project`.

A failed action shows an alert and writes a line to `~/Library/Logs/right-here/rh.log`.

## macOS asks whether Right Here may control the terminal

This is the Automation permission. macOS asks it once for each terminal. Choose **Allow**.

The Finder extension asks, because macOS holds it responsible for what `rh` does for it. If you chose **Don't Allow**, turn it on in
System Settings, Privacy & Security, Automation. Or reset the question:

```sh
tccutil reset AppleEvents com.boyugou.righthere.FinderExtension
```

## An action says macOS did not let Right Here look at a folder

Desktop, Documents, Downloads, iCloud Drive and some other folders are protected. A process needs your permission to look inside them.

1. Run the action again, and choose **Allow** when macOS asks. The alert has a button for System Settings, Privacy & Security, Files &
   Folders. Full Disk Access also works.
2. Right Here stops on purpose. It does not guess the path, and it never starts a terminal in another folder.

Copy Path, Show in Finder and Open in an editor work without this permission, because they only pass the path on.

## An action says a path does not exist

Each action checks the paths that it gets, so Right Here reports a typo. It does not use the folder around the path instead. Check the
spelling. `rh run <action> --dry-run <path>` shows what would happen. A link that points nowhere counts as a path that exists.

## An agent says "not found", or starts without my aliases

Right Here types the agent's command into your own login shell. So the agent sees what a new terminal window sees: nvm, your `PATH`
and your aliases. If `claude` works in a new window of your terminal, it works from the Finder menu too.

- `rh agents` shows which agent commands your login shell finds.
- If your shell starts slowly, the agent starts later by the same time. `rh doctor --probe-launch` says how long it took.
- **"Your login shell did not say whether it is installed".** Right Here started your shell as a new terminal window starts it, and the
  shell did not finish its answer. A startup file can cause this when it exits (for example `exec tmux` or `exec zellij` for each
  interactive shell), waits for input, or takes longer than ten seconds. Start the multiplexer only when a terminal is attached
  (`[[ -t 0 ]]`, and not inside it already). Or move slow steps behind such a check. Then look again.
- **The first run says "Your login shell did not say which AI agents are installed, so none is checked".** The cause is the same.
  Check the agents that you use before you press **Set Up**, or run `rh agents` after you make the startup file faster.

## The check says `~/.local/bin` is not on PATH, but my terminal has it

An app, and a program that an AI assistant starts, gets the `PATH` of launchd. macOS does not read your shell's startup files for it.
So Right Here does not trust that `PATH`. It starts your login shell as a new terminal window would (`-lic`), and reads that `PATH`.

- **It still warns.** The shell that Right Here asked may not be the shell of your terminal (a terminal's own shell setting, or a
  profile with another shell). Or your startup file adds the folder only in some cases.
  1. In your terminal, `command -v rh` must print `~/.local/bin/rh`.
  2. To see what Right Here saw, run:
     `"$(dscl . -read /Users/$USER UserShell | awk '{print $2}')" -lic 'echo $PATH'`.
- **"Did not say whether that folder is on PATH".** The shell gave no answer. A startup file exits, waits for input or takes longer than
  ten seconds. This is unknown, not wrong. Make the startup file finish quickly, then look again.

## Run an agent in a separate git worktree

To keep an agent away from your branch and your working copy, run it in a worktree:

```sh
rh run agent.claude --worktree
rh run agent.claude --worktree --branch experiment-1
```

- Right Here makes a git worktree under `.right-here/worktrees/`, on a new branch or on the branch that `--branch` names.
- It adds `.right-here` to `.git/info/exclude`, so `git status` does not show it.
- `--dry-run` shows the plan and the path of the worktree, and makes nothing.
- If the run fails and nothing in the worktree changed, Right Here removes it again.
- `rh worktree list` lists the worktrees. `rh worktree remove` removes one. It refuses work that is not committed, unless you add
  `--force`. It removes only worktrees that Right Here made.

A repository can be another person's code. So for these commands, git runs with the repository's own hooks, filters and file-system
monitor turned off, and fetches nothing. Your own git configuration still applies. Git LFS that you set up for your account
(`git lfs install`) works.

## An action says git is not installed

The worktree actions and the repository links need git. macOS has it only with Xcode or the Command Line Tools: run
`xcode-select --install` in Terminal, wait for the installation to finish, then try again. Right Here looks for git before it starts
it, so a click never ends in macOS's window that offers the tools.

## WezTerm, kitty or Alacritty

Right Here has built-in adapters for WezTerm, kitty and Alacritty. You do not need a template for them.

- Right Here finds each one by its bundle identifier and starts it with `open -n -b`.
- Each one gets the folder through the flag that its own documentation gives (ADR 0025).
- These terminals were not tried on a real Mac yet. `rh doctor --probe-launch` tests yours.
- If Homebrew does not install Alacritty, install it from its releases page. If macOS does not open it, Gatekeeper has not
  accepted the download.

## Terminal says it will not start a command in a folder

Terminal types `cd <folder>` into the shell of its profile, and shells read a backslash differently. So Right Here does not start an
agent in Terminal in a folder whose name has a backslash. Opening the folder works. Rename the folder, or use Ghostty, which gets the
folder and types nothing.

## The agent opens in a window, and I want a tab or a split

Set `terminal_placement = "tab"`, `"split-right"` or `"split-down"` under `[general]`. This works with Ghostty and iTerm. Warp opens
a tab, and a window for a split; it cannot start agents.

## Quick Actions are missing or out of date

Run `rh install --services`, or press Install or Repair in the setup window. It writes the Quick Actions again from the config. The doctor
says when they differ from the config. A change made in the setup window updates them at once; after a change in the config file, with
`rh config`, or of the language (`general.language`, or the system's when that is not set), run it again.

## The config has a mistake

Run `rh config validate --strict`. It lists each problem with its file and line, and suggests a replacement for a typo.

- A syntax error says what is wrong. An array that is not closed is reported at the line where it opens.
- An unknown key is only a warning, because the rest of the file still applies. But the setting that you meant is missing.
- With a `config.local.toml`, `validate` also reads `config.toml` alone, because the other Macs read it alone.
- A key with a name like a credential (token, secret, password, api_key) is an error in `config.toml`. A synced config must not have
  one.

**A syntax error does not stop `rh`.** Each command prints the error and uses the defaults for the whole file. `rh run` then uses the
defaults too: an action plans the default terminal, not the one that you set. The Finder menu uses the defaults as well, without a
message. `rh doctor` has a "Config file" row that fails until you fix the file. Look there first when the menu is not what you set.

## Send a bug report

Run `rh doctor --report` and send its output as it is. It names the versions of `rh`, the app and macOS, the processor, and each
doctor line. It leaves out what your config says (names, commands, the sync folder, the text of an error), your home folder and your
account name.

Do not post `rh doctor --json` in a public issue. It has those names, commands and paths.

## `rh config sync` does not pull or push

The message says why. Nothing was changed. The usual reasons:

- **The copy would add or change a program**: a terminal template, an agent command, the flag that skips an agent's permission prompts,
  or an agent that it puts in the menu while the prompts are off. Other Macs and sync services can write the sync folder, so `pull`
  lists these changes. Read the list, then run `rh config sync pull --allow-commands`. `rh config sync status` shows the same list
  first.
- **This Mac's config changed since the last sync.** Run `rh config sync status`. Then run `rh config sync push` to send it, or
  `rh config sync pull --force` to replace it. Right Here saves the old file first.
- **The copy is not on this Mac yet**, because iCloud keeps it online only. Open the folder in Finder and let it download.
- **`push` cannot make the folder.** It makes only the last folder of the path. Make the parent first (the message gives the
  `mkdir -p` command), or choose another folder with `rh config sync enable --folder <folder>`.
- **Another Right Here process is changing the config.** A pull waits up to five seconds for an edit to finish. Try again in a moment.
- **The file is larger than 1 MiB.** Right Here does not read it and never writes over it. `rh config sync status` gives its size.
  Move the file away if it is in the wrong folder, then push or pull.

## Remove Right Here

Run `rh uninstall`. It removes the runner script, the Quick Actions, the command link and the registration of the extension. It keeps
your config file. Then delete Right Here.app.
