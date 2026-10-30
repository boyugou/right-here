# 0009: Termius is not a built-in terminal

Date: 2026-10-12. Status: decided; revisit if Termius adds a way to start a local shell in a folder.

## Decision

Termius is not in the catalog of built-in terminals and gets no adapter.

## Why

Termius is an SSH and SFTP client. Its URL scheme, `termius://`, addresses saved hosts and connections, not a
local folder, and it offers no command-line tool or other way to start a local shell in a given folder.

An adapter that cannot do what "Open in Termius" says would be worse than no entry.

## If someone needs it

A terminal that can be started with a command line works today through a config-defined launcher (`[[app]]`
with `open_args` or `run_args`, see `rh docs config`). If Termius gains a documented local-shell entry point,
add it the same way and verify it on a machine that has it before shipping a built-in adapter.
