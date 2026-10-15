# Manual checks

The automated suite, the mutation check and `rh doctor --probe-launch` cover everything that can be verified
without a screen or a person. These need a real Finder, real terminals or a native speaker.

## 1. A real Finder click on protected folders

Folders under Desktop, Documents and Downloads are privacy-protected: the sandboxed extension may be refused a
look at them, and `rh` then treats the path as unreadable rather than as a folder (see
`docs/DESIGN.md`, section 9).

1. `rh setup` and `rh doctor` (everything `[ok]`).
2. In Finder, right-click a folder inside Documents, then each of Desktop and Downloads. The Right Here menu
   should appear and "Open in <terminal>" should open a window in that folder.
3. Right-click a file there and choose a path-copy item; paste it somewhere and compare.
4. `rh doctor` again: "Last action started from Finder" shows the time.

If a protected folder does not work, run `rh doctor --json` and the log shown in `docs/TROUBLESHOOTING.md`, and
record the result in a decision record.

## 2. Terminals without a built-in adapter

These terminals are not yet tested with Right Here beyond fakes. Each snippet below is a starting point written from the
terminal's documented command line, not a verified one. Add it to the config, then:

```sh
rh config validate
rh run agent.claude@<id> --dry-run     # look at the argument vector
rh run agent.claude@<id>               # then for real, in a throwaway folder
```

```toml
[[app]]
id = "alacritty"
name = "Alacritty"
bundle_id = "org.alacritty"
role = "terminal"
open_args = ["/usr/bin/open", "-n", "-b", "org.alacritty", "--args", "--working-directory", "{dir}"]
run_args = ["/usr/bin/open", "-n", "-b", "org.alacritty", "--args", "--working-directory", "{dir}", "-e", "{shell}", "-lic", "{command}; exec {shell} -l"]
```

`rh config validate` warns that each entry replaces the built-in one; that is intended, the built-in entries only know how to open the app, not how to start a command. (WezTerm and kitty are built in: check them with `rh doctor --probe-launch` and by hand as below.) Check for each: the window opens in the folder, the command is typed
and runs, a folder named `it's a "test"` works, and closing the agent leaves a usable shell. Report what had to
change so the docs can carry a verified entry.

## 3. Translations

The thirty languages in `Localization/Localizable.xcstrings` were machine-translated. A native speaker should read
the menu titles and the alert texts of the setup window (`rh menu --language <tag>` prints the menu; the app's
window follows the system language). Right-to-left languages (ar, he, fa, ur) deserve a look in the real menu.

The window's list of checks writes every sentence of the doctor in the system language.
`./script/preview_setup.sh out.png <code> --gallery` renders each of them in a language to a tall picture; it found text
that did not fit and, in right-to-left languages, paths and commands that the sentence around them reordered (a value is
put in a Unicode isolate now, and a command that ends in a bracket carries a left-to-right mark). That is `ImageRenderer`,
not a real window. In the real one, in Arabic or Hebrew, with a state that has a path in it (a config that does not exist
yet is enough), look at the order of the path, and select a command in a fix line, paste it into a terminal and see that no
invisible character came with it. The relative time of the last action ("5 minutes ago") is formatted when the doctor
runs, in the locale of the process.

## 4. Agent prompt presets (0012)

Needs a real Finder and a terminal that can run commands; nothing here is covered by the tests, which only plan.

1. Select two files in a project folder, right-click, open More Agent Options, then Agent Presets. The nested
   submenu should show Review, Explain and Write Tests, and clicking Review should open a terminal in the folder and
   start the agent with the prompt already sent, naming both files as `@` mentions.
2. Right-click the empty background of a folder window: the Agent Presets submenu should be missing (the built-ins
   all name files).
3. Select a folder (and a second one): the Agent Presets submenu should be missing, since a preset that names files has nothing to name. This is the one place the menu asks the file system about the selection, from the sandboxed extension, and it was not seen there: if the submenu still shows for a folder, the extension could not tell it is a folder; clicking Review then fails with an alert that says to select files. Record which in the decision record. A folder and a file together keep the submenu.
4. A file with a space and an apostrophe in its name should arrive as a single mention.

## 5. The menu preview in the setup window

Needs a real Finder and the real app window: the tests and `script/preview_setup.sh` render the view, but they never
open one, and the preview is the same code as the extension's, not Finder's own word.

1. `rh setup`, switch the Finder extension on, and relaunch Finder (hold Option, right-click the Finder icon in the
   Dock, choose Relaunch). Open Right Here and choose "Finder menu" in its sidebar.
2. Right-click the empty background of a folder window. The entries, their order, the separators, the icons (the
   menu's own glyphs and the apps' icons) and the titles match the window's list. Click a line with a chevron in the
   window: its entries open in place, indented, and the chevron turns down; open the same submenu in Finder and compare
   its entries and separators. Clicking an entry in the window does nothing.
3. Change `[menu] items`, or enable another agent, then choose Install or Repair and relaunch Finder: the window and
   the Finder menu both follow the config. An app that is not installed is missing from both.
4. Put a syntax error in the config and choose Install or Repair: the "Finder menu" section says there is no menu to show, and
   the config row under Checks says why; fix the file and the menu comes back.
5. In Arabic or Hebrew (System Settings, General, Language & Region; restart the app) the lines mirror: icons on the
   right, the chevron on the left and pointing left. In dark mode the glyphs are light and an app's icon keeps its
   colors.
6. With VoiceOver, a submenu line reads like "Open With, submenu, collapsed, button" and says "expanded" once opened; an
   entry reads its title only.
7. Overview is the first section. While the Finder extension is off it shows the three-step first-run card first; once the
   extension is on it shows the status and the default terminal and editor. "Finder menu" is always the menu for a folder.
8. Worktrees: the list is for the repository of the folder you chose with "Choose Folder…", or else the first repository of your
   pinned and recent folders (the app has no folder of its own to start from). Right Here's worktrees (under
   `.right-here/worktrees`) have a Remove… button, which asks first and never forces: a worktree with uncommitted work stays,
   and the window shows what git said. The branch is kept. The main working copy and the worktrees you made by hand have no button.
9. Folders: Unpin and Clear Recent Folders change `state.toml`; `rh pins` and `rh recents` show the same lists afterwards.
10. In Arabic or Hebrew, with a pinned folder whose names are right to left (for example a folder called مستندات): the Folders and
    Worktrees rows draw the names in reverse order in the preview (`script/preview_setup.sh --demo --tab folders ar`), and the
    left-to-right marks that are added did not change that. Look at the real window: if the names read in order there, the limit
    is the preview's; if not, the path rows need another way to be drawn, and this check says so in the decision record.
