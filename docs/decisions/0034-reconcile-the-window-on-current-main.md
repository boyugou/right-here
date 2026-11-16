# 0034: Reconcile the window on current main

Date: 2026-11-16. Status: implementation in progress.

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

## Alternatives

Replacing the published tree with the earlier tree would remove newer capabilities and protections. Merging unrelated
histories would obscure that product choice. Copying every earlier patch would also duplicate solved problems.
The comparison in [the reconciliation record](../development/RECONCILIATION.md) gives each earlier commit a disposition.

The newer window's compact header, grouped rows and bounded width fit its live settings better than the earlier large
readiness hero. The earlier single-accent navigation gives those settings a clearer hierarchy than competing colored tiles.

## Evidence

The combined native window on macOS 26 reproduced a settings menu that exposed its value through accessibility but did not open
with a click or keyboard input. The `.menuStyle(.button)` plus `.buttonStyle(.plain)` combination was responsible: a standard pop-up
Picker opened and changed the same first-run binding. `ChoiceMenu` now uses `.borderlessButton` with no hand-drawn indicator in its
label; AppKit supplies the indicator. Its menu opened, choosing Terminal saved the value, and Undo restored Ghostty in the same
isolated review. This supersedes ADR 0029's blanket ban on that menu style: its evidence was about extracting a hand-drawn chevron
as the label's first image. The whole-row borderless-button restriction remains. Real-control renders establish native geometry.

Switching from a scrolled Overview to Finder Menu displayed the new page at its top. Scrolling also exposed content drawing over
the compact header; the page now clips its scroll content at the header boundary.

The review compares actual renders of both versions. Current-main tests establish the base independently of old-branch
results. Regressions cover the specific state changes and safety conditions. Native controls, keyboard focus, accessibility,
appearance overrides and remaining workflow ports are being checked separately; final evidence belongs in the manual checks
and reconciliation record.
