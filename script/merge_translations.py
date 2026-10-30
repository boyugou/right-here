#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Add translations to a String Catalog, checked.

    ./script/merge_translations.py translations.json                       into Localizable.xcstrings
    ./script/merge_translations.py translations.json --catalog InfoPlist.xcstrings      (also AppIntents.xcstrings, AppShortcuts.xcstrings)
    ./script/merge_translations.py translations.json --replace              also overwrite a translation that exists
    ./script/merge_translations.py translations.json --replace --reviewed   the texts are a native speaker's own: mark them translated, not needs_review

translations.json holds the keys to add or to complete. Every language is named by its code, never by position:

    {
      "doctor.fix.configInit": {
        "en": "Run `rh init`.",                    a new key: its English text,
        "comment": "What a translator should know.",  and the comment that goes with it
        "keep": ["general.terminal"],              optional: text every translation must contain as it is
        "translations": {"de": "`rh init` ausführen.", "fr": "Exécutez `rh init`."}
      }
    }

A translation is checked the way verify_localizations.py checks the catalog (placeholders, commands in backticks,
the script of the language, and in a right-to-left one no literal path or quoted setting, which has to be a value), and a
right-to-left one that would start with Latin text gets the right-to-left mark.
New translations are marked needs_review, or translated with --reviewed (a native speaker's correction of their own language).
Nothing is written unless every translation passes.
"""
import argparse
import sys
from pathlib import Path

from localization_lib import (
    CATALOGS, TEXT_CATALOGS, languages, read_catalog, read_json, source_language, translation_problems, with_direction_mark,
    write_catalog,
)


def merge(catalog_name: str, requested: dict, replace: bool, reviewed: bool = False) -> tuple[dict, list[str], list[str]]:
    """The catalog with the translations merged in, the problems found, and what was added."""
    catalog = read_catalog(catalog_name)
    strings = catalog["strings"]
    shipped = {language.code: language for language in languages()}
    source = source_language()
    problems: list[str] = []
    added: list[str] = []
    for key, request in sorted(requested.items()):
        entry = strings.get(key)
        english = request.get("en") or (entry["localizations"][source]["stringUnit"]["value"] if entry else None)
        if english is None:
            problems.append(f"{key}: a new key needs its English text (\"en\")")
            continue
        if entry is None:
            entry = {"extractionState": "manual", "localizations": {source: {"stringUnit": {"state": "translated", "value": english}}}}
            if request.get("comment"):
                entry["comment"] = request["comment"]
            strings[key] = entry
            added.append(f"{key} (new)")
        elif entry["localizations"][source]["stringUnit"]["value"] != english:
            problems.append(f"{key}: the English text differs from the catalog's; change the catalog first")
            continue
        for code, value in sorted(request.get("translations", {}).items()):
            language = shipped.get(code)
            if language is None or code == source:
                problems.append(f"{key}: {code} is not a translation language in languages.json")
                continue
            value = value.strip()
            read_on_screen = catalog_name in TEXT_CATALOGS
            if read_on_screen:
                value = with_direction_mark(language, key, value, english)
            problems += translation_problems(key, language, value, english, request.get("keep", []), direction=read_on_screen)
            existing = entry["localizations"].get(code, {}).get("stringUnit")
            if existing is not None and existing["value"] != value and not replace:
                problems.append(f"{key} [{code}]: already translated (use --replace to overwrite)")
                continue
            if existing is None or existing["value"] != value:
                entry["localizations"][code] = {"stringUnit": {"state": "translated" if reviewed else "needs_review", "value": value}}
                added.append(f"{key} [{code}]")
    return catalog, problems, added


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("translations", type=Path)
    parser.add_argument("--catalog", default="Localizable.xcstrings", choices=CATALOGS)
    parser.add_argument("--replace", action="store_true")
    parser.add_argument("--reviewed", action="store_true", help="the texts come from a native speaker: state translated instead of needs_review")
    arguments = parser.parse_args()
    catalog, problems, added = merge(arguments.catalog, read_json(arguments.translations), arguments.replace, arguments.reviewed)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        print(f"nothing written: {len(problems)} problems", file=sys.stderr)
        return 1
    write_catalog(arguments.catalog, catalog)
    print(f"{arguments.catalog}: {len(added)} entries added")
    return 0


if __name__ == "__main__":
    sys.exit(main())
