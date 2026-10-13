#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Check the String Catalogs.

- Localization/languages.json lists the shipped languages; every catalog carries all of them and no other;
- every LocalizationKey in Swift has an entry, and the catalog has no stray entries;
- placeholders (%@, %1$@) match the English text in every language, and a text with several of them numbers them
  so that a translation can reorder them;
- the commands between backticks are the same in every language (the setup window shows them as code);
- a translation is written in the script of its language, and a right-to-left one that would start with Latin text
  starts with a right-to-left mark instead;
- the generated Swift is up to date;
- Localization/AppShortcuts.xcstrings (the spoken phrases of the Shortcuts actions) keeps the ${applicationName}
  placeholder;
- Localization/InfoPlist.xcstrings (the permission-prompt text in the app and the extension) is complete too.

    ./script/verify_localizations.py
    ./script/verify_localizations.py --missing de     list what a language still lacks, in every catalog
"""
import re
import subprocess
import sys
import unicodedata

from localization_lib import CODE_SPAN, LOCALIZATION, PLACEHOLDER, ROOT, SWIFT_DIRECTORY, arity, languages, placeholders, read_catalog, read_json, source_language

KEYS_FILE = SWIFT_DIRECTORY / "LocalizationKey.swift"
RIGHT_TO_LEFT_MARK = "‏"
# Keys whose text becomes a file name: no direction mark, no path separator.
FILE_NAME_KEYS = {"newFile.baseName"}

# The Unicode names (their first word) of the letters each script is written with. A translation with letters but none
# of them in its script was pasted against the wrong language (one catalog entry once got its neighbour's text); a value
# with no letters at all (a bare placeholder) and one equal to English ("OK") are fine.
LETTERS = {
    "Latn": {"LATIN"}, "Arab": {"ARABIC"}, "Hebr": {"HEBREW"}, "Beng": {"BENGALI"}, "Deva": {"DEVANAGARI"},
    "Taml": {"TAMIL"}, "Telu": {"TELUGU"}, "Thai": {"THAI"}, "Grek": {"GREEK"}, "Cyrl": {"CYRILLIC"}, "Kore": {"HANGUL"},
    "Jpan": {"CJK", "HIRAGANA", "KATAKANA"}, "Hans": {"CJK", "HIRAGANA", "KATAKANA"}, "Hant": {"CJK", "HIRAGANA", "KATAKANA"},
}


def scripts_in(text: str) -> set[str]:
    # Ordinal and micro signs (º ª µ) are Latin letters whose Unicode names do not begin with the script.
    return {"LATIN" if unicodedata.name(c, "").split()[0] in ("MASCULINE", "FEMININE", "MICRO") else unicodedata.name(c, "").split()[0]
            for c in text if c.isalpha()}


def wrong_script(script: str, value: str, english: str) -> bool:
    found = scripts_in(value)
    if not found or value == english:
        return False
    if script == "Latn":
        return bool(found - LETTERS["Latn"])
    return not (found & LETTERS[script])


def starts_left_to_right(value: str) -> bool:
    """Whether the first letter that has a direction, once placeholders are filled in with Latin text, reads left to right."""
    for character in PLACEHOLDER.sub("X", value):
        direction = unicodedata.bidirectional(character)
        if direction == "L":
            return True
        if direction in ("R", "AL"):
            return False
    return False


def check_manifest(problems: list[str]) -> None:
    shipped = languages()
    codes = [language.code for language in shipped]
    if len(set(codes)) != len(codes):
        problems.append("languages.json: a language is listed twice")
    if codes[0] != source_language():
        problems.append(f"languages.json: the first language must be the source language {source_language()}")
    for language in shipped:
        if language.script not in LETTERS:
            problems.append(f"languages.json: {language.code} has script {language.script}; add its letters to LETTERS in verify_localizations.py")
        if (language.script in ("Arab", "Hebr")) != language.rtl:
            problems.append(f"languages.json: {language.code} is written in {language.script}, so \"rtl\" should be {language.script in ('Arab', 'Hebr')}")


def check_languages(name: str, catalog: dict, problems: list[str]) -> None:
    codes = {language.code for language in languages()}
    if catalog.get("sourceLanguage") != source_language():
        problems.append(f"{name}: sourceLanguage is {catalog.get('sourceLanguage')}, not {source_language()}")
    for key, entry in sorted(catalog["strings"].items()):
        have = entry.get("localizations", {})
        for language in languages():
            unit = have.get(language.code, {}).get("stringUnit")
            if unit is None or not unit["value"].strip():
                problems.append(f"{name} {key}: no {language.code} translation")
        extra = set(have) - codes
        if extra:
            problems.append(f"{name} {key}: unexpected languages {sorted(extra)}")


def check_texts(strings: dict, problems: list[str]) -> None:
    for key, entry in sorted(strings.items()):
        localizations = entry["localizations"]
        english = localizations["en"]["stringUnit"]["value"]
        try:
            arity(english)
        except ValueError as error:
            problems.append(f"{key}: the English text {error}")
        for language in languages():
            unit = localizations.get(language.code, {}).get("stringUnit")
            if unit is None or not unit["value"].strip():
                continue
            value = unit["value"]
            where = f"{key} [{language.code}]"
            if sorted(placeholders(value)) != sorted(placeholders(english)):
                problems.append(f"{where}: placeholders differ from English")
            if "%" in PLACEHOLDER.sub("", value):
                problems.append(f"{where}: a % that is not a placeholder")
            if value.count("`") % 2 or sorted(CODE_SPAN.findall(value)) != sorted(CODE_SPAN.findall(english)):
                problems.append(f"{where}: the text between backticks differs from English: {value!r}")
            if wrong_script(language.script, value, english):
                problems.append(f"{where}: not written in the script of {language.code}: {value!r}")
            if key in FILE_NAME_KEYS:
                if RIGHT_TO_LEFT_MARK in value or "/" in value or ":" in value:
                    problems.append(f"{where}: becomes a file name, so no direction mark, slash or colon: {value!r}")
            elif language.rtl and starts_left_to_right(value):
                problems.append(f"{where}: starts with Latin text and no right-to-left mark: {value!r}")


def main() -> int:
    if "--missing" in sys.argv:
        code = sys.argv[sys.argv.index("--missing") + 1]
        for name in ("Localizable.xcstrings", "InfoPlist.xcstrings", "AppShortcuts.xcstrings"):
            for key, entry in sorted(read_catalog(name)["strings"].items()):
                if code not in entry["localizations"]:
                    print(f"{name}\t{key}")
        return 0

    problems: list[str] = []
    check_manifest(problems)
    catalog = read_catalog("Localizable.xcstrings")
    strings = catalog["strings"]
    swift_keys = set(re.findall(r'= "([A-Za-z.]+)"', KEYS_FILE.read_text(encoding="utf-8")))
    for key in sorted(swift_keys - strings.keys()):
        problems.append(f"{key}: used in Swift but missing from the catalog")
    for key in sorted(strings.keys() - swift_keys):
        problems.append(f"{key}: in the catalog but not a LocalizationKey")

    check_languages("Localizable.xcstrings", catalog, problems)
    check_texts(strings, problems)

    info = read_catalog("InfoPlist.xcstrings")
    if "NSAppleEventsUsageDescription" not in info["strings"]:
        problems.append("InfoPlist.xcstrings: NSAppleEventsUsageDescription is missing")
    check_languages("InfoPlist.xcstrings", info, problems)

    # The spoken phrases of the Shortcuts/Spotlight actions: every language, and the app-name placeholder in each.
    shortcuts = read_catalog("AppShortcuts.xcstrings")
    check_languages("AppShortcuts.xcstrings", shortcuts, problems)
    for key, entry in sorted(shortcuts["strings"].items()):
        for language in languages():
            unit = entry["localizations"].get(language.code, {}).get("stringUnit")
            if unit is not None and "${applicationName}" not in unit["value"]:
                problems.append(f"AppShortcuts.xcstrings {key} [{language.code}]: ${{applicationName}} is missing")

    stale = subprocess.run([sys.executable, str(ROOT / "script" / "compile_localizations.py"), "--check"], capture_output=True, text=True)
    if stale.returncode != 0:
        problems.append(stale.stderr.strip())

    unreviewed = sum(
        1 for entry in strings.values() for unit in (loc["stringUnit"] for loc in entry["localizations"].values())
        if unit["state"] == "needs_review"
    )
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"ok: {len(strings)} strings x {len(languages())} languages ({unreviewed} awaiting native-speaker review)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
