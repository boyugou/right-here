# 0035: Sidebar, View menu and shortcuts share their order

Date: 2026-11-15. Status: implemented. Updates [0029](0029-feedback-and-keyboard-navigation.md) and
[0033](0033-current-design-language.md).

## Problem

The visual redesign grouped the sidebar by purpose but kept the earlier View-menu order and numbered shortcuts. The third,
fourth and sixth visible sections were AI Assistants, Folders and Checks, while Command-3, Command-4 and Command-6 opened Checks,
AI Assistants and Folders. A person following the sidebar's order therefore reached a different page. The dedicated design
review identified this inconsistency in the implementation, and recommended correcting it without redesigning the pages.

## Decision

`SetupTab.navigationGroups` supplies both the sidebar and the View menu. Their separators mark the same groups. Numbered
shortcuts derive from the flattened groups rather than from a separate switch statement:

| Shortcut | Section |
|---|---|
| Command-1 | Overview |
| Command-2 | Finder menu |
| Command-3 | AI Assistants |
| Command-4 | Folders |
| Command-5 | Worktrees |
| Command-6 | Checks |

The sidebar's layout, page selection behavior and stable section identifiers remain the same. Command-F still applies only
to a searchable Folders page, and Command-R still refreshes. No old numeric aliases are retained: the project has no existing
users, and an alias would conflict with the section that now belongs at that number.

## Alternatives

Restoring the old sidebar order would undo the grouping chosen in ADR 0033. Keeping the old shortcuts would require learning
two different orders. Updating three separate lists would fix today's mismatch while leaving the same cause in place.

## Verification

`SetupTabTests` pins the visible groups, checks that every section appears exactly once, and verifies the six key assignments.
The focused suite passed. Native interaction on the machine reporting macOS 27.2 (26B123) used the production views and model
with fake system facts, a runner that executed no processes, and saved folders in a temporary home. The View menu's accessible
items followed the sidebar order. Each of Command-1 through Command-6 selected its corresponding row and page heading.
Command-4 followed immediately by Command-F focused search; returning from AI Assistants with the same sequence selected the
existing query for replacement. Command-6 reached Checks. The review app and its temporary data were removed. This does not
claim full keyboard Tab traversal or spoken VoiceOver, which remain in the manual checklist.
