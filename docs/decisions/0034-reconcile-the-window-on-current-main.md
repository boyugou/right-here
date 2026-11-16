# 0034: Reconcile the window on current main

Date: 2026-11-16. Status: accepted.

## Choice

The combined app builds on current main's editable product. Its eight sections, drafts, proposals, Undo and per-machine
configuration remain. The earlier line contributes a quieter current-directory identity, native first-run choices and
specific interaction improvements. Each behavior is adapted and verified on the new base.

The icon remains an Icon Composer document. Original dot and slash vectors replace the pin and prompt layers.
Forest is the default asset-catalog accent. Navigation and setting symbols use one quiet treatment.
System text colors, accent preferences, increased contrast and native control behavior remain the rendering inputs.

First-run defaults use native pop-up pickers with current application icons. Agents use native checkboxes. Found agents lead; other
agents remain available through disclosure, and checked choices remain visible when it closes. An empty detection does not
hide the choices. Setup's phase feedback remains visible.

Saved-folder reads distinguish absence from failure. Invalid field types and unknown fields refuse an update before its
closure runs. Writes respect the same byte limit as reads. The folder page offers the source file and a retry after failure.

The remaining Finder setup action leads after a successful setup. Its button follows the actual diagnostic: Settings for a disabled
extension, Repair when installation needs repair. A successful report is a disclosure below it; new warnings expand the report again.
Failed reports remain above the chooser. Menu preview text distinguishes expanding submenus here from running actions in Finder.

Folder search matches names and paths, keeps the person's query across visits and supports Command-F and Escape. Long operation
messages occupy a compact sidebar button; a bounded popover exposes their complete text, Copy Message and Dismiss.

Config recovery chooses the diagnosed shared or local file without throwing away a draft. The external editor opens the file selected
on the Config page. Activation compares the bounded sources a read consumed, including comments and link destinations. Changed
settings queue a new read even during the quiet period or an existing read. Comment-only edits refresh the editor and conflict state
without running the login shell. A GUI edit's newer state still wins over an older doctor's answer.

Worktree questions capture their repository and complete identity. Switching repositories clears the old actionable rows at once;
manual choices remain available in the window. Removal stays busy through its final listing. Ignored-file confirmation retains the
same captured repository and the exact files the person agreed to lose. Read failures have a local retry.

## Alternatives

Replacing the published tree with the earlier tree would remove newer capabilities and protections. Merging unrelated
histories would obscure that product choice. Copying every earlier patch would also duplicate solved problems.
The comparison in [the reconciliation record](../development/RECONCILIATION.md) gives each earlier commit a disposition.

The newer window's compact header, grouped rows and bounded width fit its live settings better than the earlier large
readiness hero. The earlier single-accent navigation gives those settings a clearer hierarchy than competing colored tiles.

## Evidence

The combined native window on macOS 27.2 (26B123) reproduced a settings menu that exposed its value through accessibility but did not open
with a click or keyboard input. The `.menuStyle(.button)` plus `.buttonStyle(.plain)` combination was responsible: a standard pop-up
Picker opened and changed the same first-run binding. `ChoiceMenu` now uses `.borderlessButton` with no hand-drawn indicator in its
label; AppKit supplies the indicator. Its menu opened, choosing Terminal saved the value, and Undo restored Ghostty in the same
isolated review. This supersedes ADR 0029's blanket ban on that menu style: its evidence was about extracting a hand-drawn chevron
as the label's first image. The whole-row borderless-button restriction remains. Real-control renders establish native geometry.

Switching from a scrolled Overview to Finder Menu displayed the new page at its top. Scrolling also exposed content drawing over
the compact header; the page now clips its scroll content at the header boundary.

The review compares actual renders of both versions. The combined native review verified selection, save and Undo, search and its
focus shortcuts, draft conflicts and recovery routing, worktree confirmation and cancellation, failed-read retries, scrolling and
an app-local red system-accent override. It inspected accessibility roles, descriptions and actions; spoken VoiceOver and full Tab
navigation remain manual checks. English, German and Arabic offscreen native renders cover layout separately from active interaction.

Both preview modes now enumerate current view sources and remove old symlinks. The former fixed list omitted a newly added file;
a stale link let one cached preview build while a fresh native preview failed. The pre-push gate now builds and renders both modes.
Current-base tests and targeted mutation runs are recorded in [the reconciliation record](../development/RECONCILIATION.md).
