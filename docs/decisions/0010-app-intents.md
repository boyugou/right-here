# 0010: App Intents as a second entry point

Date: 2026-10-12. Status: decided; the Shortcuts side is unverified until someone runs it by hand (see below).

## Decision

The app target declares four App Intents, so the actions run from Shortcuts and Spotlight without the Finder
extension: Open in Terminal, Start AI Agent, Create New File and Copy Path, with an `AppShortcutsProvider` for
Siri and Spotlight phrases.

- Each `perform()` starts only the bundled `rh` (`Contents/Helpers/rh`) through the existing process runner, with a
  60 second limit: `rh run <action id> --origin cli -- <path>`. The argument vector is built by `IntentCommand`
  in RightHereKit, which refuses an id that is not one word and a path that is not absolute, and has tests.
- There is no free-text parameter. The folder or item is a file parameter (or, since [ADR 0030](0030-saved-folders-for-shortcuts.md),
  a Saved Folder entity); the agent and the template are entities
  picked from `rh agents --json` (enabled or found in the shell) and `rh actions --json` (the config's templates);
  the path style is an enum with one case per `PathStyle` (an exhaustive switch breaks the build when one is added).
- The result is a short dialog (`Done: <rh's summary>`); a failure throws the line in which rh says why it stopped (its
  last `error:` or `Error:` line), not all of its standard error: before that rh reports each problem in the config,
  which quotes the person's file. With no such line the text is only "rh exited with status N", so nothing of the
  config is ever shown as the answer.
- The titles, parameter names and phrases live in the String Catalog (`Localizable.xcstrings`, and
  `AppShortcuts.xcstrings` for the spoken phrases), in all thirty languages; both are resources of the app target.

## Why

Finder Sync is the one entry point that depends on a system extension, and developer forums report it failing to
load on some macOS 26 machines. An intent has no such dependency, runs wherever Shortcuts or Spotlight can send
a folder, and reuses everything `rh` already guarantees (a terminal only ever gets a folder, argv only).

## Checked

- The build emits `Contents/Resources/Metadata.appintents/extract.actionsdata` with the four actions, the
  entities, the path-style enum and the four shortcuts with their phrases, and the app bundle has the
  per-language `Localizable.strings` and `AppShortcuts.strings`.
- The argument building and result handling are unit tested (`IntentInvocationTests`).

## Not checked

- Running the intents from Shortcuts or Spotlight: that needs the Shortcuts app and, for a terminal, an Apple event
  to it, which tests and scripts must not do. Run one by hand once.
- Whether macOS shows the setup window when it starts the app only to run an intent (the scene is
  `.defaultLaunchBehavior(.presented)`). If it does, move the intents into an App Intents extension.
- No doctor row: registration with Shortcuts cannot be read without the Shortcuts app, and the presence of the
  metadata in the bundle says nothing about registration.
