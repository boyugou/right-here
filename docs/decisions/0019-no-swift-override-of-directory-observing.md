# 0019: The Finder extension does not override the directory-observing methods

Date: 2026-10-15. Status: decided. Not yet verified in Finder: the Mac that showed the crash has only the Command Line Tools, so the extension could not be rebuilt there. Verify on the next build by right-clicking a folder on macOS 26.5 and checking that no new crash report appears.

## Decision

`FinderSyncExtension` does not override `beginObservingDirectory(at:)` or `endObservingDirectory(at:)`. The warm-up they once
started runs from `init` (ADR 0015), so the overrides had been reduced to a call of `super` and nothing else.

## Evidence

On macOS 26.5.1 (25F80), with the signed 0.2.0 release, the extension aborted every time Finder asked it to watch a directory,
which Finder does within seconds of the extension starting and again on each right-click in a new folder. Ten crash reports in one
afternoon (`~/Library/Logs/DiagnosticReports/FinderExtension-2026-10-15-*.ips`) have the same cause:

- `EXC_CRASH (SIGABRT)` after an uncaught `NSInvalidArgumentException` (HIServices logs it as a fault with a private message).
- The exception backtrace is `-[FIFinderSyncExtension startWatchingDirectoryURL:]` →
  `@objc FinderSyncExtension.beginObservingDirectory(at:)` → `_CF_forwarding_prep_0` → `___forwarding___` → throw. The Swift thunk
  that bridges the argument to `URL` is the only frame of ours; the receiver of the failing message forwards (an `NSProxy` kind of
  object), so what Finder hands over on this macOS is not a plain `NSURL` that bridges.
- Finder's own log at the same seconds: `extension connection was interrupted! ... com.boyugou.righthere.FinderExtension`, eight
  times in an hour.

The effect for the person: the extension logged `menu items: 1 items, served from cache` for a right-click, Finder tore the
connection down nine seconds later, and the context menu showed none of Right Here's entries, while `rh doctor` reported every check
ok (the extension is registered and switched on, and the launch probe, which does not touch directory watching, passed).

Without the override there is no Swift thunk on this path: `FIFinderSync`'s own Objective-C implementation receives the call. The
removed methods did nothing, so no behaviour of ours changes.

## The doctor looks at crash reports

The report also showed why the doctor stayed green: it asks `pluginkit` whether the extension is registered and switched on, and the
launch probe runs the chain a click uses, and neither does what Finder asks of an extension by itself (watching a folder). `rh doctor`
now reads the crash reports macOS keeps for the extension (`FinderExtension-*.ips` in `~/Library/Logs/DiagnosticReports`), counts those
written since the installed copy's code was written and within the last seven days, and turns the Finder extension row into a warning that
names the newest one. The row is English in every language (`doctor.verbatim`): a report is a file for a person to attach to a bug report, not a sentence
to translate. The window of the direct download shows it too; the Mac App Store edition's window is sandboxed, cannot read that folder
and leaves the row as it is.

## Alternatives

- Keep the override and guard the argument: not possible, the exception is thrown while bridging the argument, before any line of
  the method runs.
- Declare the override with an Objective-C type (`NSURL`): `FIFinderSync` is imported with `URL`, and nothing in the method would
  use the value anyway.
