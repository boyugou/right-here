---
name: review-changes
description: Show the files you changed in Finder so the user can review them. Use after finishing a task that edited several files, or when the user asks to see what you changed.
argument-hint: "[folder or files]"
---

# Show what changed in Finder

Scope: $ARGUMENTS

## 1. Collect the files

If a repository is involved, `git status --porcelain` lists changed and new files; otherwise use the files you
edited in this conversation. Resolve them to absolute paths. Skip build output and anything ignored.

## 2. Reveal them

`right_here_run` with `action` `reveal` and `paths`. Finder opens windows and selects the items. If there are
more than about twenty files, reveal the folders that contain them instead.

## 3. Tell the user

List what you revealed and what changed in each file, in a sentence each.
