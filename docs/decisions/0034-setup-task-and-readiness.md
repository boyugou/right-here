# 0034: The next setup task leads; registration is not readiness

Date: 2026-11-15. Status: implemented. Updates [0011](0011-first-run-card.md) and [0026](0026-setup-next-actions.md).

## Problem

After Set Up, the window led with a technical installation record. All of its marks were green, including a Finder extension
described as "registered but switched off". The repeated three-step card began with choosing tools that the person had just
chosen. The remaining action, enabling the extension, was farther down the page. A successful installation report establishes
that setup's operations succeeded; it does not establish that Finder is ready.

The dedicated design review independently identified the same hierarchy and status contradiction in the rendered first-use
journey. Its review of the revised English, Chinese and German views confirmed that the remaining action leads and failed
setup remains visible.

## Decision

- Once a config exists, Overview leads with the remaining Finder task. A disabled extension offers Finder Extension Settings.
  A missing extension shows the doctor's actual detail and Install or Repair. Unknown fixes lead to Checks instead of assuming
  that a Settings switch is the answer. The completed tool-choice step is removed; defaults and Open Config remain available.
- An ordinary successful installation record is collapsed below the task. Failures, warnings and unapplied config choices
  remain visible above it. The existing setup-result scroll target now identifies that task or the visible error. A healthy
  Overview continues to omit an ordinary record.
- `SetupStepSummary` combines an installation outcome with the current extension check. Registration with `needsUser` gets an
  orange hollow circle and the existing switched-off sentence. A missing check is pending, a failed check is a problem, and a
  warning remains a warning. The extension can receive a completed mark only after its check is `ok`. A failed or skipped
  installation step retains its outcome even if the current extension check is healthy.
- Try it and the Quick Actions fallback remain below the primary task. Try it points to Checks; it never runs a terminal test
  while the extension is unavailable. Setup, repair, CLI reports and extension registration behavior do not change.
- Reuse the existing translated instructions. Remove the four obsolete three-step headings and labels from all thirty
  languages instead of retaining unused copy.

## Alternatives

Keeping the installation report first and changing its colors would correct the false completion signal but leave the next
action behind the record. Hiding every report would also hide failures and unapplied choices. A new multi-page wizard would
duplicate the existing chooser and make revisiting state harder; the window already has the facts needed to show the next task.

## Verification

Six `SetupStepSummaryTests` cover successful registration outcomes, enabling the same extension, missing and unanswered checks,
an absent or unrelated check, failed and skipped installation steps, and ordinary installed pieces. Existing setup tests cover
which reports contain actionable news and which action belongs to each fix.

Headless SwiftUI renders cover the minimum window in English, Chinese, long German and dark Arabic, including expanded details,
failed setup, an unregistered extension and choices not applied. `preview_setup.sh --set-up` renders the normal next task;
`--setup-details` expands its record, and `--missing-extension` exercises the repair state.

Native interaction on the machine reporting macOS 27.2 (26B123) used the real views, model and setup actions over fake system
facts and a runner that executed no processes. All installation writes stayed in a temporary home. Set Up from the bottom of
the chooser brought the next task into view. The record expanded with its pending-extension text. Changing only the fake
extension state to enabled let the existing watcher reach a healthy Overview without Refresh. Changing it to missing showed
the actual failure and Repair; pressing Repair returned to the enable-extension task. These checks do not establish real
System Settings behavior or spoken VoiceOver; those remain in the manual checklist.

The full repository gate passed with 1,752 tests, app and extension builds, localization, schema, documentation and public-safety
checks. No protection in DESIGN section 9 changes in this iteration.
