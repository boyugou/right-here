#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Measure the text that people read against docs/development/WRITING.md: how long the sentences are, and how many
use the passive voice. It reports; it does not fail.

    ./script/writing_report.py                       the README, the user guides, the plugin's README
    ./script/writing_report.py --site <gh-pages>     also the website's English strings (i18n/en.json)
    ./script/writing_report.py --long FILE           list the long sentences of one file

A sentence is long when it has more than 25 words (a step should have 20 or fewer). Code (fenced blocks, `inline
code`), headings, table rows and link targets are not counted.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_FILES = ["README.md", "docs/INDEX.md", "docs/TROUBLESHOOTING.md", "docs/AGENT_SETUP.md", "CONTRIBUTING.md",
                 "SECURITY.md", "plugins/right-here/README.md", "CHANGELOG.md"]
LONG = 25

BE = r"(?:is|are|was|were|be|been|being|isn't|aren't|wasn't|weren't)"
IRREGULAR = ("made given done shown written taken known seen kept held sent built set put read run found left told "
             "brought bought begun broken chosen drawn driven eaten fallen felt forgotten got gotten hidden hit hung "
             "laid led lost meant met paid proven quit ridden risen said sold shut slept spent split spread stood "
             "struck sworn swept thought thrown understood undone woken worn won wound").split()
PASSIVE = re.compile(rf"\b{BE}\s+(?:\w+ly\s+)?(?:\w+ed|{'|'.join(IRREGULAR)})\b", re.IGNORECASE)


def markdown_text(text: str) -> str:
    """The prose of a Markdown file, one block per line: code, headings, tables and HTML are left out."""
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith(("#", "|", "<", "![", "---")):
            lines.append("")
            continue
        lines.append(stripped)
    prose = "\n".join(lines)
    prose = re.sub(r"`[^`]*`", "CODE", prose)
    prose = re.sub(r"!\[[^\]]*\]\([^)]*\)", " ", prose)
    prose = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", prose)
    prose = re.sub(r"<[^>]+>", " ", prose)
    prose = re.sub(r"\*\*|__|\*", "", prose)
    return prose


def sentences(prose: str) -> list[str]:
    found = []
    # Paragraphs and list items end a sentence too.
    for block in re.split(r"\n\s*\n|\n\s*(?:[-*+]|\d+\.)\s+", prose):
        block = " ".join(block.split())
        block = re.sub(r"^(?:[-*+]|\d+\.)\s+", "", block)
        for sentence in re.split(r"(?<=[.!?])\s+(?=[A-Z\"“(])", block):
            if len(sentence.split()) >= 3:
                found.append(sentence)
    return found


def measure(name: str, items: list[str]) -> dict:
    words = [len(s.split()) for s in items]
    long = [s for s in items if len(s.split()) > LONG]
    passive = [s for s in items if PASSIVE.search(s)]
    return {
        "name": name,
        "sentences": len(items),
        "words": sum(words),
        "average": (sum(words) / len(words)) if words else 0,
        "long": long,
        "passive": passive,
    }


def site_text(site: Path) -> list[str]:
    strings = json.loads((site / "i18n" / "en.json").read_text(encoding="utf-8"))
    prose = "\n\n".join(re.sub(r"<[^>]+>", " ", re.sub(r"`[^`]*`", "CODE", value)) for value in strings.values())
    return sentences(prose)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--site", type=Path, help="the gh-pages checkout, for its English strings")
    parser.add_argument("--long", metavar="FILE", help="list the long sentences of one file (or 'site')")
    parser.add_argument("files", nargs="*")
    arguments = parser.parse_args()

    results = []
    for name in arguments.files or DEFAULT_FILES:
        path = ROOT / name
        if not path.exists():
            continue
        results.append(measure(name, sentences(markdown_text(path.read_text(encoding="utf-8")))))
    if arguments.site:
        results.append(measure("site", site_text(arguments.site)))

    if arguments.long:
        for result in results:
            if result["name"] == arguments.long:
                for sentence in result["long"]:
                    print(f"{len(sentence.split()):3d}  {sentence}")
        return 0

    print(f"{'file':34} {'sentences':>9} {'words':>7} {'average':>7} {'> 25 words':>10} {'passive':>8}")
    total = measure("all", [])
    for result in results:
        count = result["sentences"] or 1
        print(f"{result['name']:34} {result['sentences']:9d} {result['words']:7d} {result['average']:7.1f} "
              f"{len(result['long']) / count:9.0%} {len(result['passive']) / count:8.0%}")
        total["sentences"] += result["sentences"]
        total["words"] += result["words"]
        total["long"] += result["long"]
        total["passive"] += result["passive"]
    count = total["sentences"] or 1
    print(f"{'all':34} {total['sentences']:9d} {total['words']:7d} {total['words'] / count:7.1f} "
          f"{len(total['long']) / count:9.0%} {len(total['passive']) / count:8.0%}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
