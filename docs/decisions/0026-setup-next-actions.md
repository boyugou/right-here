# 0026: Setup shows the next action before the diagnostic detail

Date: 2026-11-15. Status: accepted.

## Problem

The rendered first-run window showed five checks needing attention before the person had chosen anything. All five were pieces
that Set Up was about to create. After a successful setup, Install or Repair was still the prominent button and the default
Return-key action on every page. Checks mixed failures with successful diagnostics in one long list. Action results appeared
in a small sidebar footer, far from the controls that caused them. The menu preview used the same empty message for an absent
config, an invalid config and a valid config with no menu entries.

## Decision

- Before a config exists, the window presents setup as the next task, without an attention badge. The doctor's findings are
  still available in Checks. The command line's report and the checks themselves are unchanged.
- A healthy Overview offers Preview Finder Menu. Install or Repair is a secondary action on Checks, with no Return shortcut.
  Open Config stays in the header; Command-R refreshes when no operation is running.
- First-run agent choices show detected agents first. More AI agents reveals the others. A selected agent remains visible when
  that disclosure closes. If detection found nothing, all choices remain visible, including when the login shell did not answer.
  Choices cannot change while setup is applying them.
- Checks puts issues that need attention first, and offers separate disclosures for optional warnings and passed checks. The
  partition uses the same `DoctorCheck.isOptional` rule as the summary and badge. A known fix offers its corresponding action:
  go to the setup chooser, repair, open the config, or open extension settings. An unknown fix stays a readable instruction.
  An extension that is not registered offers repair in the onboarding card; one that is switched off offers System Settings.
- Progress and dismissible action feedback appear above the page content. A terminal test keeps its localized result there,
  including when its successful diagnostic is in the collapsed group. The test describes its temporary terminal window before
  it runs. Dismissing a message does not dismiss the underlying diagnostic.
- The Finder menu preview distinguishes loading, initial setup, invalid config, empty menu and a ready preview. Each empty state
  has a direct route to setup or Checks. Preview entries still never run actions.
- Keep native controls, semantic system colors, the existing six sections and the text config. Titles and values wrap; check text
  is one accessibility element and its recovery button remains separately reachable. New copy belongs to the catalog in all
  thirty shipped languages. Checks has its own view file instead of continuing to enlarge `SetupPages.swift`.
  A diagnostic's accessibility representation explicitly includes its title, status, detail, every note and fix, in that order.
  It uses the visible text's localization, home abbreviation and command formatting. Native inspection found that combining
  the selectable text and assigning the status as its accessibility value discarded the detail, notes and fix. A synthetic
  text element avoids that merge, following Apple's
  [accessibilityRepresentation documentation](https://developer.apple.com/documentation/swiftui/view/accessibilityrepresentation(representation:)).
  The visible text remains selectable; the recovery button remains outside the replacement representation.
- The flow of choices uses leading-edge coordinates once. Its old manual RTL reversal duplicated SwiftUI's reversal and left
  Arabic choices on the left, separated from their headings. This was reproduced and corrected in the macOS headless render;
  Apple's [LayoutDirection documentation](https://developer.apple.com/documentation/swiftui/layoutdirection) describes the automatic reversal.

## Alternatives

- A new preferences editor would address a different task: editing an existing text config while retaining comments, ordering and
  overlays. This iteration improves the entry points to that workflow without inventing a second settings model.
- Hiding warnings entirely would lose useful information for CLI and agent users. Optional checks remain one disclosure away.
- Running repair directly from a first-run diagnostic would bypass the person's choices. Its Set Up action only navigates to
  the chooser.
- A timed toast could disappear before a person reads a long error. Feedback stays until it is dismissed or another action
  replaces it, and is announced without moving keyboard focus.

## Verification

`SetupCheckActionTests` covers the diagnostic partition, optional warnings becoming failures, fix-specific actions, unknown fixes
and launch-result feedback. `SetupModelFirstRunTests` covers neutral initial presentation, menu states, setup navigation without
writes and dismissing a message without changing diagnostics. The existing setup guards and launch protections are unchanged.
The full `script/verify_all.sh` passed: 1,696 tests, the app and Finder extension build, all thirty localizations, config schema,
embedded documentation, command/link checks, mutation-entry consistency and public-safety checks. This change does not alter a
security protection, so the full mutation sweep was not required.

`script/preview_setup.sh` has canned `--config-error`, `--empty-menu`, `--feedback` and `--failure-notice` states. `--first-run`
also accepts `--tab menu` or `--tab checks`. The gallery expands optional and passed checks so every diagnostic remains visible
for translation review. Rendered checks cover English, Simplified Chinese, German, Arabic and Thai, light and dark appearance,
and the minimum window. These are headless renders, not evidence of native VoiceOver or real Finder behavior; those remain in
the manual checklist.

The minimum-size preview now clips a natural-height page inside its viewport instead of compressing the text or moving the
header offscreen. The diagnostic gallery also refuses to render when a doctor's message is not represented; the previously
missing agent-detection and shell-PATH messages are included.

Later native accessibility checks on macOS 27.2 (26B123) found that the combined diagnostic exposed only its title and status.
A temporary config with a warning, per-machine overlay and symlink visibly showed a detail, two notes and a fix, but none of
those appeared in its accessibility element. Attention, optional and passed rows all had the same omission. Replacing the
combined element with the explicit text representation made all of those fields available, in English, Simplified Chinese
and Arabic. Recovery buttons remained separate, and a visible instruction could still be selected with a mouse drag.

Temporarily moving the isolated fixture's config and overlay aside changed the first-run instruction to Set Up on Overview.
Pressing its separate diagnostic action opened the chooser without creating a config or command link. The fixture was restored
and verified afterward. The full gate passed again with 1,718 tests, app and extension builds, localization, schema, docs,
mutation-entry consistency and public-safety checks. The unique review app, registration, preferences, saved window state and
temporary home were removed. These checks inspect native accessibility elements and interaction; actual spoken VoiceOver
traversal remains a manual check.
