# 0015: The Finder extension stays loaded, and does not keep the Mac awake

Date: 2026-10-14. Status: decided.

## Decision

The Finder extension asks the system not to terminate it while Finder runs (`disableAutomaticTermination`,
`disableSuddenTermination`) and holds one process activity with the option `.userInitiatedAllowingIdleSystemSleep`, so that App Nap does
not slow the first right-click after a pause. It does not use `.userInitiated` or `.latencyCritical`.

It also keeps the menus of folders it built (`MenuCachePolicy`): a menu is served from memory for 60 seconds, and only while the
config files are unchanged. The 60 seconds are shorter than the 300 seconds for which the facts (which apps are installed) are
remembered, so an installed or removed app shows up in the menu within about a minute.

## Evidence

Measured on macOS 26 with a small program that starts the activity and `pmset -g assertions` while it runs:

- `[.userInitiated, .latencyCritical]` creates a `PreventUserIdleSystemSleep` assertion named after the activity.
- `[.userInitiatedAllowingIdleSystemSleep]` creates none.

An extension that holds the first for as long as Finder runs, which is until the person logs out, would keep the Mac from going to sleep
when idle. A first version of the speed-up did exactly that.

## Alternatives

- No activity at all: App Nap can slow the extension after minutes of idleness; a right-click then waits.
- A menu cache that lives as long as the config does not change: it kept offering an uninstalled app for hours.
