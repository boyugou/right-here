#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Mark translations as reviewed (state translated) once a review pass has read them.

    ./script/mark_reviewed.py all          every language of every catalog
    ./script/mark_reviewed.py de fr        those languages only

A review pass is a person reading their own language, or a second model holding each string to its English, its comment
and the terms of the rest of the language (ADR 0006). A translation added later is needs_review until one has read it.
"""
import sys

from localization_lib import CATALOGS, languages, read_catalog, source_language, write_catalog


def main() -> int:
    arguments = sys.argv[1:]
    shipped = [language.code for language in languages() if language.code != source_language()]
    if not arguments:
        print(__doc__, file=sys.stderr)
        return 2
    codes = shipped if arguments == ["all"] else arguments
    unknown = [code for code in codes if code not in shipped]
    if unknown:
        print(f"not a translation language in languages.json: {', '.join(unknown)}", file=sys.stderr)
        return 1
    for name in CATALOGS:
        catalog = read_catalog(name)
        marked = 0
        for entry in catalog["strings"].values():
            for code, unit in entry.get("localizations", {}).items():
                string = unit.get("stringUnit")
                if code in codes and string is not None and string["state"] == "needs_review":
                    string["state"] = "translated"
                    marked += 1
        if marked:
            write_catalog(name, catalog)
        print(f"{name}: {marked} marked reviewed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
