# Right Here: App Store metadata draft (English, US)

A draft for a possible App Store edition ([ADR 0007](../decisions/0007-app-store-edition.md), proposed). Nothing is published.

Limits are Apple's as of this draft; verify them in App Store Connect before submitting.

- Name (max 30): Right Here: Finder Menu   (alternatives: "Right Here")  [verify availability]
- Subtitle (max 30): Open folders where you work   (27 characters)
- Category: Utilities (primary). Secondary: Developer Tools.
- Promotional text (max 170, editable without a new build):
  A configurable Finder menu: open any folder or file in your terminal or editor, copy its path in the form you
  need, and keep it all in one plain-text file.   (about 150 characters)

## Description (max 4000)

Right Here adds one clean menu to Finder. Right-click a folder, a file, the folder background or the toolbar, and
send it where you work.

- Open the folder in your terminal or editor.
- Copy the path as POSIX, quoted for the shell, as a file URL, as a Markdown link and more.
- Show only what applies: the menu follows what is selected and what is installed.
- One plain-text configuration file decides what appears and in what order. Edit it in any editor.
- Private by design: no account, no analytics, no network. Right Here never sends anything anywhere.
- Open source under the Apache License 2.0.
- Available in 30 languages.

To turn it on: open Right Here, then enable the Finder extension in System Settings, General, Login Items &
Extensions, Added Extensions (Finder).

Note: this edition is the menu-only edition. Starting AI agents in a terminal, the `rh` command-line tool and the
MCP server are in the free direct download at https://github.com/boyugou/right-here.

## Keywords (max 100 characters, comma-separated, no spaces after commas)

finder,context menu,terminal,folder,path,copy path,developer,right click,editor,toolbar

(count: 87)

## What's New (version 1.0)

First release. A configurable Finder menu for opening folders and copying paths.

## URLs

- Support URL: https://github.com/boyugou/right-here/issues
- Marketing URL: https://boyugou.github.io/right-here/
- Privacy policy URL: https://boyugou.github.io/right-here/privacy.html (from PRIVACY.md)
- Copyright: Licensed under the Apache License 2.0.

## Review notes (draft)

Right Here is a Finder Sync extension plus a small setup window. To test: launch the app, then System Settings >
General > Login Items & Extensions > Added Extensions > enable "Right Here" under Finder. Open a Finder window and
right-click a folder or the window background; the "Right Here" items appear. Choose "Copy Path" and paste anywhere
to see the result. The app uses the App Sandbox, no temporary exceptions, no network and no accounts. It sends Apple events
only to the terminal the person chose, to open a window there (the `com.apple.security.automation.apple-events` entitlement and the
`NSAppleEventsUsageDescription` text); macOS asks once the first time.
