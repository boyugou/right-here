---
name: review-changes
description: Show the files you changed in Finder so the user can review them. Use after finishing a task that edited several files, or when the user asks to see what you changed.
argument-hint: "[folder or files]"
---

# Show what changed in Finder

Scope: $ARGUMENTS

## 1. Collect the files

If a repository is involved, `git status --porcelain -z` lists changed and new files (NUL-separated and unquoted; plain `--porcelain` puts quotes
around a name with a space or an accent, and those quotes are not part of the path); otherwise use the files you
edited in this conversation. Resolve them to absolute paths and keep only what exists now: skip deleted files
(status `D`), and for a rename (`R`) take the new name, the first of its two entries. Skip build output and anything ignored. A
path that does not exist makes the whole call fail.

## 2. Reveal them

`right_here_run` with `action` `reveal` and `paths`. Finder opens one window per folder that holds a revealed
item and selects the items in it, so what costs the person's screen is the number of folders, not files.

- Many files in a few folders: reveal them all in one call (at most 200 paths).
- Changes spread over more than about ten folders: reveal the few folders that contain them instead.
- Tool calls may open only about two dozen windows or files a minute. If a call is refused for opening too
  much, do not retry it or split it to get round the limit: reveal fewer, larger things, or ask the person.

## 3. Tell the user

List what you revealed and what changed in each file, in a sentence each.
