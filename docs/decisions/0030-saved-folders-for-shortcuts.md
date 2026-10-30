# 0030: A pinned or recent folder is a thing Shortcuts can pick

Date: 2026-10-28. Status: decided; the Shortcuts side is unverified until someone runs it by hand, as the intents themselves are
([ADR 0010](0010-app-intents.md)).

## Decision

The four App Intents take their folder a second way: a **Saved Folder**, picked from a list of the pinned folders and then the
recent ones, instead of a folder handed over as a file.

- `SavedFolderEntity` is an `AppEntity` whose id is the folder's absolute path, shown by its own name with the path under it
  (`~` for the home folder) and a pin or a clock. Its query (`SavedFolderQuery`) lists what `rh pins --json` and
  `rh recents --json` say, the pinned ones first and a recent one left out when it is pinned (`IntentCatalog.folders`, tested).
- Each intent's file parameter (Folder, or File or Folder) becomes optional, and a Saved Folder parameter stands beside it. The
  saved one wins when both are set: it was picked by name. With neither set the action asks for a saved folder
  (`needsValueError`, with "Choose a folder, or one of your saved folders." from the String Catalog), as Shortcuts asked for the
  file while that parameter was required; so a phrase said to Siri or Spotlight still ends in a question, not a failure. An
  intent still only ever starts the bundled `rh` with the path as an argv entry after `--` (`IntentCommand`); a saved folder's id
  goes the same way as a file's path.
- A shortcut made with a saved folder keeps naming that folder after it is unpinned or leaves the recent ones: the query answers
  for any identifier that is an absolute path of a folder that exists, so the shortcut goes on working, with a plain folder
  instead of a pin or a clock.
- No parameter summary: the intents had none, and one would need a sentence in thirty languages for each way of each intent. The
  action's card shows its title and its parameters.
- Not indexed for Spotlight (`IndexedEntity`): the list is read from `rh` when Shortcuts asks, and Spotlight's index would be a
  second copy of the pins and recents to keep right. The entity can be given that later without changing its id.

## Why

A shortcut that always opens the same project had to carry the folder as a file, chosen in
a file picker; the window, `rh pins` and the MCP tool `right_here_bookmarks` already know the person's folders. The entity makes
them the same list in Shortcuts.

## Checked

- `swift test`: the list's order and the shown path, also with a combining mark after the slash (`IntentInvocationTests`).
- An independent review of the first version found the plain folder, the question in place of a failure and the scalar-level
  prefix test; it measured that a `%` in a folder's name comes through `LocalizedStringResource(stringLiteral:)` unchanged.
- The app's build writes the entity, its query and the new parameter of each intent into
  `Contents/Resources/Metadata.appintents/extract.actionsdata`, and `verify_localizations.py` finds every new key read by the app.

## Not checked

- Picking a saved folder in the Shortcuts app and running the action, and what the action's card looks like with two optional
  parameters: `docs/development/MANUAL_CHECKS.md`, section 5, step 13.
