# 0039: First-run choices use native selection controls

Date: 2026-11-16. Status: implemented. Updates [0033](0033-current-design-language.md).

## Problem

The first-run chooser drew radio and checkbox marks inside ordinary buttons. The native accessibility tree exposed every
choice as a button, with only a selected trait distinguishing checked choices. The appearance implied single or multiple
selection without corresponding control roles or values.

## Decision

Default terminal and editor use native menu Pickers, showing the current application name. Their visible section headings
remain, and the Pickers retain those names as accessibility labels. An empty app list shows None found. Agent choices use
native checkbox Toggles in the existing wrapping layout, with a separate Boolean binding for each agent. The custom chip
view and its decorative control marks are removed.

The chooser preserves available app choices across refreshes. If an app disappears, its selection becomes the detected
available default, otherwise the first available app, or nil when no app remains. This keeps the menu value and the value
setup writes consistent. Newly available apps can become defaults after an initially empty read. Agent opt-ins remain the
person's, including agents not found by detection. Existing detected-first grouping and More AI agents disclosure remain.

## Alternatives

Native radio groups would supply the right semantics, but their visible options grow with the installed-app list and long
names. A menu gives this default-app choice a stable footprint. Keeping custom chips and adding accessibility traits would
still require implementing their keyboard selection and value behavior. Native controls already provide those mechanisms
and adapt to the system appearance and layout direction.

Apple documents [Picker as a mutually exclusive choice and Toggle as an on/off choice](https://developer.apple.com/documentation/swiftui/controls-and-indicators).
The dedicated design review independently identified the semantic mismatch and reviewed the revised layouts.

## Verification

A native review used a separate app identity, temporary homes, fake system facts and a runner that executed no processes.
Before the change the accessibility tree described all choices as buttons. Afterward it described named pop-up buttons
with current application values, and checkboxes with 0/1 values. Opening the menus and pressing Down and Return selected
Terminal and TextEdit. Checking Claude Code and Codex, then unchecking Claude Code, retained Codex. Set Up wrote exactly
those app defaults and the Codex opt-in to the temporary config and showed the matching defaults afterward.

The Arabic native window mirrored the controls and retained readable product names. Selecting OpenCode under More AI agents
and collapsing the disclosure kept it visible and checked. Its temporary setup config retained Claude Code, Codex and
OpenCode. English, Simplified Chinese, German and dark Arabic headless renders were also reviewed at minimum width.
The review processes, registrations, preferences and temporary homes were removed; cleanup accounted for the system's
equivalent `/var` and `/private/var` paths.

Two model regressions failed against the previous implementation: losing a selected app retained its obsolete id, and
discovering apps after an empty first read retained nil. Tests cover both transitions and preserve agent choices. Existing
refresh tests cover retaining still-available choices. A native fixture removed the selected terminal and all editors: the
window showed the remaining Terminal and None found. Restoring the original available apps with Command-R retained Terminal,
restored the editor picker, and preserved both checked agents. The current system's Tab behavior did not enter the controls;
complete keyboard traversal and spoken VoiceOver remain manual checks. The menu's arrow-key behavior is verified separately.

The full gate passed with 1,775 tests, app and Finder extension release builds, localization, config schema, documentation
and public-safety checks. No protection in DESIGN section 9 changes in this iteration.
