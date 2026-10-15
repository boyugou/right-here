#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Check the documentation against the repository: the `rh` commands it shows and the links it makes.

Docs rot quietly: a flag is renamed, a subcommand is split, a file moves, and a README or a skill keeps telling
people to run something that now fails or to read a page that is gone (the Homebrew formula's test did exactly
that). This reads every `rh ...` command in the user-facing documentation, the plugin's skills and the embedded
agent playbook, and asks the built `rh` whether the subcommand exists and its `--help` mentions each flag
(nothing is run but `--help`); and it checks that every relative link in every Markdown file points at a file.

Needs a built `rh`: `swift build` first.

    ./script/verify_docs.py                       uses .build/debug/rh
    RH=/path/to/rh ./script/verify_docs.py
"""
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RH = os.environ.get("RH") or str(ROOT / ".build" / "debug" / "rh")

# Decision records describe what was true when they were written, so they are left out.
SOURCES = [
    ROOT / "README.md", ROOT / "CONTRIBUTING.md", ROOT / "SECURITY.md", ROOT / "ROADMAP.md", ROOT / "CHANGELOG.md",
    ROOT / "docs" / "DESIGN.md", ROOT / "docs" / "INDEX.md", ROOT / "docs" / "TROUBLESHOOTING.md", ROOT / "docs" / "AGENT_SETUP.md",
    ROOT / "Sources" / "RightHereCore" / "Documentation.swift", ROOT / "Sources" / "RightHereMCP" / "MCPGuide.swift",
    *sorted((ROOT / "docs" / "development").glob("*.md")),
    *sorted((ROOT / "plugins").rglob("*.md")),
]

# swift-argument-parser's own options: some are hidden from `--help`.
BUILT_IN = {"--help", "--version", "--generate-completion-script"}

_helps: dict[tuple[str, ...], tuple[int, str]] = {}


def help_for(path: tuple[str, ...]) -> tuple[int, str]:
    if path not in _helps:
        result = subprocess.run([RH, *path, "--help"], capture_output=True, text=True)
        _helps[path] = (result.returncode, result.stdout + result.stderr)
    return _helps[path]


def commands(text: str) -> set[str]:
    found = {m.group(1).strip() for m in re.finditer(r"`(rh [^`\n]+)`", text)}
    for block in re.finditer(r"```(?:sh|bash|shell)?\n(.*?)```", text, re.S):
        for line in block.group(1).splitlines():
            line = line.strip().removeprefix("$ ")
            if line.startswith("rh "):
                found.add(line.split(" #")[0].strip())
    return found


def subcommands(path: tuple[str, ...]) -> set[str]:
    """The subcommands `rh <path> --help` lists. (`rh <anything> --help` exits 0 and prints the parent's help, so
    asking whether a word is a subcommand by its exit status can never say no.)"""
    names: set[str] = set()
    listing = False
    for line in help_for(path)[1].splitlines():
        if line.strip() == "SUBCOMMANDS:":
            listing = True
            continue
        if listing:
            if not line.strip():
                if names:
                    break
                continue
            match = re.match(r"^  ([a-z][a-z-]*)\b", line)
            if match:
                names.add(match.group(1))
            elif not line.startswith(" "):
                break
    return names


def problem(command: str) -> str | None:
    try:
        tokens = shlex.split(command)
    except ValueError:
        return None
    rest = tokens[1:]
    path: list[str] = []
    for word in rest:
        if word.startswith("-"):
            break
        known = subcommands(tuple(path))
        if word in known:
            path.append(word)
        elif known and re.fullmatch(r"[a-z][a-z-]*", word):
            return f"`{word}` is not a subcommand of `rh {' '.join(path)}`".replace("`rh `", "`rh`")
        else:
            break
    text = help_for(tuple(path))[1]
    for flag in (t.split("=")[0] for t in rest if t.startswith("--")):
        # Whole option names only: "--dry" is not "--dry-run".
        if flag not in BUILT_IN and not re.search(rf"(?<![\w-]){re.escape(flag)}(?![\w-])", text):
            return f"{flag} is not an option of `rh {' '.join(path)}`".replace("`rh `", "`rh`")
    return None


def broken_links() -> list[str]:
    problems = []
    for markdown in sorted(ROOT.rglob("*.md")):
        if ".build" in markdown.parts or ".git" in markdown.parts:
            continue
        for match in re.finditer(r"\[[^\]]*\]\(([^)#\s]+)(?:#[^)]*)?\)", markdown.read_text(encoding="utf-8")):
            target = match.group(1)
            if re.match(r"^[a-z][a-z0-9+.-]*:", target):
                continue
            if not (markdown.parent / target).resolve().exists():
                problems.append(f"{markdown.relative_to(ROOT)}: the link to {target} points at nothing")
    return problems


def main() -> int:
    if not os.access(RH, os.X_OK):
        print(f"no rh at {RH}; run `swift build` first", file=sys.stderr)
        return 2
    seen: dict[str, set[str]] = {}
    for source in SOURCES:
        if source.exists():
            for command in commands(source.read_text(encoding="utf-8")):
                seen.setdefault(command, set()).add(source.name)
    problems = broken_links()
    for command, where in sorted(seen.items()):
        why = problem(command)
        if why:
            problems.append(f"`{command}` ({', '.join(sorted(where))}): {why}")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"ok: {len(seen)} distinct rh commands in the documentation all exist with the flags shown, and no link is broken")
    return 0


if __name__ == "__main__":
    sys.exit(main())
