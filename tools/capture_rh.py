#!/usr/bin/env python3
"""Authoring helper: records what `rh` says about a sample project, for the menu on the home page.

    python3 tools/capture_rh.py <path to rh>

It makes a throwaway home with a git repository `code/My App` and the file `Sources/main.swift`, sets Right Here up there
with Ghostty, Visual Studio Code, Claude Code and Codex, and writes three files:

- tools/rh-menu-output.json   `rh menu --json` for the selected file
- tools/rh-menu-output.txt    `rh menu` for the same file
- tools/rh-run-output.json    for every action of that menu, what `rh run <action> --dry-run --json` would do

`rh` runs with RH_HOME and HOME set to the throwaway home, RH_NO_UI set and a minimal PATH, so it reads no real config
and starts nothing. Only the parts of a plan that hold no path are kept: the summary, the kind of each step, the app it
controls, the command it types and what it copies. A copied path is written as if the home were /Users/you, and the
script stops if any other path of this Mac is left.
"""
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
SAMPLE_HOME = "/Users/you"
# The argument of each terminal's AppleScript that holds the text typed into the shell (see the adapters on main).
TYPED_ARGUMENT = {"Ghostty": 1, "Terminal": 0}


def run(rh, home, *args):
    env = {"PATH": "/usr/bin:/bin", "HOME": str(home), "RH_HOME": str(home), "RH_NO_UI": "1", "SHELL": "/bin/zsh",
           "LANG": "en_US.UTF-8"}
    result = subprocess.run([rh, *args], env=env, capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        sys.exit(f"rh {' '.join(args)} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout


def actions(nodes):
    for node in nodes:
        if node.get("actionID"):
            yield node["actionID"]
        yield from actions(node.get("children", []))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    rh = sys.argv[1]
    work = pathlib.Path(tempfile.mkdtemp(prefix="rh-site-")).resolve()
    try:
        home = work / "you"
        project = home / "code" / "My App"  # a space, so that the shell-escaped path differs from the full one
        (project / "Sources").mkdir(parents=True)
        selected = project / "Sources" / "main.swift"
        selected.write_text("print(\"Hello\")\n", encoding="utf-8")
        subprocess.run(["git", "init", "-q", str(project)], check=True)

        run(rh, home, "init", "--terminal", "ghostty", "--editor", "vscode", "--agents", "claude,codex")
        menu_json = run(rh, home, "menu", "--json", str(selected))
        menu_text = run(rh, home, "menu", str(selected))
        menu = json.loads(menu_json)

        plans = {}
        for action in actions(menu):
            plan = json.loads(run(rh, home, "run", action, str(selected), "--dry-run", "--json"))
            steps = []
            for step in plan.get("steps", []):
                kind = step.get("kind")
                kept = {"kind": kind}
                if kind == "appleScript":
                    app = step.get("controls", "")
                    if app not in TYPED_ARGUMENT:
                        sys.exit(f"{action}: which argument of the {app} script is the typed command? Add it to TYPED_ARGUMENT")
                    kept["app"] = app
                    typed = step.get("arguments", [])[TYPED_ARGUMENT[app]]
                    if typed:
                        kept["types"] = typed.replace(str(home), SAMPLE_HOME)
                elif kind == "open":
                    kept["opens"] = [pathlib.Path(t).name for t in step.get("targets", [])]
                elif kind == "openURL":
                    url = urllib.parse.urlsplit(step.get("url", ""))
                    kept["url"] = f"{url.scheme}://{url.netloc}{url.path}"
                elif kind == "copyToPasteboard":
                    kept["copies"] = step.get("text", "").replace(str(home), SAMPLE_HOME)
                elif kind in ("createFile", "reveal"):
                    kept["file"] = pathlib.Path(step.get("path") or (step.get("paths") or [""])[0]).name
                else:
                    sys.exit(f"{action}: a step of kind {kind} that this script does not know")
                steps.append(kept)
            plans[action] = {"summary": plan.get("summary", ""), "steps": steps}

        text = json.dumps(plans, ensure_ascii=False)
        private = [str(work), urllib.parse.quote(str(work), safe=""), os.path.expanduser("~"), "/private/"]
        for needle in private:
            if needle and needle in text + menu_json + menu_text:
                sys.exit(f"a path of this Mac is left in the output: {needle}")

        (ROOT / "tools/rh-menu-output.json").write_text(menu_json, encoding="utf-8")
        (ROOT / "tools/rh-menu-output.txt").write_text(menu_text, encoding="utf-8")
        (ROOT / "tools/rh-run-output.json").write_text(json.dumps(plans, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"{len(plans)} actions recorded")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
