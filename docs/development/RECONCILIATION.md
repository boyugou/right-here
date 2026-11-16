# Reconciling the two development lines

Date: 2026-11-16. Current base: `2a2d29b` (1.2.25). Preserved earlier work: `1c26d9d` on
`codex/design-and-setup-improvements` (24 commits from the older 0.3.2 line).

The work began without fetching the current main. The cached main still named `449aa04` from October 16.
The published history now starts at the 1.0.0 snapshot and has no common ancestor with that line.
The published main was not replaced. Both lines remain available.

The combined version starts from current main. Useful behavior is rewritten against its contracts.
The older tree is a source of ideas and regression cases, not a replacement tree.

## Product foundation

Keep current main's eight sections, GUI configuration editors, proposals, Undo, per-machine settings, all fifteen built-in
agents, ignored-file removal confirmation, Shortcuts entities, repository links, Office templates and distribution pipeline.
Use the current Icon Composer build and the current architecture and safety rules.

The visual direction combines the earlier current-directory mark (`./`) and forest accent with the newer compact header,
grouped editing rows and bounded content width. A monochrome sidebar replaces competing colored tiles. The app icon,
documentation icon and Finder toolbar mark share the same original geometry. The asset catalog supplies the default accent;
the production view does not force a tint over the person's system preference.

## Disposition of the earlier work

| Earlier commits | Decision for current main |
| --- | --- |
| `dbf09ea`, `119cf5e` | Rewrite the next-action hierarchy. Preserve current setup phases, repair behavior and live editable defaults. The current main already distinguishes extension registration from readiness. |
| `f81642c` | Keep clearer folder identity and operation feedback. Current main already has Pin, Unpin, Reveal and Shortcuts integration. |
| `6fd784b`, `0aa064d` | Rewrite repository selection, read recovery and complete removal identity. Preserve current main's second confirmation for ignored files and its non-forced removal rules. |
| `fc28449`, `ab87e06` | Adapt readable operation feedback. Keep the current eight-section order and shortcuts. Do not restore the older six-section map. |
| `3b6dc9d` | Reset scrolling when a section or detail route changes. Drafts remain in the model. |
| `f471125` | Recheck diagnostic accessibility against the combined native window. Older accessibility results do not prove the new binary. |
| `65d687e` | Keep current main's configured-language behavior. Remove the remaining double mirroring of first-run flow layouts. |
| `16c6171` | Extend current main's saved-state protection. It already rejects malformed TOML writes; wrong field types, unknown fields, oversized writes and failed-read presentation need the additional checks. |
| `97d148d` | Drop the rejected folder-and-arrow icon and its PNG asset chain. |
| `cac9664`, `a0614a5` | Adapt folder search, distinct no-match state and focus behavior to the newer folder page. |
| `acb6bb5` | Keep the identity and restrained emphasis. Preserve the newer editable window, native icon pipeline and content bounds. |
| `cfd111f` | Keep the principle of checking actual deadlines. Do not remove current main's MCP wrapper: its test uses a server budget shorter than the child's own deadline, so the wrapper has a demonstrated purpose. |
| `dcaf48c` | Clarify preview interaction while retaining Edit Menu mode and all newer editors. Regenerate screenshots from the combined version. |
| `5f53aa4` | Use OpenCode as the display name. Keep its command, id and config keys unchanged. Update the config reference too. |
| `b3c631b`, `a41b50a`, `1c26d9d` | Retain as historical evidence only. Their validation applies to the older line. |
| `ca03ad0` | Rewrite config recovery around the existing two-file editor. Respect drafts and open the selected file externally. |
| `f9d18f9` | Rewrite activation refresh for the newer editors. Preserve `editedAt`, unsaved drafts and conflict reporting; comment-only changes also matter to the text editor. |
| `a2d4687` | Use real choice semantics with current application icons, all fifteen agents and setup progress. Preserve available choices across refreshes and reconcile unavailable defaults. |

## Verification boundary

The exact current base passed 2,784 tests before changes. Seventeen synthetic baseline pictures include Overview, first run,
Agents, Config, menu preview and editing, Folders, Worktrees, dark Arabic and long German text. Real-control pictures use an
offscreen native window and establish geometry, not active-window keyboard behavior.

The first integrated state passes 2,802 tests and builds the app and Finder extension. New regressions first failed on the
current main for invalid saved-folder fields and vanished first-run app choices. The work also checks failed reads in the
window loader, CLI and MCP, preserves unreadable bytes, and keeps saved-folder writes within the readable byte limit.

Further behavioral ports and their native verification are still in progress. The old line's 1,775-test result and mutation
sweep are not validation of this tree. The current mutation list has more than twelve hundred entries; matching patterns is
not a completed mutation run. Changed protections need targeted removal tests against a committed combined tree.
