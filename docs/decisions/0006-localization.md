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

## A language of the config's own (2026-10-22)

A person could not find where to change the language: it was the system's, and only System Settings changed it. `general.language` now
names one of the thirty languages (`Config.language`; absent, the system's). The Finder menu, the setup window, the failure alerts, the
names of the Quick Actions, the files made from Finder and the dialogs of the Shortcuts actions follow it (`Config.localizer`); the
command line and the MCP server stay in English. The Overview of the window has a menu for it, and an AI assistant may change it by itself
(`ConfigTrust`): a language starts nothing.

Why a key and not macOS's own per-app language (System Settings › General › Language & Region › Applications): that setting writes
`AppleLanguages` into the app's own preferences, and the Finder extension and `rh` (started by the runner script and by the Quick Actions)
are other processes, with other preferences or none. So we expect the window to change and the menu not to. This is reasoned, not measured:
`docs/development/MANUAL_CHECKS.md` section 9 has the step that measures it. The key is read by every process from the one config file, so
they agree whatever that measurement says.

Each process reads it where it has the config: the extension when it builds a menu, `rh run` for a click from Finder, the window through a
`localizer` value of the SwiftUI environment set at its root (with the layout direction and the locale, so an Arabic config mirrors the
window on an English Mac), and the doctor when it works out the names the Quick Actions must have. A change of the language renames the
Quick Actions, and the window writes them again at once (ADR 0026, stage 10). What macOS shows from the app's bundle (the permission texts
of `InfoPlist.strings`, the names of the App Shortcuts) stays in the system language: macOS reads those, not Right Here.

## Why an action did nothing, in the person's language (2026-11-03)

The alert after a click in Finder had its title in the person's language and its body in English: the body was the English of the
error, so a German Mac that clicked Copy Repository Link on a commit that was not pushed read why in English. Every sentence a refusal
can say is now a message of the catalog (`refusal.*`, with the doctor's own sentence where one says the same), and `PlanError` and
`ExecutionError` are `LocalizedFailure`s: each gives its sentences, and `Localizer.describe` writes them in a language. The alert and
the reasons the window gives for an action that cannot start use it; the command line and the MCP server print the same sentences in
English (`localizedDescription`), as before. The Shortcuts actions start `rh run --json`, whose failure carries the sentences as codes
and values (`messages`, beside the English `error`), and the app writes them in its language. A text of the catalog is never put together from
pieces of a sentence: a refusal with more to say is several whole sentences, written one after the other as the language writes them
(no space between two in Chinese and Japanese). A failure's values (a path, a name, what git said) are escaped once, where the failure
gives them to a person (`LocalizedFailure.shownSentences`): their control and invisible characters as escapes, as the English was, except the
line breaks of what a program wrote; they are isolated in a right-to-left sentence. A notice that is no failure (a worktree removed, an app
added) shows a name as it is, with the marks it has.

The setup window's notices go the same way (`SetupNotice.failure`): an Install or Repair that stopped says its step's sentence (the window
writes its first letter as a capital, since a step's detail starts in lower case beside the step's name), a config text the Config page
would save that does not read, a config the page cannot read, a file that is read-only, a lock that cannot be taken and a worktree git would
not remove are sentences of the catalog (`config.*`, `setup.*`), and so are the reasons Install or Repair does not start (a download macOS
has not moved, a disk image, the Trash, another setup that holds the turn: `install.*`) and the details of the steps it could not do. The
window's Undo after a change made by hand, and a proposal that is no longer waiting, say the window's own sentences (`app.undoRefused`,
`app.proposalGone`), not the command line's advice. What stays English: what a program, git or the config parser wrote (it is a value of
the sentence, and so is the exit status a program that said nothing ended with), the step of a plan that failed (its heading), the hint
Right Here adds to git's refusal to remove a worktree with work in it (it names `--force`), the config check's own words inside a setup
step's sentence, and the errors only the command line and an AI assistant meet (making a worktree, an undo by an assistant, looking at a
proposal, config sync).
A `LocalizedMessage` cannot be interpolated into a string (`"\(message)"` does not compile), so a sentence cannot slip into the English
as its structure.

Alternatives: translating the English text at the alert by looking it up (a sentence with a value is not found, and every change of wording
breaks the lookup); keeping the body English and saying so (ADR 0033 did, which contradicted this record's first section).

## Why compile to Swift instead of using bundles

`rh` ships inside the app at `Contents/Helpers/rh`. A SwiftPM resource bundle is looked up next to the
executable, so the first `Bundle.module` access in that binary would crash. A compiled table has no
lookup to fail, works the same in the extension, the app, the CLI and the tests, and keeps the catalog
format that translation tools (Xcode, Weblate) understand.

## Status of the translations

The initial translations were produced by an AI and marked `needs_review`, which most still are. They are
usable, short UI strings, but they are awaiting native-speaker review. Adding a string
means adding a catalog entry with its English text and a translation in every language; the verifier rejects a
partial language.

A second pass by AI (by group of languages, reporting only definite problems, each suggestion judged
before it was applied) fixed, among others: "resume" translated as "restart" or "repeat",
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

A second review pass (2026-11-08) read what came after the first: the 110 strings added since 1.0.0 (most of them the refusals, the
sentences that say why an action did nothing) and the Shortcuts, App Shortcuts and Info.plist strings, 133 in each language. One model
per language held each string to its English, its comment, the terms of the language's other strings and Apple's own words read from
this Mac's system files, and changed only what was definitely wrong: 148 corrections in 29 languages, each checked by
`merge_translations.py`. Among them: a lock that "cannot be downloaded" (Greek) or "fetched" (Korean); "shell" left in English
(Malay) and "commit" written two ways in one sentence (Hebrew); "an empty file name" for an unused one (Bengali, Hindi); kilobytes
as Apple writes them (French "ko", Russian and Ukrainian "КБ"); a permission prompt in another register than the rest of the
language (Hebrew) or without the capital of the polite «Ваш» (Russian); Apple's own name for Command Line Tools where its installer dialog uses one (Simplified Chinese, Polish); and terms that
differed from the rest of the language. The English lost Launchpad, which macOS 26 replaced with Apps (`doctor.fix.appCopies` now
names Spotlight alone). Every translation is now marked reviewed (`translated`); `script/mark_reviewed.py` marks a language after a
pass, and `merge_translations.py` still adds a new translation as `needs_review`. A native speaker's reading is still welcome.

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

## The doctor says its checks as messages

`rh doctor`, the MCP tool `right_here_doctor` and the setup window show the same checks, and they used to share
sentences that were English text built in code, so the window could translate the titles only. A check is now a `CheckID`
(an enum: one case for each fixed check and one for each enabled agent), a status, and what it says: `detail`, `notes`
(more lines under it, such as the per-machine overlay the config is merged with) and `fix`, each a `LocalizedMessage`.
Apart from the two probes (below), nothing in the doctor writes an English sentence: the English wording is the catalog's
English text and `LocalizedMessage.english()` is the one place it is read, for the command line and the MCP server (one renderer,
`DoctorCheck.englishLines`; the MCP server passes a function that fences what a check quotes from the config). The
setup window renders the same messages with `Localizer.render` in the system language and titles each row from
`CheckID.titleKey`; an agent's row is titled with the agent's own name.

`rh doctor --json` carries each message as `{"code": "doctor.services.differ", "args": ["3", "1", "0"], "text": "..."}`:
a program acts on the code and the values, a person or an AI agent reads the text.

What is translated: what a person meets on a first run and afterwards, that is the config file (missing, warnings, an
overlay, a symlink), the default terminal and editor (the app a click opens, none installed, the configured one not
installed), agents (found, missing), the Claude Code link, the runner script (missing, stale, pointing nowhere), the
Services (missing, stale), the `rh` link, the Finder extension (not registered, switched off, registered twice, ok), the
last action and every config sync row. The fix line under a config with errors and under an agent that cannot start is
translated too. Thirty languages each, checked like every other string.

What stays English in every language, on purpose: the chain probe (`finder.chain`), which a person runs from a terminal, and
what the launch probe (`finder.launch`) says of a rarer failure (no reply, the command ran in another folder, a step that
failed, no report from the extension), which is what the extension or the terminal reported; the reasons under an empty Finder
menu, which are what `rh menu --explain` prints; and text that comes from outside the catalog and is shown as it is through
`doctor.verbatim`: the parser's description of the first error of a config (it sits above its translated fix line), a bare path,
and the config lines the launch-settings row quotes. The launch probe was English as a whole until 2026-11-12: the setup window's
Test Terminal Start runs it, and a person on a German Mac read "Click Allow, then run this again" in English. A start that ran, the
permission prompt waiting or refused, and a terminal that cannot run commands are the catalog's now (`doctor.probe.*`,
`doctor.fix.probe*`). The relative time of the last action is formatted when the doctor runs, in the locale of that process; the
place a click came from has its own sentence for each place since 1.2.19 (`doctor.activity.*`). The parser's sentences are not Right Here's own words, and translating them would need
the same split in that layer. The planner's reason an agent cannot start was in this list until 2026-11-03; it is a sentence of the
catalog now. The two reasons the default terminal or editor row can give
(nothing of the role is installed, the configured app is not) are the exception: the catalog has them word for word as the
planner says them (`PlanError`), which a test holds, so `rh run`, `rh actions` and the window say one sentence. A config
that names an unknown app, or a terminal as the editor, is refused when it is read and the default is used instead, so no
"unknown app" sentence exists in the catalog.

A path or a command quoted in a right-to-left sentence is a left-to-right value, and the sentence around it reorders it:
rendering the Arabic window showed `~/.config/...` and `/Applications/...` with their leading characters at the wrong end.
The window therefore renders doctor lines with `render(_:isolatingValues: true)`, which puts each value of a
right-to-left language in a Unicode isolate (U+2068 ... U+2069); a text that is only its value is left as it is. It is an
option, off by default, because the menu, the alerts and the names of Services and files go through the same function
and must not carry invisible marks. A command between backticks in the catalog's own text is not a value, so it cannot be
isolated that way; one that ends in a bracket (`rh config sync enable --folder <folder>`) had its closing bracket drawn
mirrored and on the wrong side, so a right-to-left translation puts a left-to-right mark after it, which
`merge_translations.py` adds, `verify_localizations.py` demands and a test holds.

The same goes for a path, or a quoted, assigned or bracketed word, written in the sentence itself: the fix line of "rh on
your PATH" had `~/.local/bin` in its text and the window drew it `local/bin./~` in Arabic, Persian, Hebrew and Urdu
(found by a review), and `launcher = "link"` had its closing quote at the wrong end. These are values of the message
(`doctorFixCliPath("~/.local/bin")`, `doctorFixAgentLauncher("launcher = \"link\"", "\"desktop\"")`), and
`verify_localizations.py` and `merge_translations.py` refuse such a literal in a right-to-left translation of a text the
window shows (the lint finds twenty such words in sixteen translations of the old catalog, and none in the new one). A test lays every text
out with CoreText, as the window does, and finds a path that is still drawn out of order, and a second one does the same
for every command between backticks (none was out of order, so commands needed no treatment beyond the mark for a
bracket). Checked once in the renders of `script/preview_setup.sh --gallery` (the window's own SwiftUI text, drawn by
`ImageRenderer`) in Arabic, Persian, Hebrew and Urdu, with the picture read back by on-device text recognition: the value
`~/.local/bin` reads `~/.local/bin`, `launcher = "link"` and `agents = ["claude"]` come out whole, and the same path
written into the sentence reads `local/bin./~`. That is the renderer, not a real window; the real one is in
`docs/development/MANUAL_CHECKS.md`, section 3.

Alternatives: the doctor takes a `Localizer` and returns strings (every consumer must choose a language, the JSON has
no codes, and the English the tests pin would depend on the language); leaving the sentences English and translating
the titles only (what there was: a window half in one language and half in another). A test holds every doctor sentence
of the catalog to be said somewhere in the doctor, so a sentence that is dead, or one whose use was lost, is found.

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
