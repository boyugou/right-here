#!/usr/bin/env python3
"""Check our wording against macOS's own, as shipped on this Mac.

1. The Settings path the permission alert quotes (System Settings > Privacy & Security > Automation). macOS
   ships those names in its own languages (inside System Settings and its Privacy & Security extension), so
   this reads them and checks each translation of `alert.permissionMessage` and `alert.openSettings` uses
   the same words. Languages macOS does not ship (Bengali, Persian, Marathi, Tamil, Telugu, Urdu) show an
   English Settings, so their alert must quote the English path.
2. The other two Settings paths the app names: where to switch the Finder extension on (General > Login Items & Extensions >
   Finder, in `app.fixExtensionEnable` and `doctor.fix.extensionEnable`) and where a Quick Action gets its keyboard shortcut
   (Keyboard > Keyboard Shortcuts > Services, in `app.quickActionsBody`). The same rule: the words macOS ships, or the English
   path for a language it does not ship.
3. Two menu items Finder has itself: "Open With" (`group.openWith`) and "Show in Finder" (`action.reveal`)
   read exactly as Finder's own menus do, so ours sits comfortably beside them.

It depends on the macOS version it runs on, so it is not part of verify_all.sh; run it after a macOS update:

    ./script/verify_macos_wording.py
"""
import json
import plistlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FINDER = Path("/System/Library/CoreServices/Finder.app/Contents/Resources")
PANE = Path("/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/Resources")
SETTINGS = Path("/System/Applications/System Settings.app/Contents/Resources")
EXTENSIONS = Path("/System/Library/ExtensionKit/Extensions")
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


# The words of the other Settings paths in a case ending, as the sentence correctly writes them (by language, then by macOS's label).
INFLECTED_PATHS = {
    "el": {"System Settings": ["Ρυθμίσεων συστήματος"]},
    "pl": {"System Settings": ["Ustawieniach systemowych"]},
    "ru": {"System Settings": ["Системных настройках"]},
    "uk": {"System Settings": ["Системних параметрах"]},
}


def normalize(text: str) -> str:
    return text.replace("­", "").replace(" ", " ").replace("‏", "")


def lookup(table: dict, language: str, key: str):
    for code in [language] + ALIASES.get(language, []):
        for candidate in (code, code.replace("-", "_")):
            if key in table.get(candidate, {}):
                return table[candidate][key]
    return None


def read_table(path: Path):
    try:
        return plistlib.loads(path.read_bytes())
    except (OSError, ValueError):
        return None


def finder_strings(language: str, name: str):
    for code in [language] + ALIASES.get(language, []):
        for candidate in (code, code.replace("-", "_")):
            path = FINDER / f"{candidate}.lproj" / name
            if path.exists():
                try:
                    return plistlib.loads(path.read_bytes())
                except Exception:
                    return None
    return None


def settings_path_problems(strings: dict, settings: dict, languages: dict) -> list:
    """The Login Items & Extensions path and the Keyboard Shortcuts path, in the strings that quote them."""
    general = read_table(EXTENSIONS / "GeneralSettings.appex/Contents/Resources/InfoPlist.loctable")
    login = read_table(EXTENSIONS / "LoginItems.appex/Contents/Resources/Localizable.loctable")
    keyboard_info = read_table(EXTENSIONS / "KeyboardSettings.appex/Contents/Resources/InfoPlist.loctable")
    keyboard = read_table(EXTENSIONS / "KeyboardSettings.appex/Contents/Resources/Localizable.loctable")
    shortcuts = read_table(EXTENSIONS / "KeyboardSettings.appex/Contents/Resources/DefaultShortcutsTable.loctable")
    if not all((general, login, keyboard_info, keyboard, shortcuts)):
        return ["cannot read the General, Login Items or Keyboard settings of this macOS"]
    paths = {
        "app.fixExtensionEnable": ("System Settings › General › Login Items & Extensions", (
            ("System Settings", lambda l: lookup(settings, l, "CFBundleDisplayName") or lookup(settings, l, "CFBundleName")),
            ("General", lambda l: lookup(general, l, "CFBundleDisplayName")),
            ("Login Items & Extensions", lambda l: lookup(login, l, "Login Items & Extensions")))),
        "app.quickActionsBody": ("System Settings › Keyboard › Keyboard Shortcuts › Services", (
            ("System Settings", lambda l: lookup(settings, l, "CFBundleDisplayName") or lookup(settings, l, "CFBundleName")),
            ("Keyboard", lambda l: lookup(keyboard_info, l, "CFBundleDisplayName")),
            # macOS writes the button "Keyboard Shortcuts…", with its ellipsis (and a different one in zh-Hant).
            ("Keyboard Shortcuts", lambda l: (lookup(keyboard, l, "Keyboard Shortcuts…") or "").rstrip("….⋯")),
            ("Services", lambda l: lookup(shortcuts, l, "Services")))),
    }
    paths["doctor.fix.extensionEnable"] = paths["app.fixExtensionEnable"]
    problems = []
    for key, (english, parts) in paths.items():
        for language in sorted(languages):
            if language == "en":
                continue
            text = normalize(strings[key]["localizations"][language]["stringUnit"]["value"])
            names = [lookup_name(language) for _, lookup_name in parts]
            if not all(names):
                if english not in text:
                    problems.append(f"{language}: macOS does not ship this language, so {key} should quote the English path")
                continue
            for (label, _), name in zip(parts, names):
                if normalize(name).casefold() not in text.casefold() and not any(
                        form.casefold() in text.casefold() for form in INFLECTED_PATHS.get(language, {}).get(label, [])):
                    problems.append(f"{language}: {key} does not use macOS's word for {label}: {normalize(name)}")
    return problems


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
    problems += settings_path_problems(strings, settings, message)
    finder_checked = 0
    for language in sorted(message):
        if language == "en":
            continue
        merged = finder_strings(language, "LocalizableMerged.strings")
        services = finder_strings(language, "ServicesMenu.strings")
        if not merged:
            continue
        finder_checked += 1
        open_with = normalize(strings["group.openWith"]["localizations"][language]["stringUnit"]["value"])
        if normalize(merged.get("N152", open_with)) != open_with:
            problems.append(f"{language}: group.openWith is {open_with!r} but Finder's Open With is {normalize(merged['N152'])!r}")
        reveal = normalize(strings["action.reveal"]["localizations"][language]["stringUnit"]["value"])
        theirs = normalize((services or {}).get("Finder/Reveal", "/" + reveal).split("/")[-1])
        if theirs != reveal:
            problems.append(f"{language}: action.reveal is {reveal!r} but Finder's Show in Finder is {theirs!r}")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"ok: the permission alert uses macOS's own wording in {sum(1 for l in message if l != 'en')} languages; "
          f"Open With and Show in Finder match Finder's in {finder_checked}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
