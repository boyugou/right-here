#!/usr/bin/env python3
"""Check the Settings path quoted by the permission alert against macOS's own wording on this Mac.

The alert tells the person where to allow the control: System Settings > Privacy & Security > Automation.
macOS ships those names in its own languages (inside System Settings and its Privacy & Security extension),
so this reads them and checks each translation of `alert.permissionMessage` and `alert.openSettings` uses the
same words. Languages macOS does not ship (Bengali, Persian, Marathi, Tamil, Telugu, Urdu) show an English
Settings, so their alert must quote the English path.

It depends on the macOS version it runs on, so it is not part of verify_all.sh; run it after a macOS update:

    ./script/verify_macos_wording.py
"""
import json
import plistlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PANE = Path("/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/Resources")
SETTINGS = Path("/System/Applications/System Settings.app/Contents/Resources")
ALIASES = {"pt-BR": ["pt_BR"], "zh-Hans": ["zh_CN"], "zh-Hant": ["zh_TW", "zh_HK"]}
ENGLISH_PATH = "System Settings › Privacy & Security › Automation"
# Languages that inflect the app's name inside a sentence (a case ending), so the dictionary form is not
# found as such. Each form below is the name as the sentence or the button correctly writes it.
INFLECTED = {
    "el": ["Ρυθμίσεων συστήματος"],
    "pl": ["Ustawieniach systemowych"],
    "ru": ["Системных настройках"],
    "uk": ["Системних параметрах"],
}


def normalize(text: str) -> str:
    return text.replace("­", "").replace(" ", " ").replace("‏", "")


def lookup(table: dict, language: str, key: str):
    for code in [language] + ALIASES.get(language, []):
        for candidate in (code, code.replace("-", "_")):
            if key in table.get(candidate, {}):
                return table[candidate][key]
    return None


def main() -> int:
    try:
        pane_info = plistlib.loads((PANE / "InfoPlist.loctable").read_bytes())
        pane_loc = plistlib.loads((PANE / "Localizable.loctable").read_bytes())
        settings = plistlib.loads((SETTINGS / "InfoPlist.loctable").read_bytes())
    except OSError as error:
        print(f"cannot read macOS's resources: {error}", file=sys.stderr)
        return 2
    strings = json.loads((ROOT / "Localization" / "Localizable.xcstrings").read_text(encoding="utf-8"))["strings"]
    message = strings["alert.permissionMessage"]["localizations"]
    button = strings["alert.openSettings"]["localizations"]
    problems = []
    for language in sorted(message):
        if language == "en":
            continue
        text = normalize(message[language]["stringUnit"]["value"])
        names = (
            lookup(settings, language, "CFBundleDisplayName") or lookup(settings, language, "CFBundleName"),
            lookup(pane_info, language, "CFBundleDisplayName"),
            lookup(pane_loc, language, "AUTOMATION"),
        )
        if not all(names):
            if ENGLISH_PATH not in text:
                problems.append(f"{language}: macOS does not ship this language, so the alert should quote the English path")
            continue
        def uses(name: str, where: str) -> bool:
            return normalize(name) in where or any(form in where for form in INFLECTED.get(language, []))
        for label, name in zip(("System Settings", "Privacy & Security", "Automation"), names):
            if not uses(name, text):
                problems.append(f"{language}: the alert does not use macOS's word for {label}: {name}")
        if not uses(names[0], normalize(button[language]["stringUnit"]["value"])):
            problems.append(f"{language}: alert.openSettings does not use macOS's name for the app: {names[0]}")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"ok: the permission alert uses macOS's own wording in {sum(1 for l in message if l != 'en')} languages")
    return 0


if __name__ == "__main__":
    sys.exit(main())
