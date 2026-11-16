# 0028: The worktree browser keeps its repository and operation states clear

Date: 2026-11-15. Status: accepted.

## Problem

The repository menu only contained roots found in saved folders. A root chosen through the folder picker was not added, so the
window could show one repository while offering only others. Its fixed-width path competed with Choose Folder in one row.
Failed reads showed git's text without a recovery action, and a successful empty result showed nothing.

Switching repositories deferred clearing the old rows until a task ran. Removal read the current repository at confirmation time
instead of retaining the repository of the row being confirmed. Its controls became available before the final list refresh
completed. Choosing a repository through the picker also kept every operation disabled while git was merely reading its list.

## Decision

- The selector includes known roots and roots chosen during this window's lifetime, once each. Switching back does not forget a
  chosen root. These choices do not write pins or recent history, and they are not persisted between app launches.
- The repository name and abbreviated path have their own space below the controls. Long paths truncate in the middle and have
  a full-path tooltip. Menu choices show full paths and mark the selected repository. Refresh reads only the worktree list.
- Failed reads have a localized heading, git's original error and Try Again. Retrying reads the list; it never repeats a removal.
  No repository, loading, an empty successful read and a failed read remain distinct states. A slow list read still permits
  selecting another repository, including after the native folder picker returns.
- Switching immediately clears the old rows, including when refreshed folders change the default repository. A result is applied
  only when both its request number and repository still match.
  A removal confirmation captures the row and its repository together. The runtime still checks ownership and asks git to remove
  without force or branch deletion. Repository selection and repeated mutations stay disabled through removal's final read;
  background worktree reads cannot overwrite that operation's result.
- Rows expose Reveal in Finder through the existing folder action. Removal is offered only for the app's own worktrees. Branch
  and path remain separate from their display text; display-only escapes never enter a git or Finder argument.
- The shared folder chooser is a sheet attached to the app window. The standalone panel became inaccessible during native
  automation after the main window regained focus, leaving editing controls disabled. A sheet keeps the pending choice with
  its window; both pinning a folder and choosing a repository use it. A visible window that can become main is also considered
  when an accessibility action invokes the chooser while the app is inactive and neither key nor main window is available.
- The view moves to `SetupWorktrees.swift`. The window model receives a `WorktreeBrowser`, allowing tests to hold and reorder fake
  git replies without starting a real process. The app model tests share one temporary-home fixture instead of copying it.

## Alternatives

Persisting a second repository history would duplicate the saved folder state. This iteration remembers choices only for the
current window. Disabling repository selection for every read would avoid overlapping reads but make a slow or unavailable
repository harder to leave. Request numbers and a captured repository preserve responsiveness while rejecting stale results.
Automatically retrying a failed mutation would be surprising; the recovery button is confined to reading.

## Verification

`SetupModelWorktreeTests` covers remembered choices, deduplication, immediate row clearing after selection or a folders refresh,
out-of-order reads, retry, responsive selection while a picker-initiated read is pending, confirmation ownership, and controls
remaining disabled until the final refresh for both successful and refused removal. All process calls use fake runners. The
existing runtime tests still cover dirty-worktree refusal and keeping the branch in a throwaway repository.

The headless preview accepts `--worktrees-state failed`, `empty`, `loading`, `none` and `long`. These are canned states, including
multiple repository choices; no project from the machine is used. Long paths, error recovery and right-to-left layout were
rendered in English, Simplified Chinese, German and Arabic, including the minimum window and dark appearance.

Restoring the former choice retention, row-clearing, confirmation, picker-waiting and removal-refresh behaviors caused their
regression tests to fail. Separately restoring stale rows after a folders refresh failed that regression too. The corrected
tests passed with fake processes and temporary homes.

The final `script/verify_all.sh` passed: 1,716 tests, the release app and Finder extension build, thirty localizations, schema,
embedded documentation, documentation commands and links, mutation-entry consistency and public-safety checks. The runtime's
git and launch protections are unchanged.

Native interaction was checked on the machine reporting macOS 27.2 (26B123), with two throwaway repositories and a copy of the app
using a distinct bundle identifier, no embedded Finder extension, and a temporary `RH_HOME`. The copy also supplies that environment
through its `LSEnvironment`, so a UI automation relaunch stays isolated. The attached repository chooser opened from an accessibility
action in an inactive window; Escape restored the page. Choosing the second repository, switching back and reopening the menu kept
both choices and marked the selected one. Cancel kept a clean worktree; confirming removal removed its directory and retained its
branch. A changed worktree was refused and its untracked file remained byte-for-byte intact. Temporarily hiding only the fixture's
git metadata produced the failed card; restoring it and choosing Try Again brought the list back. The pin chooser also opened as a
sheet and Cancel restored its controls. Pins and recents stayed unchanged. The app, registration, preferences and fixtures were
removed afterwards. Spoken VoiceOver output remains a manual check; the accessibility tree alone does not verify it.
