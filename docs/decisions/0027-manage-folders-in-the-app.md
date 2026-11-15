# 0027: Saved folders can be added and used in the app

Date: 2026-11-15. Status: accepted.

## Problem

Folders showed the saved paths, but its only actions were Unpin and Clear Recent Folders. Adding a folder required the command
line, and a recent folder could neither be pinned nor located in Finder from this page. The model also enabled those actions
before their asynchronous list refresh ended, allowing another action to run against the list still on screen.

## Decision

- Pin Folder opens a native directory chooser. Recent rows offer Pin; rows already pinned offer Unpin. A folder can appear in
  both lists, since being pinned does not remove it from recent history. The empty state explains the action available on the page.
- Every row offers Reveal in Finder, with the folder name first and its abbreviated path below. Actions receive the complete
  path even when its display is shortened. Buttons have localized labels, tooltips and the path as their
  accessibility value. Missing folders can still be unpinned.
- Pin and reveal use the shared context-input validation, then check that the path is an existing absolute directory. Reveal invokes the existing product convention,
  `open -R`, with the entire path as one argument; it never asks the default application to open that path. A failed validation
  explains that the folder may have moved or access may be restricted and does not remove saved state automatically.
- Pins and recent history continue to share `state.toml` with the CLI and MCP. Changes go through the existing locked, atomic
  state update. Pinning does not change config or recent history. A successful mutation has a localized confirmation; a write
  failure preserves the previous saved state and reports the error.
- Editing controls remain disabled until the refreshed list arrives. Both folder choosers use one asynchronous picker boundary
  with a guard against opening a second picker. Cancel restores the controls and preserves the previous notice. The window does
  not show an operation spinner while waiting for a person to choose a folder.
- The Folders view has its own file. The app keeps native controls, system colors and the six-section structure from ADR 0017.

## Alternatives

Opening the folder in the configured terminal or editor would need an action chooser and additional context. Reveal in Finder
is a small, predictable first action and leaves launching tools to the existing Finder menu. Automatically removing unavailable
folders would discard useful pins for disconnected disks or temporarily inaccessible locations. A separate app-only list would
disagree with `rh pins` and the assistant's view.

## Verification

Runtime tests cover pinning, normalized duplicate paths, unchanged config and recents, rejection of files, missing paths and NUL bytes,
write failure, and a reveal path containing quotes, shell syntax and a newline staying one argument. They use temporary homes
and fake process runners. Model tests inject folder choices and a suspended folder read to cover cancel, duplicate picker
requests, a non-repository choice, feedback, and controls staying disabled through the final refresh. No test opens a window.
Restoring the old timing made the regression test fail for both Unpin and Clear Recent Folders. The final `script/verify_all.sh`
passed: 1,707 tests, the app and Finder extension build, thirty localizations, schema and documentation checks, mutation-entry
consistency and public-safety checks. Existing launch protections are unchanged.

The headless preview accepts `--empty-folders`; `--feedback --tab folders` and `--failure-notice --tab folders` show folder
confirmations and failures. English, Simplified Chinese, German and Arabic were rendered, including long folder names and paths,
empty and failed states, the minimum window and dark appearance.

Native interaction was checked on the machine reporting macOS 27.2 (26B123), using a copy of the built app with a distinct bundle
identifier, no embedded Finder extension and a temporary `RH_HOME`. Cancel and Escape returned to usable controls; choosing a
directory pinned it; pinning a recent folder updated both occurrences; Reveal selected the directory in Finder. After renaming
it in Finder, Reveal reported it unavailable and Unpin still worked. The accessibility tree exposes each row button's action
and path. The review app, registration and temporary folders were removed afterwards.

One observed platform detail matters: entering a file path in the panel's Go to Folder sheet and pressing Pin returned that file
despite `canChooseFiles = false`. The runtime directory check rejected it and the saved pins stayed unchanged. The panel's
configuration is therefore not treated as validation. Full keyboard traversal and spoken VoiceOver output remain in the manual
checklist; inspecting the accessibility tree does not establish either.
