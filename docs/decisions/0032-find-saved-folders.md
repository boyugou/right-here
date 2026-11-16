# 0032: Find saved folders without changing their order or contents

Date: 2026-11-15. Status: accepted.

## Decision

The Folders page has a local Find field when it has saved folders or a query. Every whitespace-separated word must occur in
the full path or the abbreviated, escaped path shown by the window. Matching folds case, diacritics and character width using
the displayed language. It preserves the original values and order; pinned and recent remain separate groups.

Command-F selects the current query and brings the field back into view. The Edit menu enables Find Folders only when this
page has a field. Refresh, pin changes and visits to another section retain the query for this window. Escape clears a query,
then releases focus when already empty. A clear button and an explicit no-results panel offer the same recovery.

Search never reads the filesystem or writes saved state. A failed saved-folder read retains its distinct recovery panel. A
genuinely empty list offers Pin Folder without a redundant search field. During filtering, Clear Recent Folders is hidden so
it cannot be mistaken for removing only the displayed results. Pin Folder remains available.

## Alternatives

Sorting by relevance would disrupt the person's pinned order and the recency order. Searching basenames alone would hide the
location information that distinguishes identically named folders. A global search would imply searching actions, settings or
the filesystem, which this field does not do. Live matching of these bounded, already-loaded lists needs no asynchronous job.

## Verification

Tests cover names, absolute and home-relative paths, multiple terms, literal punctuation, diacritics, fullwidth text, Chinese,
escaped control characters, locale-specific case folding and retained ordering. App-model tests check command availability
and query retention through a folder change, refresh and section visits.

On the machine reporting macOS 27.2 (26B123), an isolated app with 42 pins and 20 recents scrolled to the bottom, then returned
to the field with Command-F. Repeating Find selected the query for replacement. An accent-free query found a name with
accents; pasted Chinese words found a nested Chinese path. Command-R and section switching retained the query. The Edit menu
disabled Find on Overview and enabled it on Folders. These operations left the saved file byte-identical. Input-method
composition, spoken VoiceOver and all keyboard clearing paths remain in the manual checklist.

English, German, Chinese and Arabic previews cover matching and no-result states, minimum width, large text and dark
appearance. ImageRenderer cannot render the native text field, so previews draw its static value in the same position;
editing and focus are checked in the native app.

## Focus timing follow-up

A native review reproduced an intermittent lost Command-F focus when the Folders page appeared during a rapid section switch.
The field handles the request in its own cancellable task and yields before assigning focus, so a disappearing page abandons
the request. The same native sequence then focused and selected the query on first entry and repeated visits; the manual
checklist also covers leaving immediately after Find. This is a measured UI fix, not a claim that task scheduling guarantees
native-view attachment on every system.
