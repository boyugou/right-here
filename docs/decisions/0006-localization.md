# 0006: Thirty languages from a String Catalog, compiled into Swift

Date: 2026-10-11. Status: accepted.

## Decision

`Localization/Localizable.xcstrings` is the source of truth: 43 strings in the thirty languages of the
owner's other product (English plus Arabic, Bengali, German, Greek, Spanish, Persian, French, Hebrew,
Hindi, Indonesian, Italian, Japanese, Korean, Marathi, Malay, Dutch, Polish, Brazilian Portuguese,
Romanian, Russian, Tamil, Telugu, Thai, Turkish, Ukrainian, Urdu, Vietnamese, Simplified and
Traditional Chinese). `script/compile_localizations.py` turns it into
`Sources/RightHereCore/Localization/Localizations.generated.swift`; `script/verify_localizations.py`
checks completeness, placeholders and that the generated file is current.

Human-facing surfaces follow the system language: the Finder menu, the app, alerts, and files created
from Finder (the default name "untitled" becomes "unbenannt" and so on). The command line and the MCP
server stay in English so their output is stable for scripts and agents; `rh menu --language de`
previews another language.

## Why compile to Swift instead of using bundles

`rh` ships inside the app at `Contents/Helpers/rh`. A SwiftPM resource bundle is looked up next to the
executable, so the first `Bundle.module` access in that binary would crash. A compiled table has no
lookup to fail, works the same in the extension, the app, the CLI and the tests, and keeps the catalog
format that translation tools (Xcode, Weblate) understand.

## Status of the translations

The initial translations were produced by an AI and every one is marked `needs_review`. They are
usable, short UI strings, but they need native-speaker review before a public release. Adding a string
means adding a `LocalizationKey`, an English entry and all thirty translations; the verifier rejects a
partial language.

A second AI pass (one reviewer per group of languages, instructed to report only definite problems, each
suggestion then judged before it was applied) fixed, among others: "resume" translated as "restart" or "repeat",
verbless agent labels in Korean, Japanese and Marathi, mixed imperative and infinitive in Dutch, Portuguese menus
that were not in Apple's title case, an alert title with no object, and Latin/CJK spacing in Chinese. Two design
changes came out of it: the built-in templates have whole "New …" phrases (`menu.newText`, `menu.newMarkdown`),
because "New %@" plus a capitalised title put a capital mid-phrase in seven languages; and right-to-left strings
that begin with a Latin name or a placeholder start with a right-to-left mark, so AppKit lays them out right to
left (never the string that becomes a file name). The setup window can be checked for layout, including mirroring,
with `script/preview_setup.sh`. The Settings path the permission alert quotes (System Settings › Privacy &
Security › Automation) is checked against macOS's own wording, which ships in System Settings and its
Privacy & Security extension: `script/verify_macos_wording.py` reads it and found real mismatches (Arabic,
Greek, Hebrew, Indonesian, Malay, Portuguese, Romanian, Thai, Vietnamese, Simplified Chinese), all fixed; for
Bengali, Persian, Marathi, Tamil, Telugu and Urdu, which macOS does not ship, the alert quotes the English path
because that is what Settings shows. The same script holds "Open With" and "Show in Finder" to Finder's own
wording in the 23 languages Finder ships, which changed Arabic, Hebrew, Hindi, Polish, Russian, Turkish,
Ukrainian and Traditional Chinese for Open With, and several for Show in Finder; Thai and Indonesian now say
"route" and "jalur" for a path as Finder does, and Romanian uses the formal register macOS uses. Run it after a
macOS update. What a native speaker would change is still open.

## Names of apps

Terminals and editors are shown by the name the system gives them in the person's language
(`FileManager.displayName`), so Terminal appears as "终端" or "ターミナル" where macOS says so.
