#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""The released version is written once in the code (AppIdentity.version); everything else that names it must agree.

    ./script/verify_version.py

Checks project.yml (MARKETING_VERSION), the top entry of CHANGELOG.md, the Homebrew formula and cask under packaging/ and the Claude Code plugin's manifest.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def first(pattern: str, path: str, flags: int = 0) -> str | None:
    match = re.search(pattern, (ROOT / path).read_text(encoding="utf-8"), flags)
    return match.group(1) if match else None


version = first(r'static let version = "([^"]+)"', "Sources/RightHereCore/AppIdentity.swift")
if version is None:
    sys.exit("verify_version: AppIdentity.version not found")
expected = {
    "project.yml MARKETING_VERSION": first(r"MARKETING_VERSION:\s*(\S+)", "project.yml"),
    "CHANGELOG.md top entry": first(r"^## (\d+\.\d+\.\d+)", "CHANGELOG.md", re.M),
    "packaging/homebrew/right-here.rb version": first(r'^\s*version "([^"]+)"', "packaging/homebrew/right-here.rb", re.M),
    "packaging/homebrew/rh.rb url tag": first(r"/tags/v([0-9.]+)\.tar\.gz", "packaging/homebrew/rh.rb"),
    "plugins/right-here/.claude-plugin/plugin.json version": first(r'"version":\s*"([^"]+)"', "plugins/right-here/.claude-plugin/plugin.json"),
}
wrong = {where: found for where, found in expected.items() if found != version}
if wrong:
    for where, found in wrong.items():
        print(f"verify_version: {where} says {found!r}, AppIdentity.version says {version!r}", file=sys.stderr)
    sys.exit(1)
print(f"ok: version {version} in the code, project.yml, CHANGELOG.md and packaging/")
