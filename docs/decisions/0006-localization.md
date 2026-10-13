# 0006: Thirty languages from a String Catalog, compiled into Swift

Date: 2026-10-11. Status: accepted.

## Decision

`Localization/Localizable.xcstrings` is the source of truth for the strings and `Localization/languages.json` for the
languages: thirty of them (English, Arabic, Bengali, German, Greek, Spanish, Persian, French, Hebrew, Hindi, Indonesian,
Italian, Japanese, Korean, Marathi, Malay, Dutch, Polish, Brazilian Portuguese, Romanian, Russian, Tamil, Telugu, Thai,
Turkish, Ukrainian, Urdu, Vietnamese, Simplified and Traditional Chinese). The manifest gives each language its code, its
English name, its script and whether it is written right to left. The compiler, the verifier and the tests all read it, so
a language is listed in one place.

`script/compile_localizations.py` turns the catalog into three files in `Sources/RightHereCore/Localization/`: the table
of texts (`Localizations.generated.swift`), `LocalizationKey` (one case per key, named from the key, with the number of
values its English text takes) and `LocalizedMessage.generated.swift` (a typed constructor per key).
`script/verify_localizations.py` checks completeness against the manifest, placeholders, that the commands between
backticks survive, the script of each language, the right-to-left marks, that the generated Swift is current and that it
agrees with the catalog (every key has its case, with the right arity, and a constructor with that many parameters).

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
usable, short UI strings, but they are awaiting native-speaker review. Adding a string
means adding a catalog entry with its English text and a translation in every language; the verifier rejects a
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

## Typed messages

A sentence with values in it is a `LocalizedMessage`: a key and the values, not yet written in a language.
`.menuOpenIn("Ghostty")` makes one; the constructor is generated from the catalog, so a wrong number of values does not
compile. `Localizer.render` writes it in the language of the localizer and `english()` in English. A text that takes
several values numbers its placeholders (`%1$@ in %2$@`), because a translation may need another order; the verifier
rejects two bare `%@`. A key that takes no values is read with `Localizer.string(.key)`, which is also how the
built-in titles (agent options, presets, new-file templates) are found by their key; a test holds each of those keys to
take no values.

Alternatives considered for the values: a `Localizer` method per key with named parameters (generated names are no
better than `argument1`, and the doctor needs a value it can hand over before the language is chosen, which a method
cannot be), and a variadic `string(key, args...)` (what there was: untyped, and a wrong count made `String(format:)`
read memory that is not there).

## Adding a string or a language

A string: add the entry (English text, a comment for the translator) and its translations, compile, verify.
`script/merge_translations.py` takes a JSON file of keys with `{language code: text}` dictionaries, checks each text
like the verifier does, adds the right-to-left mark where a right-to-left text would start with Latin letters, marks
the new texts `needs_review` and writes nothing unless every text passes. A language: add it to `languages.json`,
list what is missing with `script/verify_localizations.py --missing <code>` (all three catalogs), translate, merge,
compile, verify. `CONTRIBUTING.md` has the steps.

## Names of apps

Terminals and editors are shown by the name the system gives them in the person's language
(`FileManager.displayName`), so Terminal appears as "终端" or "ターミナル" where macOS says so.
