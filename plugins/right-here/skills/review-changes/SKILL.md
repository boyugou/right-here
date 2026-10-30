---
name: review-changes
description: Show the files you changed in Finder so the user can review them. Use after finishing a task that edited several files, or when the user asks to see what you changed.
argument-hint: "[folder or files]"
---

# Show what changed in Finder

Scope: $ARGUMENTS

## 1. Collect the files

- In a repository, `git status --porcelain -z` lists the changed and new files. Its names are separated by NUL and not quoted. (Plain
  `--porcelain` puts quotes around a name with a space or an accent, and the quotes are not part of the path.)
- Outside a repository, use the files that you edited in this conversation.
- Make each path absolute. Keep only what exists now: skip deleted files (status `D`), and for a rename (`R`) take the new name, the first
  of its two entries.
- Skip build output and ignored files. A path that does not exist makes the whole call fail.

## 2. Reveal them

Call `right_here_run` with `action` `reveal` and `paths`. Finder opens one window for each folder that holds a revealed item, and selects
the items in it. So the number of folders, not of files, decides how much of the screen it takes.

- Many files in a few folders: reveal them all in one call (at most 200 paths).
- Changes in more than about ten folders: reveal the few folders that contain them.
- Tool calls may open only about two dozen windows or files in a minute. If a call is refused for opening too much, do not try it again and
  do not split it to get round the limit. Reveal fewer, larger things, or ask the user.

## 3. Tell the user

List what you revealed, and say in one sentence what changed in each file.
