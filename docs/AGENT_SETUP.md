# Setting up Right Here for a person (for AI agents)

Goal: the person right-clicks a folder in Finder and sends it to their terminal, editor or AI agent. You do the setup. They do only
what macOS keeps for the person at the keyboard. Read this once, then follow it in order.

## 1. Ask first

Before anything changes, ask the person three questions, in one message, and wait for the answers:

1. Which terminal do you use? (`rh apps` lists the ones Right Here knows, with their ids. Terminal.app is always there.)
2. Which editor do you use?
3. Which AI agents do you use, if any? (`rh agents` lists the ones it knows.)

Ask nothing else: the rest has defaults. "Whatever you find" is a good answer; then leave that flag out and Right Here uses what
is installed. Turn their words into ids with `rh apps --json` and `rh agents --json`. An id is exact (`ghostty`, `vscode`,
`claude`, `codex`), and a misspelt one is refused with the closest id. If they use no agent, the answer is `--agents none`. If
they name an app that is not on this Mac yet, write it anyway: setup says it is not installed, and which app is used until it is.

## 2. Look before you change

`rh config path` says where the config file is. If a file is there it is the person's, and you will not rewrite it.
`rh setup --dry-run --json` (with the flags of step 3) shows what would be done and changes nothing.

## 3. Run setup once

    rh setup --json --terminal <id> --editor <id> --agents <id,id>

Leave out a flag the person did not answer. To add an agent to a config that exists, give the whole list: the agents already
enabled (`rh agents`) and the new one. Setup does everything in order and can be run again: the config file (created only when
there is none), the runner script and the command link that Finder needs, the Quick Actions and the Finder extension, then the
checks of `rh doctor`. It opens no window and never touches System Settings. Exit status 0 means no step failed.

## 4. Read the report

- `ok` is false when a step failed. `steps` says which (`outcome` is created, updated, unchanged, skipped or failed) and why. Read
  `rh docs troubleshooting`, fix the cause, and run setup again: it only does what is still missing.
- `configEdits` is not empty only when a config already existed and the person's choices differ from what it says. That config was
  not changed. Make exactly the listed edits, in the file each names, and nothing else: each has the `line`, the `current` value
  and the `value` to write. Keep every comment and every other line. Then run `rh config validate --strict` and fix what it says.
- `warnings` are for the person: say each one in a sentence.
- `needsUser` is what only the person can do (step 5). `checks` are the rows of `rh doctor --json`. `next` lists commands to run after.

## 5. Tell the person what only they can do

Give each `needsUser` entry's `text` and `how` in your own words, with the exact clicks, and say it is theirs to do. Do not do it
for them.

- `finderExtension`: switch on Right Here in System Settings › General › Login Items & Extensions › Finder. The Finder menu then
  appears within a few seconds. Running setup again does not switch it on.
- `path`: add the line `how` gives to their shell's startup file, and open a new terminal window. Do not edit the startup file
  yourself; if they ask you to, add that one line and nothing else.
- `automation`: the first time an agent starts in their terminal, macOS asks whether Right Here may control it. They click Allow.

## 6. Check the result

1. `rh doctor --json`: no check has the status `fail`. A `warn` or a `needs-user` is something to tell the person, not to fix by
   guessing. (The Finder extension row fails when Right Here.app is not installed. Then say so: the Finder menu needs the app, and
   Quick Actions work without it.)
2. `rh menu --container <a folder they use>` shows the menu. It must list their terminal, editor and agents; `rh menu --explain`
   says why an entry is missing.
3. Only if the person agrees (a terminal window opens and closes for a second, and macOS may ask for permission):
   `rh doctor --probe-launch`.

## 7. Never

- Never change System Settings or the databases behind it (`defaults`, `tccutil`, `sqlite3`, `pluginkit` by hand).
- Never delete, replace or rewrite the person's config or its comments. `rh setup --force` replaces the file (the old one is saved
  next to it): use it only when the person asked to start the config over.
- Never run `rh setup` or `rh install --finder` again, or in a loop, to make the extension switch on: it only registers it.
- Never put a secret in the config or in a command.
- Never run `rh doctor --probe-launch` or `--probe-extension` without asking, and never run `rh finder`.

## 8. When something fails

`rh docs troubleshooting` covers a menu that does not appear, a click that does nothing and the permission prompts. Each row of
`rh doctor` says what it found and what to do.

## 9. Hand back

Tell the person, in a few lines: what you set up (their terminal, editor and agents, and that Finder is connected); the one thing
left for them, if `needsUser` has an entry, with its clicks; any warning; and how to change it later, which is editing the config
file (`rh config path` says where; `rh docs config` lists every setting) or asking you. If the Finder menu does not show in a
folder inside iCloud Drive, say that right-click › Quick Actions works there.
