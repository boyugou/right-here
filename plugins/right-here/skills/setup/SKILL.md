---
name: setup
description: Set up or repair Right Here, the Finder menu for terminals, editors and AI agents. Use when the user asks to configure Right Here, add an app or agent to the Finder menu, change which terminal opens, or when the Finder menu is missing or an action fails.
argument-hint: "[what to change]"
---

# Set up Right Here

What the user wants: $ARGUMENTS

Read the playbook first: `right_here_docs` with topic `agent-setup` (the same text as `rh docs agent-setup` in a shell). This is
its short form; the playbook has the details.

## 1. Ask first

Before anything changes, ask the user which terminal, editor and AI agents they use, in one message, and nothing else. If
`$ARGUMENTS` already says, use that. `right_here_catalog` lists the ids (`ghostty`, `terminal`, `vscode`, `zed`, `claude`,
`codex`, ...); an id is exact. "Whatever you find" is an answer: leave that flag out. No agent at all is `--agents none`.

## 2. Run setup once, in the shell

Setting up writes files in the user's home, so it is a shell command and not a tool:

    rh setup --json --terminal <id> --editor <id> --agents <id,id>

Leave out a flag the user did not answer. It makes the config only when there is none, installs what Finder needs, runs the
doctor, and opens no window. To add an agent to a config that exists, give the whole list of agents. If the report's
`configEdits` is not empty, the existing config was left alone: make exactly those edits to the file each names, keep every
comment and every other line, then check it with `right_here_config_validate` (`clean` must be true).

## 3. Tell the user what only they can do

Each `needsUser` entry has a `text` and `how`: give them to the user in your words, with the exact clicks (switching the Finder
extension on in System Settings, the PATH line, the permission macOS asks for once). Running setup again does not switch the
extension on, so never run it in a loop.

## 4. Check the result

`right_here_doctor`: no check has the status `fail`; say what a `warn` or `needs-user` says. `right_here_menu` with a folder
shows the user the menu their config makes. Do not run an action for real unless the user asked. The one thing worth offering when
they start agents in a terminal is `rh doctor --probe-launch` in the shell: it opens and closes a terminal window for a second and
macOS may ask for permission, so ask before you start it.

## Never

Change System Settings or the databases behind it; delete, replace or rewrite the user's config or its comments (`rh setup --force`
only when they asked to start over); edit their shell startup files unless they ask you to; put a secret in the config.
