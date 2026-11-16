# Reconciling the two development lines

Date: 2026-11-16. Current base: `2a2d29b` (1.2.25). Preserved earlier work: `1c26d9d` on
`codex/design-and-setup-improvements` (24 commits from the older 0.3.2 line).

The work began without fetching the current main. The cached main still named `449aa04` from October 16.
The published history now starts at the 1.0.0 snapshot and has no common ancestor with that line.
The published main was not replaced. Both lines remain available.

The combined version starts from current main. Useful behavior is rewritten against its contracts.
The older tree is a source of ideas and regression cases, not a replacement tree.
The contributor entry point now requires fetching and comparing the live main before new development.

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

The integrated behavioral revision passes 2,831 tests: 1,176 Core, 1,068 Kit, 116 MCP, 188 CLI and 283 app-model tests. The extra
47 tests are relative to the exact current base. Newly reproduced regressions include quiet-period config changes, external-editor
file selection, draft conflict refresh and worktree context, alongside the first-run and saved-state failures above. App-model
tests now run in GitHub CI too.

Their first CI run exposed four existing repair tests that silently depended on a helper installed in `/Applications`.
Using an absent helper under a temporary home reproduced all seven assertions on the development Mac. The fixture now owns a
non-command-running executable in that home, and its fake registration follows that bundle. The production checks remain intact;
all 283 app-model tests then pass without using an installed app.

Seventeen targeted protection-removal runs passed against committed combined revisions: 437, 535, 1029, 1030, 1105 and 1248–1251
at `2af79bb`; 292, 307, 520, 528, 870, 1028, 1252 and 1253 at `d156047`. Each removed protection made a relevant test fail.
The list has 1,254 matching entries; this is not a claim that all 1,254 were run. The old line's 1,775-test result and mutation sweep
are historical evidence only.

## Native acceptance

Interactive checks used a separate review bundle, temporary home, fake system facts and fake process runner on macOS 27.2
(26B123), Xcode 27.2 (27B52). No terminal, editor or Finder extension belonging to the person was controlled or installed by the
review. Worktree deletion with real git remains a regression test in temporary repositories.

- First-run app pickers opened and changed their values. More AI agents exposed all remaining choices, including OpenCode.
  Setup retained a checked missing agent and put the remaining Finder action first.
- A settings menu changed the default terminal, wrote the temporary config and exposed Undo. Undo restored the previous value.
- Command-F focused folder search and selected its current query. `resume` matched `Résumé 2026`. A no-match query had its own
  explanation and Clear Search; another section and back retained it. Escape cleared it.
- Worktrees showed complete branch/path identity in accessibility and confirmation. The second question named `.env` and the
  same worktree; Cancel retained the row. Repository switching and a failed listing followed by Try Again worked.
- An external comment change kept a native text-editor draft, displayed the conflict and disabled Save. An overlay error's Config
  action preserved the shared draft with an explanation; after Revert it selected This Mac Only and displayed the diagnosed text.
  A regression also clears the now-obsolete save-or-revert notice.
- A malformed saved-folder file showed its error, source-file action and Refresh. Repairing the temporary file and pressing Refresh
  restored the list. A long operation error kept navigation visible and opened a bounded, selectable details popover with reachable
  Copy Message and Dismiss controls.
- Switching from a scrolled page reset its successor to the top. Scroll content stopped at the fixed header after clipping was added.
  The Checks accessibility tree retained diagnostic text, status and fix actions; its current-main implementation was kept.
- An app-local red system-accent preference changed selection, checkboxes and the default button. Forest remains the default when
  the system allows an app accent. Offscreen native pictures cover light/dark, Arabic flow and German long text at the minimum width.

Full Tab navigation, spoken VoiceOver, increased-contrast preferences and native-speaker translation review remain the manual
checks they were before this integration. Offscreen native controls draw as an inactive window; their grey selection is not a
disabled interactive control. Xcode 26 is not installed locally; the local gate reports that supported-floor build as skipped,
and CI's macOS 26 job builds the app and extension.

The preview source list was also repaired: both modes link current sources, removing stale links from an older checkout, and the
pre-push gate builds and renders both the stand-in and native-control modes. README pictures are regenerated from the combined view.
