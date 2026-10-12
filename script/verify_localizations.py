#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Check the String Catalog.

- every LocalizationKey in Swift has an entry, and the catalog has no stray entries;
- every entry carries all shipped languages, with no empty value;
- placeholders (%@, %1$@) match the English text in every language;
- the generated Swift file is up to date;
- Localization/InfoPlist.xcstrings (the permission-prompt text in the app and the extension) carries
  the same languages.

    ./script/verify_localizations.py
    ./script/verify_localizations.py --missing de     list keys without a translation in a language
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Localization" / "Localizable.xcstrings"
INFO_PLIST_CATALOG = ROOT / "Localization" / "InfoPlist.xcstrings"
KEYS_FILE = ROOT / "Sources" / "RightHereCore" / "Localization" / "LocalizationKey.swift"
SHIPPED = [
    "en", "ar", "bn", "de", "el", "es", "fa", "fr", "he", "hi", "id", "it", "ja", "ko", "mr", "ms", "nl", "pl",
    "pt-BR", "ro", "ru", "ta", "te", "th", "tr", "uk", "ur", "vi", "zh-Hans", "zh-Hant",
]
PLACEHOLDER = re.compile(r"%(?:\d+\$)?@")


def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog["strings"]
    swift_keys = set(re.findall(r'= "([A-Za-z.]+)"', KEYS_FILE.read_text(encoding="utf-8")))
    problems: list[str] = []

    for key in sorted(swift_keys - strings.keys()):
        problems.append(f"{key}: used in Swift but missing from the catalog")
    for key in sorted(strings.keys() - swift_keys):
        problems.append(f"{key}: in the catalog but not a LocalizationKey")

    missing_for = sys.argv[sys.argv.index("--missing") + 1] if "--missing" in sys.argv else None
    for key, entry in sorted(strings.items()):
        localizations = entry["localizations"]
        english = localizations["en"]["stringUnit"]["value"]
        for language in SHIPPED:
            unit = localizations.get(language, {}).get("stringUnit")
            if unit is None or not unit["value"].strip():
                problems.append(f"{key}: no {language} translation")
                continue
            if sorted(PLACEHOLDER.findall(unit["value"])) != sorted(PLACEHOLDER.findall(english)):
                problems.append(f"{key} [{language}]: placeholders differ from English")
        extra = set(localizations) - set(SHIPPED)
        if extra:
            problems.append(f"{key}: unexpected languages {sorted(extra)}")
        if missing_for:
            if missing_for not in localizations:
                print(key)

    if missing_for:
        return 0

    info = json.loads(INFO_PLIST_CATALOG.read_text(encoding="utf-8"))["strings"]
    if "NSAppleEventsUsageDescription" not in info:
        problems.append("InfoPlist.xcstrings: NSAppleEventsUsageDescription is missing")
    for key, entry in sorted(info.items()):
        for language in SHIPPED:
            unit = entry["localizations"].get(language, {}).get("stringUnit")
            if unit is None or not unit["value"].strip():
                problems.append(f"InfoPlist.xcstrings {key}: no {language} translation")
        extra = set(entry["localizations"]) - set(SHIPPED)
        if extra:
            problems.append(f"InfoPlist.xcstrings {key}: unexpected languages {sorted(extra)}")

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
    print(f"ok: {len(strings)} strings x {len(SHIPPED)} languages ({unreviewed} awaiting native-speaker review)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
