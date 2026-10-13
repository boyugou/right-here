# 0009: Termius is not a built-in terminal

Date: 2026-10-12. Status: decided; revisit if Termius adds a way to start a local shell in a folder.

## Decision

Termius is not in the catalog of built-in terminals and gets no adapter.

## Why

Termius is an SSH and SFTP client. Checked on an installed copy (bundle `com.termius-dmg.mac`):

- Its only registered URL scheme is `termius://`, which addresses saved hosts and connections, not a local folder.
- The app bundle ships no command-line helper, and its only executable is the Electron main binary.
- Opening a folder with it through LaunchServices would at best bring the app forward; nothing in the bundle's
  metadata suggests it starts a local shell in that folder.

An adapter that cannot do what "Open in Termius" says would be worse than no entry. The checks above read
metadata only; no window was opened.

## If someone needs it

A terminal that can be started with a command line works today through a config-defined launcher (`[[app]]`
with `open_args` or `run_args`, see `rh docs config`). If Termius gains a documented local-shell entry point,
add it the same way and verify it on a machine that has it before shipping a built-in adapter.
