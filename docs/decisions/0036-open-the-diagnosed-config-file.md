# 0036: Open the config file named by the problem

Date: 2026-11-15. Status: implemented. Extends [0013](0013-config-sync.md) and
[0026](0026-setup-next-actions.md).

## Problem

The doctor could name a syntax error in `config.local.toml` while the setup window's Open Config action opened `config.toml`.
When both files existed, the action always preferred the main file. The person reached a valid file that could not fix the
reported error. The window also offered no way to choose the local file for ordinary editing.

## Decision

The config parse-error row names the file in its recovery button, such as **Open config.local.toml**, and opens that file directly.
The header offers a native menu of the actual file names when both layers exist, and retains a single Open Config button
when only one exists. Generic terminal or agent warnings use the same choice when both files exist; they do not guess which
layer supplied a setting. A diagnostic with an unknown source likewise does not become a path to open.

The runtime carries a typed main/local selection. It derives each URL from the configured main path and the existing overlay
naming rule, so custom config names work too. It never parses localized sentences or accepts a path from diagnostic text.
The default opening selection follows the doctor's priority: a dangling config link first, then the first error. This keeps
the stored source and default action aligned with the displayed problem even when a different layer also has a syntax error.
The dangling-link check retains its manual instructions and has no row button; the header still offers the known layers.

An explicit selection takes precedence over an error elsewhere. Before opening, the runtime loads the current file state
again. If the selected file disappeared, it reports that failure and does not open the other file or create a replacement.
A dangling link remains a known layer and is handed to the editor at its own path; Right Here does not write its target.
Paths still travel as separate arguments to `open -t`. File contents, merge rules and first-run creation remain unchanged.

## Alternatives

Always opening the main file caused the observed dead end. Always opening the error file would prevent a person from choosing
the other layer deliberately. Opening both files would create unnecessary editor windows and leave the recovery target
ambiguous. An embedded TOML editor is outside the setup window's role.

## Verification

A regression test first failed against the old action: an overlay syntax error opened the main file. Runtime tests now cover
the correct default target, explicit selection with an error in the other file, custom names containing a quote, a disappeared
selection, a dangling local link, unknown diagnostic sources and an overlay without a main file. A second failing regression
covered a dangling local link taking precedence over a main-file syntax error, matching the doctor's displayed check.

Native review on the machine reporting macOS 27.2 (26B123) used the production views, model and actions with fake system facts,
a runner that recorded arguments without launching an editor, and a temporary home. The named recovery button opened the
local file. The header menu exposed both actual names and their paths, and each choice recorded the corresponding argument.
After the main file was moved aside and the view refreshed, the single button opened the remaining local file. Moving the
local file after refresh produced a visible missing-file message and no additional editor request. The review app and its
temporary data were removed. This does not verify an external editor's behavior or spoken VoiceOver.

`preview_setup.sh --local-config --config-error --tab checks` uses the real layered parser for its canned error. ImageRenderer
cannot draw a native menu, so its static preview shows the closed label and chevron; menu interaction was checked natively.
