# 0030: A failed saved-folder read never becomes an empty list

Date: 2026-11-15. Status: accepted.

## Problem

`StateStore.load` treated absent, unreadable, oversized and malformed files alike. Folders appeared empty in the app, CLI and
MCP. The next pin or recent-folder update then replaced the original file with a fresh list. A regression test reproduced lost
bytes for malformed TOML, invalid UTF-8, a list with the wrong type and a file larger than the read limit. All four failed on
the previous implementation. Saving also had no corresponding size limit, so a successful update could become unreadable.

## Decision

- Only an absent state file means an empty store. Empty files and omitted optional lists remain valid. Invalid TOML, wrong list
  or element types, unknown fields and excessive nesting report an error. Absolute-path normalization, deduplication and the
  twenty-recent-folder cap retain their existing behavior.
- Reads throw a structured error. Locked updates must finish reading before calling the mutation; failures preserve the file.
  Writes enforce the same inclusive 128 KiB UTF-8 limit as reads, before the atomic replacement. CLI and MCP report failures;
  recording a recent folder remains best effort and does not prevent an otherwise successful launch.
- State reads use the existing `BoundedRead`: file size is checked before reading, the read itself is capped, and named pipes or
  other non-regular files cannot block waiting for a writer. The same reader already serves configuration files.
- A missing-file read error is checked with `lstat`: a dangling symlink is an existing entry, and must not be replaced as though
  no state existed. A local temporary-directory measurement confirmed that absent paths and dangling links both give ENOENT
  on read, but only absent paths give ENOENT on `lstat`; a directory gives a separate read error.
- The app distinguishes a failed snapshot from an empty one. Its failure panel names the file and error, says the file was not
  changed, and offers Try Again and Reveal in Finder. Editing controls are absent during failure; the runtime protects stale
  actions too. Reveal uses `open -R` with a separate path argument. Retry reads only folders and holds the operation guard
  through completion. No automatic reset, repair or deletion is offered.
- Long error text scrolls within 180 points so recovery actions remain visible; the complete message is exposed to accessibility.
- The failure heading and recovery text are in the thirty-language catalog. Parser and filesystem details remain in their
  own wording. Display paths abbreviate the home; untrusted control characters are escaped.

## Alternatives

Silently starting again would conceal and compound the original failure. Automatically backing up and resetting would preserve
bytes but still discard the person's active lists without their choice. A permissive read API alongside a strict update API would
keep the misleading empty UI and make accidental use of the permissive API possible. The same throwing read serves all callers.

## Verification

Core and runtime tests cover malformed documents, list shapes, unknown keys, nesting, missing and unreadable files, dangling
links, exact byte boundaries, multibyte overflow and unchanged original bytes. CLI and MCP tests check an error instead of an
empty success; app tests cover failed edits, safe reveal arguments, retry after repair and disabled controls during the read.
All use temporary homes or fake runners. The original four-case regression is retained. Ten mutation entries remove these
protections individually. `--failed-folders --tab folders` renders the recovery panel using canned data.

Native inspection found that bridging the TOML library's error to `NSError` lost its line and reason, showing only a generic
error code. The core now applies the existing `TOMLSyntax` explanation and wraps it in a localized-error value: an unclosed
array points to its opening line and names the missing bracket, rather than reporting the parser's internal error at EOF.
A loader regression test reproduced the loss before the fix and verifies that the repair information reaches the window.

On the machine reporting macOS 27.2 (26B123), a separately identified copy of the app with no Finder extension and a temporary
home showed the failure panel, revealed and selected its state file in Finder, and restored pins after the fixture was repaired
and Try Again pressed. Read and Reveal left the malformed bytes unchanged. A long unknown-field diagnostic scrolled while
both recovery buttons remained visible. The accessibility tree exposed the error and both buttons; spoken VoiceOver output
and the full long value beyond the inspection tool's text limit remain manual checks. English, Chinese, German and Arabic
previews cover the minimum window, large text and dark appearance.
