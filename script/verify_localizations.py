#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Check the String Catalogs.

- Localization/languages.json lists the shipped languages; every catalog carries all of them and no other;
- the generated LocalizationKey has a case, with the right number of arguments, for every entry of the catalog and for
  nothing else, and LocalizedMessage has a constructor that takes exactly those arguments;
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

from localization_lib import (
    CATALOGS, LETTERS, ROOT, SWIFT_DIRECTORY, arity, case_name, languages, read_catalog, source_language, translation_problems,
)

KEYS_FILE = SWIFT_DIRECTORY / "LocalizationKey.generated.swift"
MESSAGES_FILE = SWIFT_DIRECTORY / "LocalizedMessage.generated.swift"


def check_manifest(problems: list[str]) -> None:
    shipped = languages()
    codes = [language.code for language in shipped]
    if len(set(codes)) != len(codes):
        problems.append("languages.json: a language is listed twice")
    if codes[0] != source_language():
        problems.append(f"languages.json: the first language must be the source language {source_language()}")
    for language in shipped:
        if language.script not in LETTERS:
            problems.append(f"languages.json: {language.code} has script {language.script}; add its letters to LETTERS in localization_lib.py")
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
            if unit is not None and unit["value"].strip():
                problems += translation_problems(key, language, unit["value"], english)


def check_generated_keys(strings: dict, problems: list[str]) -> None:
    """Reads the generated Swift back, so a generator that drops or miscounts a key cannot go unnoticed."""
    text = KEYS_FILE.read_text(encoding="utf-8")
    cases = dict(re.findall(r'case (\w+) = "([A-Za-z0-9.]+)"', text))
    keys = set(cases.values())
    for key in sorted(keys - strings.keys()):
        problems.append(f"{key}: a LocalizationKey but missing from the catalog")
    for key in sorted(strings.keys() - keys):
        problems.append(f"{key}: in the catalog but not a LocalizationKey")
    counts: dict[str, int] = {}
    for names, number in re.findall(r"case ((?:\.\w+(?:, )?)+): (\d+)\n", text):
        for name in re.findall(r"\.(\w+)", names):
            counts[name] = int(number)
    for name, key in sorted(cases.items()):
        if key not in strings:
            continue
        if name != case_name(key):
            problems.append(f"{key}: the case is called {name}, not {case_name(key)}")
        english = strings[key]["localizations"]["en"]["stringUnit"]["value"]
        try:
            expected = arity(english)
        except ValueError:
            continue
        if counts.get(name, 0) != expected:
            problems.append(f"{key}: the generated arity is {counts.get(name, 0)}, the English text takes {expected}")

    constructors: dict[str, int] = {}
    messages = MESSAGES_FILE.read_text(encoding="utf-8")
    for name in re.findall(r"public static var (\w+): LocalizedMessage", messages):
        constructors[name] = 0
    for name, parameters in re.findall(r"public static func (\w+)\(([^)]*)\) -> LocalizedMessage", messages):
        constructors[name] = len(parameters.split(","))
    for name, key in sorted(cases.items()):
        if key in strings and constructors.get(name) != counts.get(name, 0):
            problems.append(f"{key}: LocalizedMessage.{name} takes {constructors.get(name)} values, the key takes {counts.get(name, 0)}")
    for name in sorted(constructors.keys() - cases.keys()):
        problems.append(f"LocalizedMessage.{name} is not a LocalizationKey")


def main() -> int:
    if "--missing" in sys.argv:
        code = sys.argv[sys.argv.index("--missing") + 1]
        for name in CATALOGS:
            for key, entry in sorted(read_catalog(name)["strings"].items()):
                if code not in entry["localizations"]:
                    print(f"{name}\t{key}")
        return 0

    problems: list[str] = []
    check_manifest(problems)
    catalog = read_catalog("Localizable.xcstrings")
    strings = catalog["strings"]
    check_generated_keys(strings, problems)
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
