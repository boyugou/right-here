# 0007: A Mac App Store edition, if any, is a reduced menu-only app

Date: 2026-10-12. Status: proposed (needs a one-day spike before any build work).

## Decision

Do not try to ship the full product through the Mac App Store. If an App Store edition is wanted, make it a
reduced "menu-only" app, built only after a spike (below) shows the sandbox allows what it needs. `rh`, the
config file, agent launching in a terminal, the MCP server and Quick Action generation stay in the direct
edition (notarized DMG, Homebrew).

## Why

Research sources: Apple documentation, App Review Guidelines, Developer Forums. Each
claim carries its source; items marked UNVERIFIED are inferences or could not be confirmed.

- **A Finder menu can be sandboxed.** Finder Sync is one of Apple's app extension points, and an app extension runs
  in the App Sandbox that guideline 2.4.5(i) asks of Mac App Store apps. How a sandboxed extension would open a
  terminal session without a folder entitlement is UNVERIFIED.
- **What review has refused.** Temporary exceptions on a FinderSync extension (UNVERIFIED: guideline 2.4.5(i) asks for an
  appropriate sandbox and does not name them),
  Apple-event exceptions for Terminal and Finder (developer.apple.com/forums/thread/663311), and an app that installed AppleScripts
  into Application Scripts for core functionality (2019, developer.apple.com/forums/thread/113216).
- **NSUserUnixTask is for scripts the user supplies.** A sandboxed app may read the folder but not write to it
  (developer.apple.com/documentation/foundation/nsuserunixtask); WWDC 2012 session 206 says built-in scripts are
  inappropriate; DTS says it is "not meant to be a generic sandbox bypass mechanism"
  (developer.apple.com/forums/thread/794326). A built-in runner script, which the direct edition relies on, is the
  shape that fails.
- **Entitlements.** `home-relative-path.read-only` needs written justification and is "typically" rejected
  (developer.apple.com/forums/thread/709333); `~/.config` is unreachable. Apple events need scripting-targets or an
  exception plus TCC, and DTS 2025 says controlling Terminal is not going to be accepted
  (developer.apple.com/forums/thread/794326). `NSAppleEventsUsageDescription` is required wherever Apple events are
  sent (the direct edition now carries it).
- **Opening a folder in another app from the sandbox is the open question.** NSWorkspace open can fail for a URL
  outside the sandbox (developer.apple.com/forums/thread/731972). Whether a URL handed to a
  FinderSync menu action carries a sandbox extension that LaunchServices honors is UNVERIFIED and decides the scope.
- **A bundled CLI** must itself be sandboxed (ITMS-90296), so `rh` could not be an unsandboxed binary on PATH; the
  tool would ship inside the bundle and the person would link it.

## What an edition could contain

| Feasible as is | With a setup step | Not feasible |
|---|---|---|
| Menu over user-chosen locations; string-only copy-path styles; settings in the container or an App Group; localization; agent start by URL scheme (UNVERIFIED) | Open in terminal or editor (depends on the spike, else a one-time folder grant); New File through a save panel; git-relative paths; app-declared Services as the Quick Action surface; optional user-attached scripts; the command link through a Privileged File Operations request | Typed agent launch in Terminal or Ghostty; an app-installed runner or `rh`; writing `~/.local/bin`, `~/Library/Services` or `~/Library/Application Scripts`; reading `~/.config`; a bundled MCP server |

## The spike (one day)

A sandboxed FinderSync extension with no exceptions: call `NSWorkspace.open` on the folder the menu hands it (Terminal,
Ghostty, VS Code; Desktop, Documents, elsewhere), open `claude-cli://`, and use `NSSavePanel`. If the folder opens,
the edition is viable as the first column; if not, only with a one-time folder grant. If review then rejects it, drop
the edition and file feedback.

## Checklist if it goes ahead

Apple Distribution certificate; explicit App IDs for the app and `<app id>.FinderExtension` with a Mac App Store
profile each; an App Group only if the two share settings or bookmarks (and this project already found the group
prefix rules sharp, see DESIGN section 5); App Store Connect record, privacy and age-rating answers, and review notes
that say how to enable the extension (General, Login Items & Extensions) and that no exceptions are used.
