# 0038: Keep the worktree identifiable through removal confirmation

Date: 2026-11-15. Status: implemented. Extends [0028](0028-worktree-browser-state.md).

## Problem

The worktree list led with its branch, but the removal confirmation named only its folder. Those names can differ, so the
person had to reconstruct which item they had selected at the point of confirmation. Long branches with a shared prefix
also lost their distinguishing suffix in the list. A detached worktree received the same promise that its branch would be
kept, even though it had no branch.

## Decision

Branch names truncate in the middle, preserving their beginning and end. The row's help contains both the complete branch
and folder. The native confirmation repeats that identity without truncation: a localized Branch label and the full name,
or Detached HEAD, followed by the folder and the consequence. Only a worktree with a branch says that its branch is kept.
Both cases explain that uncommitted changes prevent removal.

Display values escape control and directional-formatting characters, and inserted values use the localizer's directional
isolation. The underlying branch and path remain unchanged. The existing captured removal request, Cancel action,
non-forced removal and branch-retention behavior are unchanged.

## Alternatives

Using only the folder in both places would hide the branch that people use to distinguish parallel work. Wrapping every
long branch would make otherwise equivalent rows take varying heights. A custom confirmation window would add layout and
interaction machinery; the existing native dialog accepts the full identity as its message.

## Verification

The branch-identity and detached-consequence regressions failed against the previous message. Tests now cover a branch
whose name differs from its generated folder, a detached worktree, and escaped names across all thirty languages while
checking that the actual removal target is unchanged. The long-name preview includes two branches with the same long
prefix and different suffixes, plus a detached worktree. English, Simplified Chinese, German and Arabic renders retain
the distinguishing suffixes and visible actions.

A native review on macOS 27.2 used a separate app identity, temporary home and fake process runner. The native list showed
both branch suffixes; accessibility help included their complete names and paths. The actual confirmation's accessibility
tree contained the complete branch and folder for the branched case, and Detached HEAD with no branch-kept claim for the
detached case. Cancel returned to all four rows in both cases. No removal was executed. The review process, registration,
preferences and temporary home were removed afterward.

The window capture returned blank images for the native sheets, so this review establishes their text and cancellation,
not their precise visual wrapping. That remains in the manual check; spoken VoiceOver and native-speaker translation
review are also not claimed by these tests.

The full gate passed with 1,773 tests, release builds of the app and Finder extension, localization, config schema,
documentation and public-safety checks. The separate full mutation sweep was still running when this change was committed;
matching its 375 current entries to the source is not a claim that the sweep passed.
