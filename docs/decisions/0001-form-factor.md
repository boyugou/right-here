# 0001: A CLI core with an app bundle for Finder

Date: 2026-10-11. Status: accepted.

## Question

Should Right Here be an app, a Homebrew package, or both?

## Decision

`rh` (a command-line tool) is the core and does all the work. A small app bundle exists because a
Finder Sync extension has to live in one; the app also shows setup status. Distribution is Homebrew-
friendly: a cask for the app (the extension and `rh` inside, `rh` linked onto PATH) and a formula for
the CLI alone.

## Alternatives

- **App only.** Every action would live behind a resident app or a private IPC, and agents could not use
  it. Rejected.
- **Homebrew CLI plus Quick Actions only.** No signing and no extension, but Quick Actions show in a
  submenu and may not appear on a folder's empty background (not yet checked; DESIGN section 5), which is
  where copy path and new file are wanted. Kept as a second surface instead.
- **App Store only.** The sandbox forbids starting an agent in a terminal without user-installed scripts,
  writing files in arbitrary folders without grants, and shipping a CLI that works from a terminal
  (Apple Developer Forums 771117, 130092; guideline 2.4.5). A menu-only App Store build stays possible.

## Consequences

- Everything the menu does can be done and tested from the command line.
- A Homebrew formula cannot write `$HOME`, so `rh install` sets up the Finder side at runtime.
- The official cask repository requires Gatekeeper-passing casks, so the app is Developer ID signed and
  notarized.
