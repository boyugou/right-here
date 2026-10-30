"""Refuses the control styles of the window that AppKit draws other than the window's own views draw them.

The window is drawn by its own SwiftUI views so that the pictures of `preview_setup.sh` are the window (ADR 0029). Two styles put an
AppKit control under a SwiftUI label and draw it their own way, measured in a window that was never put on screen (ADR 0029, 10 and
11):

- `.menuStyle(.borderlessButton)` is an AppKit pop-up button, which keeps the label's text and its first image and draws the image
  first: the window showed "⇕ Ghostty" while every picture of it showed "Ghostty ⇕".
- `.buttonStyle(.borderless)` is an AppKit button, which drew the words of a whole row grey, as a disabled row's.

`ChoiceMenu` and `PlainButton` (Apps/RightHere) are the way to make a value menu and a plain button; both are SwiftUI's own. This
check reads the window's Swift files and fails on either style. `self_test` runs first, so that a net that has stopped catching what
it is for fails the build.

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
    (re.compile(r"\.menuStyle\(\s*\.borderlessButton\s*\)"), "an AppKit pop-up button: it draws the label's image before its text (ADR 0029, 10); use ChoiceMenu"),
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
        .menuStyle(.borderlessButton)   // the old way
    // .buttonStyle(.borderless) in a comment is not a use
    Button(action: action, label: label)
        .buttonStyle( .borderless )
    Button(action: action, label: label).buttonStyle(.plain)
    """
    lines = [line for line, _reason in findings(sample)]
    assert lines == [3, 6], f"self test: the check found lines {lines}, not [3, 6]"
    assert findings("Menu {}.menuStyle(.button).buttonStyle(.plain)") == []


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
    print(f"ok: {len(files)} window files use no control style that AppKit draws its own way")
    return 0


if __name__ == "__main__":
    sys.exit(main())
