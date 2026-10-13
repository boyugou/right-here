"""What the localization scripts share: where the files are, how a catalog is read and written, how a
placeholder is counted, how a catalog key becomes a Swift name and what a good translation looks like.

Used by compile_localizations.py, verify_localizations.py and merge_translations.py; not run on its own.
"""
import json
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCALIZATION = ROOT / "Localization"
MANIFEST = LOCALIZATION / "languages.json"
SWIFT_DIRECTORY = ROOT / "Sources" / "RightHereCore" / "Localization"
# The catalogs every language must be complete in: the strings of the code, the permission prompt text and the
# phrases of the Shortcuts actions.
CATALOGS = ("Localizable.xcstrings", "InfoPlist.xcstrings", "AppShortcuts.xcstrings")

# %@ and %1$@ are the only placeholders a string may use.
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?@")
# Commands and settings names between backticks (the setup window shows them as code), and the app-name placeholder of
# the Shortcuts phrases. A translation keeps each of them as it is.
PROTECTED = re.compile(r"`[^`]*`|\$\{[A-Za-z]+\}")
RIGHT_TO_LEFT_MARK = "\u200f"
LEFT_TO_RIGHT_MARK = "\u200e"
# A command between backticks that ends in a bracket (`rh ... <folder>`). In a right-to-left sentence the bracket takes the
# direction of the sentence, so it is drawn mirrored and on the wrong side of the command unless a left-to-right mark follows.
BRACKET_ENDING_COMMAND = re.compile(r"(`[^`]*[<>()\[\]{}]`)(?!" + LEFT_TO_RIGHT_MARK + ")")
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


@dataclass(frozen=True)
class Language:
    code: str
    name: str
    script: str
    rtl: bool


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def languages() -> list[Language]:
    """The shipped languages, in the order of the manifest (the source language first)."""
    manifest = read_json(MANIFEST)
    return [Language(entry["code"], entry["name"], entry["script"], entry.get("rtl", False)) for entry in manifest["languages"]]


def source_language() -> str:
    return read_json(MANIFEST)["source"]


def read_catalog(name: str) -> dict:
    return read_json(LOCALIZATION / name)


def write_catalog(name: str, catalog: dict) -> None:
    # The format the catalogs have always had: two-space indentation, sorted keys, a final newline.
    (LOCALIZATION / name).write_text(json.dumps(catalog, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")


def placeholders(text: str) -> list[str]:
    return [match.group(0) for match in PLACEHOLDER.finditer(text)]


def arity(text: str) -> int:
    """How many arguments the text takes. Raises ValueError for a text a translation could not safely reorder."""
    found = list(PLACEHOLDER.finditer(text))
    positions = [int(match.group(1)) for match in found if match.group(1)]
    if positions and len(positions) != len(found):
        raise ValueError("mixes %@ with numbered placeholders")
    if not positions:
        if len(found) > 1:
            raise ValueError("has several %@; number them (%1$@, %2$@) so that a translation can reorder them")
        return len(found)
    if sorted(set(positions)) != list(range(1, max(positions) + 1)):
        raise ValueError(f"numbers its placeholders {sorted(set(positions))} instead of 1 to {max(positions)}")
    return max(positions)


def case_name(key: str) -> str:
    """`menu.openIn` becomes `menuOpenIn`: the segments after the first start with a capital."""
    first, *rest = key.split(".")
    return first + "".join(part[:1].upper() + part[1:] for part in rest)


def swift_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")
    return f'"{escaped}"'


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


def is_only_a_value(english: str) -> bool:
    """A text that is nothing but its value (`%@`): a path, a message from elsewhere. It is shown as it is, in every language."""
    return PLACEHOLDER.fullmatch(english) is not None


def with_direction_mark(language: Language, key: str, value: str, english: str) -> str:
    """A right-to-left text that would start with Latin text (a name, a command, a placeholder) is laid out left to right
    unless it starts with a right-to-left mark, and a command that ends in a bracket needs a left-to-right mark after it.
    Not for a text that becomes a file name, and not for one that is only a value (the mark would end up in the copied
    path)."""
    if language.rtl and key not in FILE_NAME_KEYS and not is_only_a_value(english):
        if starts_left_to_right(value):
            value = RIGHT_TO_LEFT_MARK + value
        value = BRACKET_ENDING_COMMAND.sub(lambda match: match.group(1) + LEFT_TO_RIGHT_MARK, value)
    return value


def translation_problems(key: str, language: Language, value: str, english: str, keep: tuple[str, ...] | list[str] = (), direction: bool = True) -> list[str]:
    """What is wrong with `value` as the translation of `english`, as lines that start with the key and the language.
    `direction` is the right-to-left mark rule, which only the strings of the code follow (a Shortcuts phrase is spoken)."""
    where = f"{key} [{language.code}]"
    problems = []
    if not value.strip():
        return [f"{where}: empty"]
    if sorted(placeholders(value)) != sorted(placeholders(english)):
        problems.append(f"{where}: placeholders differ from English: {value!r}")
    if "%" in PLACEHOLDER.sub("", value):
        problems.append(f"{where}: a % that is not a placeholder: {value!r}")
    if value.count("`") % 2 or sorted(PROTECTED.findall(value)) != sorted(PROTECTED.findall(english)):
        problems.append(f"{where}: the commands between backticks differ from English: {value!r}")
    for token in keep:
        if token not in value:
            problems.append(f"{where}: {token!r} is missing: {value!r}")
    if wrong_script(language.script, value, english):
        problems.append(f"{where}: not written in the script of {language.code}: {value!r}")
    if is_only_a_value(english) and value != english:
        problems.append(f"{where}: the text is only its value and is shown as it is, so it stays {english!r}: {value!r}")
    elif key in FILE_NAME_KEYS:
        if RIGHT_TO_LEFT_MARK in value or "/" in value or ":" in value:
            problems.append(f"{where}: becomes a file name, so no direction mark, slash or colon: {value!r}")
    elif direction and language.rtl and not is_only_a_value(english) and starts_left_to_right(value):
        problems.append(f"{where}: starts with Latin text and no right-to-left mark: {value!r}")
    if direction and language.rtl and key not in FILE_NAME_KEYS and BRACKET_ENDING_COMMAND.search(value):
        problems.append(f"{where}: a command that ends in a bracket needs a left-to-right mark after it: {value!r}")
    return problems
