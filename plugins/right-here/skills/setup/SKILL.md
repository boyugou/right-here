---
name: setup
description: Set up or repair Right Here, the Finder menu for terminals, editors and AI agents. Use when the user asks to configure Right Here, add an app or agent to the Finder menu, change which terminal opens, or when the Finder menu is missing or an action fails.
argument-hint: "[what to change]"
---

# Set up Right Here

What the user wants: $ARGUMENTS

If that is empty, check the setup and fix what is broken.

## 1. Read the playbook and check the machine

Call `right_here_docs` with topic `agent-setup`, then `right_here_doctor`. If the menu is missing or a click does
nothing, read topic `troubleshooting` before guessing.

- `fail`: fix it with the `fix` text. Most fixes are `rh` commands; run them in the shell.
- `needs-user`: only the person can do this (for example, switching on the Finder extension in
  System Settings). Tell them exactly the step and wait.
- `warn`: mention it; fix it if it relates to the request.

## 2. Change the config

The config is TOML. `right_here_config_validate` returns its path in `file`. Read it, make the smallest
edit that does what the user asked, and keep their comments. Look up keys with `right_here_docs` topic
`config`; list known terminals, editors and agents with `right_here_catalog`.

## 3. Check your work

1. `right_here_config_validate`. Fix every error and every warning (`clean` must be true): an unknown key
   is only a warning, but it is almost always a typo and what it was meant to set is silently missing.
   Each diagnostic's `replacement` is the likely fix.
2. `right_here_menu` with a folder path, to show the user the menu their config now produces.
3. For an action you changed, `right_here_run` with `dry_run` to show what it will do.

Do not run an action for real unless the user asked for it. The one exception worth offering when the
user starts agents in a terminal: `rh doctor --probe-launch` in the shell. It opens and closes a terminal
window for a second and proves that the Finder click chain can run a typed command; the first run makes
macOS ask the user to allow Right Here to control the terminal, so ask before you start it.
