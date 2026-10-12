# Checks that need a person at the machine

The automated suite, the mutation check and `rh doctor --probe-launch` cover everything that can be verified
without a screen or a person. These four cannot, and they are the open items before a public release.

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

Right Here has only tested these through fakes. Each snippet below is a starting point written from the
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

(WezTerm's entry is in `rh docs config`.) Check for each: the window opens in the folder, the command is typed
and runs, a folder named `it's a "test"` works, and closing the agent leaves a usable shell. Report what had to
change so the docs can carry a verified entry.

## 3. Translations

The thirty languages in `Localization/Localizable.xcstrings` were machine-translated. A native speaker should read
the menu titles and the alert texts of the setup window (`rh menu --language <tag>` prints the menu; the app's
window follows the system language). Right-to-left languages (ar, he, fa, ur) deserve a look in the real menu.

## 4. Making the repository public

The repository is private. Before changing that: read `docs/development/RELEASING.md`, decide on the release
channel (notarized DMG from the existing Developer ID, a Homebrew cask, or both), and confirm the
public-safety check passes on the full history (`script/verify_all.sh`).
