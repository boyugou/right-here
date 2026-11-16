# 0037: Returning after a config edit updates the window

Date: 2026-11-15. Status: implemented. Extends [0036](0036-open-the-diagnosed-config-file.md).

## Problem

Returning to the setup window less than twenty seconds after its last full read skipped refreshing entirely. This avoids
restarting the person's login shell at every window switch, but also hid quick config edits: fixing an error and returning
could leave the error, the old default tool and the old menu preview on screen. Command-R worked, but the recovery flow
required the person to discover that extra step.

## Decision

Activation during the quiet period reads the two known config paths through the existing bounded config loader. A meaningful
change starts a full refresh immediately. Unchanged configuration and comment-only edits do not restart the doctor or the
login shell. After the quiet period, activation still performs the ordinary full refresh. A lightweight read does not reset
the time of the last full read, and this adds no background file polling.

The comparison uses the parsed settings, diagnostics, file-presence state and symbolic-link targets. It checks both paths,
including a local file that did not exist before. File modification dates alone would miss a replacement that preserves its
date. Config reads retain the existing size limit and rejection of pipes and other non-regular files.

The baseline is the config the snapshot actually consumed, captured before the doctor's asynchronous work. The loader also
reports that baseline at the start of an in-flight refresh. An activation that detects a change while the doctor is running
requests a follow-up through the existing RefreshLoop. Comparing only with the last displayed snapshot would miss a return
to those displayed settings while an intermediate, invalid version was still being checked. The refresh loop serializes
the reads and coalesces overlapping requests. Activation checks use a separate refresh loop too: returning again while a
lightweight check runs requests one subsequent check instead of discarding the newer activation.

The window stays on its selected section. Existing refresh feedback and disabled controls apply; there is no new toast,
page navigation, automatic repair or config rewrite. The initial load and operations started by the person retain their
existing guards.

## Alternatives

Removing the quiet period would repeatedly run shell startup files during ordinary window switching. Refreshing once after
Open Config would miss files edited independently or by an AI assistant. A persistent watcher would expand the lifecycle
and resource cost beyond this return-to-window problem. Comparing file dates is cheap, but is weaker than comparing the
small config state already understood by the loader.

## Verification

The first regression tests failed against the previous model: returning after a fast fix retained the config error, and
creating a local override retained the old terminal. Tests now cover both config layers, requesting preservation of the old
file date, adding and deleting an overlay, external creation and deletion of the main file, a comment-only edit, and a new
dangling overlay. They verify updated diagnostics, default tool, file choices and menu state, retained section selection,
and no extra process calls for an unchanged return.

Two additional regressions first failed during review: a second activation while a lightweight read was held lost the newer
edit, and replacing an ordinary file with an identical valid symlink failed to update its warning. Both now have coverage,
including restoring the symlink to a regular file.

A gated fake runner holds the doctor after it reads an invalid config. The test restores the previously displayed valid
config and activates the window while that read remains in flight. The final state must be valid, demonstrating that the
activation was not discarded and that the baseline came from the in-flight read. All file changes use temporary homes and
all process calls use fake runners.

A native-window review used a separately identified app, temporary home and a process runner that only recorded requests.
With a sixty-second quiet period, editing the local file and delivering an activation notification through a review-only
menu action cleared the visible error 14.6 seconds after the preceding full read, retained Checks, and issued exactly one
additional login-shell request. Repeating the notification without an edit issued none. The review app and data were removed.
Window-sharing interactions did not produce repeatable system activation transitions, so this verifies the notification
route and native UI update; ordinary switching from an external editor remains a manual check.
