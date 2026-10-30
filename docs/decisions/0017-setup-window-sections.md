# 0017: The setup window has six sections

Date: 2026-10-15. Status: decided.

## Decision

The setup window (`Apps/RightHere`) has six sections in its sidebar, in this order:

1. **Overview**: how the setup stands, and the default terminal and editor. While the Finder extension is off, the three-step
   first run (ADR 0011) comes first on this page.
2. **Finder menu**: the menu the extension builds for a folder, from the same code. Submenus open in place.
3. **Checks**: every check of the doctor, with what it found and what to do. Test Terminal Launch is here, and its answer
   stays in the list through refreshes until the next test.
4. **AI Assistants**: a prompt that has an AI assistant set Right Here up, the MCP configuration, and the commands that add the
   Claude Code plugin. The prompt is English on purpose: it is input for an AI assistant, as the command line and MCP output are.
5. **Worktrees**: the git worktrees of one repository. Only worktrees that Right Here made (under `.right-here/worktrees`) can be
   removed, after a confirmation and never with `--force`. Git's refusal (uncommitted work) is shown as git wrote it. The branch
   is kept; deleting it stays on the command line (`rh worktree remove --delete-branch`, which uses `git branch -d`).
6. **Folders**: the pinned and recent folders, with Unpin and Clear Recent Folders.

The Configuration section and the agent cards of the earlier window are gone. The config file is opened with Open Config in the
header; its problems are in Checks, and each agent's permission-prompt state is the sentence of its row in Checks (the doctor's
message, in thirty languages). `script/preview_setup.sh --tab` takes the six section names.

## Why

- The window is for setup and status: the Finder extension, `rh` and Shortcuts work without it. A configuration section showed a
  copy of the file; agent cards repeated the help text; the Quick Actions heading named a Finder feature the card did not explain.
- The repository for worktrees comes from the folder the person chose, or from the first pinned or recent folder that is in a
  repository. The app's own working folder is not used: a process started by launchd has `/` as its working directory and
  `/usr/bin:/bin:/usr/sbin:/sbin` as its PATH (measured on macOS on 2026-10-15 with a launchd job), so a list taken from it was
  always empty.
- Removal in the window is narrower than the command line: no `--force`, and no branch deletion. A person who misreads a dialog
  cannot lose uncommitted work through it.

## Alternatives

- Four tabs with a configuration tab (the earlier window): a copy of the file, and the status said twice.
- Removal with `--force` behind a confirmation: git's refusal is the protection a person can read; a confirmation is not one.
- The app's working folder for the repository: empty for an app started from the Dock or Finder (see above).

## Checked

- The sections were rendered headlessly with `script/preview_setup.sh` (ImageRenderer): every section in English, the first-run
  card and the folders, AI and worktrees sections in Arabic, Hebrew and Japanese, and the first-run card in German (the longest
  words), at the default width of 860 points and at the smallest width, 800 by 560 points. Each text wraps inside its panel; no
  text was cut in these renders.
- Large text: the same render with `dynamicTypeSize` set to accessibility 2 gave a picture identical to the one without it. On
  macOS the setting does not change this rendering, so large text is not claimed as checked.
- Tests in `RightHereKitTests`: `SetupSummaryTests`, `SetupLoaderTests`, `SetupActionsTests`, `SetupWorktreesTests` (against real
  git in a throwaway repository), `RefreshLoopTests`, `MenuSubmenuTests`, `PathDisplayTests`, `SetupSnippetsTests`, and the
  `WorktreeRows` and `WorktreeRepositories` suites. The window's refusal to remove a worktree Right Here did not make is a mutant
  in `script/mutation_check.py`.
- Not checked: the real window (the folder panel, the confirmation dialog, VoiceOver, and the sandboxed App Store build). The App
  Store app is sandboxed without the user-selected-files entitlement, so listing the worktrees, which runs `git` on the folder, is
  expected to fail there; this is an open item. A folder whose names are right to left is drawn with those
  names in reverse order in a right-to-left window: SwiftUI's text layout takes the direction of the window, and neither the
  isolate nor the left-to-right marks changed it (`MANUAL_CHECKS.md`, section 5).

## Amended by 0026 (2026-10-16)

A seventh section, **Config**, sits after Finder menu: the settings file as text, the changes an AI assistant proposed that wait for the person, and the latest changes with Undo. The Finder menu section gained its editor (Edit Menu). `script/preview_setup.sh --tab` takes `config` as well.

An eighth section, **Agents**, sits after Finder menu (2026-10-17): the agents the menu offers in order, with a check, a grip and the command that starts each, and the switch that starts agents without their permission
prompts (ADR 0026, stage 3b). The Overview's two cards for the default terminal and editor became menus. `script/preview_setup.sh --tab` takes `agents` as well.
