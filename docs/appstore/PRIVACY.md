# Right Here privacy policy

Effective date: 2026-10-16

Right Here sends the folder you picked in Finder to a terminal, an editor or an AI agent on your Mac. It works
on your Mac and makes no network connections of its own.

## What Right Here collects

Nothing. Right Here has no accounts, no analytics, no advertising, no crash reporting and no tracking. It makes no
network connections, and it does not contain any code that could. The developer receives no data from the app.

## What Right Here reads on your Mac

- The paths of the files and folders you select or right-click in Finder: when you choose a menu item, to hand them to
  the app you chose (for example a terminal or an editor), and when you or an AI assistant you connected ask what is
  selected (`rh finder`, the `right_here_finder_selection` tool).
- Its own settings file, a plain-text configuration that you can read and edit.
- Which of the supported apps are installed, and which agent commands your login shell finds (Right Here starts that
  shell the way a new terminal window does), to show only the menu items that can work. `rh doctor` also looks in the
  folder of crash reports for those of Right Here's own Finder extension.

Right Here does not read the contents of your files.

## What Right Here stores

- The settings file, and an optional per-machine overlay file beside it, on your Mac.
- If you turn on `rh config sync`, a copy of the settings file in the folder you choose (iCloud Drive by default), a
  small state file that records the last synced copy, and backup copies of a settings file that a sync replaced.
  Right Here itself sends nothing over the network: whatever syncs that folder (iCloud Drive, Dropbox and so on)
  handles the copy under its own privacy practices. Sync is off until you enable it.
- The folders you pinned with `rh pin`, and the folders of the actions you started most recently (up to 20, from Finder, the command
  line or Shortcuts), in a small file `state.toml` next to the settings file. Only your user account can read it. The Folders section
  of the setup window lists them. An AI assistant that you connect to Right Here over MCP can read them with the
  `right_here_bookmarks` tool, and what that assistant reads is handled under its own privacy practices. `rh unpin <folder>`
  removes a pin, and `rh recents --clear` empties the recent list (the Folders section does both). Config sync does not copy
  this file.
- A small local log of recent actions and failures at `~/Library/Logs/right-here/rh.log`. It stays on your Mac, is
  never sent anywhere, and you can delete it at any time. Its size is limited and old entries are rotated out.

## Apple events

To open a window in your terminal or to start a command you chose, Right Here sends Apple events to that terminal,
and to Finder when you or an AI assistant ask what is selected. macOS asks for your permission the first time, and
you can withdraw it in System Settings, Privacy & Security, Automation.

## Other apps you choose

When Right Here opens a folder in another app or starts an AI agent, that app or agent has its own privacy
practices. Right Here does not control them.

## Children

Right Here collects no personal information from anyone, including children.

## Open source

The source code is under the Apache License 2.0, so these statements can be checked in it:
https://github.com/boyugou/right-here

## Changes and contact

If this policy changes, the new version and its date appear on this page. Questions: open an issue at
https://github.com/boyugou/right-here/issues.
