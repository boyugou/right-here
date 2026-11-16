# 0029: Feedback stays readable without displacing the page

Date: 2026-11-15. Status: accepted.

## Problem

Operation feedback was outside the page's scroll view and grew without a limit. A long process error could push the heading,
dismiss control and page out of the minimum window. The accessibility tree also combined feedback with the sidebar's subtitle,
and combined a worktree-list failure with the repository path. The sidebar had six buttons but no discoverable keyboard commands
for switching sections; Command-R existed only on the footer button.

## Decision

- Feedback keeps its natural height until the message reaches 132 points; longer messages scroll inside that viewport. Dismiss
  stays outside the scrolling text. The same component handles confirmations and failures, with their existing colors and symbols.
  No part of a process error is truncated or rewritten. A custom layout measures the natural height before constraining
  `ViewThatFits`: a maximum-height frame alone made even one-line confirmations occupy the whole allowance.
  The viewport exposes the full message as its accessibility representation. Native inspection of the initial scrolling branch
  found the scroll bar but no text, so relying on that branch's automatic accessibility tree was insufficient.
- Problem messages offer Copy Message. It copies all of the displayed message, including text outside the viewport, and keeps
  the problem on screen. The copy button confirms the action and the app announces it. A stale view cannot copy a dismissed or
  replaced problem. Success confirmations have no copy button: copying a configuration must leave the actual configuration on
  the clipboard. Tests inject the clipboard writer and never change the person's clipboard.
- Navigation, the current page, feedback and repository controls are separate accessibility containers. The brand is one combined
  element; AI-assistant section titles and a failed worktree listing are headings. This preserves the visual structure in the
  accessibility tree instead of merging unrelated text across columns.
- The View menu contains all six section commands, in sidebar order, with Command-1 through Command-6. Refresh is Command-R in
  the same menu, disabled under the same conditions as the footer button. Every entry calls the same model operation as its
  visible button. Titles, symbols and shortcuts are defined together in the app's navigation file.

## Alternatives

Putting every message in an alert would interrupt ordinary actions. Moving feedback into the page would either hide it below the
current scroll position or require scrolling the person away from their work. Truncating a process error could hide its useful
cause. A bounded, independently scrollable message retains both the error and the page's recovery actions.

Adding shortcuts only to sidebar buttons would make them harder to discover. A second navigation state for menu commands could
disagree with the selected page, so the menu uses the existing model.

## Verification

The canned `--long-notice --minimum` preview reproduced the old overflow with twelve diagnostic paragraphs. The preview also
supports the short confirmations and localized failures already available through `--feedback` and `--failure-notice`.
`SetupModelFeedbackTests` verifies copying a message longer than 4,000 characters without losing its content or replacing the
failure, rejecting dismissed and replaced notices, and keeping a copied MCP configuration instead of its confirmation text.

The full verification gate passed with 1,718 tests, the app and extension build, 259 catalog strings in 30 languages, schema and
documentation checks, 364 consistent mutation entries and the public-safety check. Deliberately truncating a copied problem,
clearing the notice and removing the stale-notice guard made both new feedback tests fail; the original implementation was
restored before the full gate. Minimum-window previews covered long English feedback, compact English and German confirmations,
a Chinese failure, and Arabic with dark appearance and larger text.

Native checks on macOS 27.2 (26B123) used an isolated review bundle and temporary home and Git repository. All six section
shortcuts selected their corresponding sidebar page. Command-R loaded an externally added pin; removing it produced a compact
confirmation without a copy control. Long feedback scrolled independently with Copy Message and Dismiss still visible, and its
text appeared separately in the accessibility tree. Navigation, the current page and repository controls were distinct
containers; AI sections and a worktree-list failure exposed headings. Making the fixture's Git metadata temporarily unavailable
showed the list failure and Try Again; restoring it and retrying restored the worktree row.

The native check inspected the copy control; the injected-writer tests verified its complete payload without modifying the real
clipboard. Spoken VoiceOver traversal and complete keyboard Tab traversal remain manual checks. The review process exited when
its window closed, and its temporary files, registration, preferences and saved window state were removed afterward.
