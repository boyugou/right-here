# 0011: A first-run card in the setup window

Date: 2026-10-12. Status: decided; step 3 amended by [0023](0023-the-window-says-before-it-tries.md).

## Decision

While the doctor's Finder extension check is not ok, the setup window shows a three-step card above the checks:
1. pick your terminal and editor (a read-only summary of the doctor's two checks, and a button that opens the config),
2. turn on the Finder extension (a button that opens the Extensions settings through
   `FIFinderSyncController.showExtensionManagementInterface`),
3. try it (the existing Test Terminal Launch).

Under it, a line says that Quick Actions work without the extension, with the path to give them a keyboard shortcut
(System Settings › Keyboard › Keyboard Shortcuts › Services). The details list starts collapsed while the card shows.

While the extension is not ok, the window runs the doctor again every two seconds without the busy state (so no
button flickers) and stops when the extension is ok or the window closes; it skips a round while the person's own
action (a launch test) is running. The poll runs while the window exists, also when System Settings is in front,
because that is where the person flips the switch.

## Why

The extension is the one step that needs the person outside the app, and macOS gives no callback when it is switched
on; polling the same check the doctor uses is the only signal. The Quick Actions line is there because the extension
is the part that fails on some machines and in iCloud Drive; the Services work without it.

## Checked

The window was rendered headlessly in English, German, Arabic (right to left) and Japanese (dark) with
`script/preview_setup.sh <out.png> <language> --onboarding`, which pretends the extension check is not ok. No text
is cut off. The polling and the real extension toggle were not run.
