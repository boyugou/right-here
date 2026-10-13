# Manual checks

The automated suite, the mutation check and `rh doctor --probe-launch` cover everything that can be verified
without a screen or a person. These three need a real Finder, real terminals or a native speaker.

## 1. A real Finder click on protected folders

Folders under Desktop, Documents and Downloads are privacy-protected: the sandboxed extension may be refused a
look at them, and `rh` then treats the path as unreadable rather than as a folder (see
`docs/DESIGN.md`, section 9).

1. `rh install` and `rh doctor` (everything `[ok]`).
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
id = "kitty"
name = "kitty"
bundle_id = "net.kovidgoyal.kitty"
role = "terminal"
open_args = ["{app}/Contents/MacOS/kitty", "--directory", "{dir}"]
run_args = ["{app}/Contents/MacOS/kitty", "--directory", "{dir}", "{shell}", "-lic", "{command}; exec {shell} -l"]

[[app]]
id = "alacritty"
name = "Alacritty"
bundle_id = "org.alacritty"
role = "terminal"
open_args = ["{app}/Contents/MacOS/alacritty", "--working-directory", "{dir}"]
run_args = ["{app}/Contents/MacOS/alacritty", "--working-directory", "{dir}", "-e", "{shell}", "-lic", "{command}; exec {shell} -l"]
```

`rh config validate` warns that each entry replaces the built-in one; that is intended, the built-in entries only know how to open the app, not how to start a command. (WezTerm's entry is in `rh docs config`.) Check for each: the window opens in the folder, the command is typed
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
3. Select a folder and click Review: a failure alert should say to select files.
4. A file with a space and an apostrophe in its name should arrive as a single mention.
