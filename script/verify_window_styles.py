"""Refuses control styles demonstrated to break the window (ADRs 0029 and 0034).

Value menus use ChoiceMenu's native pop-up, with an optional app icon and the system's own indicator. A hand-drawn indicator in its
label was extracted as the leading image by AppKit (0029); removing the native control instead made the resulting plain-button menu
fail to open in the combined native review (0034). Real-control previews verify AppKit geometry.

Borderless plain buttons still draw whole-row labels grey (0029). The plain-button Menu combination is also refused: .buttonStyle(.plain)
alone is fine for a Button, but not following .menuStyle(.button). self_test checks both patterns before scanning production files.

    uv run script/verify_window_styles.py            the window's files
    uv run script/verify_window_styles.py <folder>   the Swift files of another folder (to try it against an older tree)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WINDOW = ROOT / "Apps" / "RightHere"

# Each pattern with the decision it comes from. A comment that names a style (to say why it is not used) is not a use: the check looks at
# code with the comments taken out.
REFUSED = [
    (re.compile(r"\.menuStyle\(\s*\.button\s*\)\s*\.buttonStyle\(\s*\.plain\s*\)"), "a plain-button menu that did not open in native review (ADR 0034); use ChoiceMenu"),
    (re.compile(r"\.buttonStyle\(\s*\.borderless\s*\)"), "an AppKit button: it drew the words of a whole row grey (ADR 0029, 11); use PlainButton or .plain"),
]

COMMENT = re.compile(r"//[^\n]*|/\*.*?\*/", re.DOTALL)


def findings(text: str) -> list[tuple[int, str]]:
    """The line of each refused style in Swift source, with the reason. Comments are blanked, line by line, so the lines still count."""
    code = COMMENT.sub(lambda match: re.sub(r"[^\n]", " ", match.group(0)), text)
    found = []
    for pattern, reason in REFUSED:
        for match in pattern.finditer(code):
            found.append((code.count("\n", 0, match.start()) + 1, f"{match.group(0)} is {reason}"))
    return sorted(found)


def self_test() -> None:
    sample = """
    Menu { choices() } label: { label }
        .menuStyle(.button).buttonStyle(.plain)   // the broken menu
    // .buttonStyle(.borderless) in a comment is not a use
    Button(action: action, label: label)
        .buttonStyle( .borderless )
    Button(action: action, label: label).buttonStyle(.plain)
    """
    lines = [line for line, _reason in findings(sample)]
    assert lines == [3, 6], f"self test: the check found lines {lines}, not [3, 6]"
    assert findings("Menu {}.menuStyle(.borderlessButton)") == []


def main() -> int:
    self_test()
    folder = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else WINDOW
    files = sorted(folder.glob("*.swift"))
    if not files:
        print(f"error: no Swift files in {folder}", file=sys.stderr)
        return 1
    problems = []
    for file in files:
        for line, reason in findings(file.read_text(encoding="utf-8")):
            problems.append(f"{file.relative_to(ROOT) if file.is_relative_to(ROOT) else file}:{line}: {reason}")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"ok: {len(files)} window files use no control style known to break native interaction or appearance")
    return 0


if __name__ == "__main__":
    sys.exit(main())
