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
# The catalogs every language must be complete in: the strings of the code (compiled into Swift), what the App Intents
# are called (read by the app by key), the permission prompt text and the phrases of the Shortcuts actions.
CATALOGS = ("Localizable.xcstrings", "AppIntents.xcstrings", "InfoPlist.xcstrings", "AppShortcuts.xcstrings")
# The ones a person reads on a screen like any other string of the code, so the placeholder, script and right-to-left
# rules apply; a Shortcuts phrase is spoken and a permission prompt is system text.
TEXT_CATALOGS = ("Localizable.xcstrings", "AppIntents.xcstrings")

# %@ and %1$@ are the only placeholders a string may use.
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?@")
# Commands and settings names between backticks (the setup window shows them as code), and the app-name placeholder of
# the Shortcuts phrases. A translation keeps each of them as it is.
PROTECTED = re.compile(r"`[^`]*`|\$\{[A-Za-z]+\}")
RIGHT_TO_LEFT_MARK = "\u200f"
LEFT_TO_RIGHT_MARK = "\u200e"
# A command between backticks that ends in a bracket (`rh ... <folder>`). In a right-to-left sentence the bracket takes the
# direction of the sentence, so it is drawn mirrored and on the wrong side of the command unless a left-to-right mark follows.
CODE_SPAN = re.compile(r"`[^`]*`")
BRACKET_BEFORE_CLOSING_TICK = re.compile(r"[<>()\[\]{}]`$")


def bracket_ending_commands(value: str) -> list[re.Match]:
    """The backticked commands of `value` that end in a bracket and are not followed by a left-to-right mark. Backticks are paired one
    after the other (the first with the second, the third with the fourth), never the text between two commands as if it were one."""
    return [span for span in CODE_SPAN.finditer(value)
            if BRACKET_BEFORE_CLOSING_TICK.search(span.group(0)) and not value.startswith(LEFT_TO_RIGHT_MARK, span.end())]
# A path, or Latin text with a quote, an equals sign or a bracket in it (`launcher = "link"`, `agents = ["claude"]`). In a
# right-to-left sentence the neutral characters at the ends of such a literal (the `~/.` of a path, a closing quote, a bracket) take the
# direction of the sentence and are drawn at the wrong end of it (`~/.local/bin` as `local/bin./~`). The setup window puts the value
# of a message in an isolate, which keeps it in one piece, so these are values (%@) of the message and never words of a translation.
LITERAL_PATH = re.compile(r"(?<![\w/.])(?:~/|/(?:usr|bin|opt|etc|var|tmp|Users|Library|Applications|System|private|Volumes)\b)")
SYMBOLS_IN_LATIN_LITERAL = set('"=[]')
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


def placeholders_joined_to_a_mark(text: str) -> list[str]:
    """Each placeholder that shares a character with what stands next to it: a combining or spacing mark, a zero-width joiner or
    non-joiner, a few letters that Unicode makes part of the character before them, after it; a prepended sign before it. Swift's
    String then counts `@` (or `%`) and that mark as one character, so `contains("%@")` and a replacement no longer find the
    placeholder. A direction mark does not join and is not reported. The catalog's Swift tests are the full check (they render every
    key); this one is here so that merge_translations.py refuses such a text before it is written."""
    joins_before = {"\u200c", "\u200d", "\u0e33", "\u0eb3", "\uff9e", "\uff9f"} | {chr(c) for c in range(0x1F3FB, 0x1F400)}
    prepended = {chr(c) for c in range(0x0600, 0x0606)} | {"\u06dd", "\u070f", "\u0890", "\u0891", "\u08e2"}
    found = []
    for match in PLACEHOLDER.finditer(text):
        after = text[match.end():match.end() + 1]
        if after and (unicodedata.category(after) in ("Mn", "Mc", "Me") or after in joins_before):
            found.append(match.group(0) + after)
        before = text[match.start() - 1:match.start()] if match.start() else ""
        if before in prepended:
            found.append(before + match.group(0))
    return found


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
    # A name kept as it is in a right-to-left language carries the direction mark that makes it start the line on the right.
    if not found or value.replace(RIGHT_TO_LEFT_MARK, "").replace(LEFT_TO_RIGHT_MARK, "") == english:
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
        for span in reversed(bracket_ending_commands(value)):
            value = value[:span.end()] + LEFT_TO_RIGHT_MARK + value[span.end():]
    return value


def right_to_left_literals(value: str) -> list[str]:
    """The paths and the quoted, assigned or bracketed Latin words that a right-to-left translation writes itself, as the words
    around them: a path anywhere (a command between backticks included), the other kind outside backticks and placeholders."""
    without_values = PLACEHOLDER.sub(" ", value).replace(RIGHT_TO_LEFT_MARK, " ").replace(LEFT_TO_RIGHT_MARK, " ")
    outside_commands = PROTECTED.sub(" ", without_values)
    found = [token for token in without_values.split() if LITERAL_PATH.search(token)]
    for token in outside_commands.split():
        if token not in found and re.search(r"[A-Za-z]", token) and SYMBOLS_IN_LATIN_LITERAL & set(token):
            found.append(token)
    return found


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
    for joined in placeholders_joined_to_a_mark(value):
        problems.append(f"{where}: {joined!r} joins the placeholder to the mark after it in one character, so the value is not "
                        f"found in it; write the suffix without the joining mark: {value!r}")
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
    if direction and language.rtl and key not in FILE_NAME_KEYS and bracket_ending_commands(value):
        problems.append(f"{where}: a command that ends in a bracket needs a left-to-right mark after it: {value!r}")
    if direction and language.rtl:
        for literal in right_to_left_literals(value):
            problems.append(f"{where}: {literal!r} is a path, or Latin text with a quote, an equals sign or a bracket, written in a right-to-left "
                            f"sentence; its ends would be drawn at the wrong side. Make it a value (%@), which the window isolates: {value!r}")
    return problems
