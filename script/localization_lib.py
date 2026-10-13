"""What the localization scripts share: where the files are, how a catalog is read and written, how a
placeholder is counted and how a catalog key becomes a Swift name.

Used by compile_localizations.py, verify_localizations.py and merge_translations.py; not run on its own.
"""
import json
import re
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
# Commands and settings names between backticks; the setup window shows them as code.
CODE_SPAN = re.compile(r"`[^`]*`")


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
