#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema"]
# ///
"""Check that `rh config schema` (the JSON Schema editors use) agrees with what `rh config validate` accepts.

A real JSON Schema validator reads the schema, and sample configs that must be accepted or rejected are
run through it, so the schema cannot drift from the config. Needs a built `rh`: `swift build` first.

    ./script/verify_config_schema.py              uses .build/debug/rh
    RH=/path/to/rh ./script/verify_config_schema.py
"""
import json
import os
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parent.parent
RH = os.environ.get("RH") or str(ROOT / ".build" / "debug" / "rh")

VALID = {
    "empty": "",
    "full": """
version = 1
[general]
terminal = "ghostty"
terminal_placement = "tab"
editor = "vscode"
agents = ["claude", "codex", "lazygit"]
[menu]
items = ["open-terminal", "-", "agents", "copy-path"]
[services]
items = ["open.terminal", "agent.claude"]
[copy_path]
styles = ["absolute", "ai-mention"]
[new_file]
then = "open"
[[new_file.template]]
id = "md"
title = "Markdown"
extension = "md"
open_with = "typora"
[[app]]
id = "tower"
name = "Tower"
bundle_id = "com.fournova.Tower3"
[agent.lazygit]
name = "lazygit"
command = "lazygit"
[[agent.claude.variant]]
id = "danger"
title = "Danger"
arguments = ["--x"]
""",
}

INVALID = {
    "a typo in a key": '[general]\nagnts = ["codex"]\n',
    "a wrong version": "version = 2\n",
    "an unknown copy-path style": '[copy_path]\nstyles = ["absolutee"]\n',
    "an unknown then": '[new_file]\nthen = "close"\n',
    "an unknown placement": '[general]\nterminal_placement = "floating"\n',
    "a template without a title": '[[new_file.template]]\nid = "x"\nextension = "txt"\n',
    "an app without a bundle id": '[[app]]\nid = "x"\nname = "X"\n',
    "an app id that is not an id": '[[app]]\nid = "Bad Id"\nname = "X"\nbundle_id = "a.b"\n',
    "an app id that starts with a dash": '[[app]]\nid = "-x"\nname = "X"\nbundle_id = "a.b"\n',
    "an agent id that is not an id": '[agent."Bad Id"]\nname = "X"\ncommand = "x"\n',
    "an agent id that starts with a dash": '[agent."-x"]\nname = "X"\ncommand = "x"\n',
    "a template extension with a slash": '[[new_file.template]]\nid = "x"\ntitle = "X"\nextension = "a/b"\n',
    "a template extension with a dot": '[[new_file.template]]\nid = "x"\ntitle = "X"\nextension = ".md"\n',
    "an empty template extension": '[[new_file.template]]\nid = "x"\ntitle = "X"\nextension = ""\n',
    "an unknown launcher": '[agent.claude]\nlauncher = "magic"\n',
    "an app id that is a launcher word": '[[app]]\nid = "desktop"\nname = "X"\nbundle_id = "a.b"\n',
    "an app name with an escape character": '[[app]]\nid = "x"\nname = "a\\u001b]0;pwned\\u0007"\nbundle_id = "a.b"\n',
    "an agent name with a line break": '[agent.x]\nname = "two\\nlines"\ncommand = "x"\n',
    "a template title with a C1 control": '[[new_file.template]]\nid = "x"\ntitle = "a\\u009bb"\nextension = "txt"\n',
    "a variant title with a bell": '[agent.claude]\n[[agent.claude.variant]]\nid = "x"\ntitle = "a\\u0007"\n',
    "a preset title with a line separator": '[[preset]]\nid = "x"\ntitle = "a\\u2028b"\nprompt = "Look at {files}"\n',
}

# config.local.toml, the per-machine overlay, is read by the same schema; `disabled` is only meaningful there.
OVERLAY_VALID = {
    "an overlay that disables ids": 'disabled = ["codex", "zed"]\n[general]\nterminal = "terminal"\n',
    "an overlay that replaces an app": '[[app]]\nid = "tower"\nname = "Tower"\nbundle_id = "com.fournova.Tower3"\n',
}
OVERLAY_INVALID = {
    "a disabled list that is not a list": 'disabled = "codex"\n',
    "a disabled list of numbers": "disabled = [1, 2]\n",
}


def main() -> int:
    if not os.access(RH, os.X_OK):
        print(f"no rh at {RH}; run `swift build` first", file=sys.stderr)
        return 2
    schema = json.loads(subprocess.run([RH, "config", "schema"], capture_output=True, text=True, check=True).stdout)
    Draft7Validator.check_schema(schema)
    validator = Draft7Validator(schema)
    problems: list[str] = []

    with tempfile.TemporaryDirectory() as folder:
        env = dict(os.environ, RH_CONFIG_DIR=folder, RH_LOG_DIR=folder + "/logs")
        template = subprocess.run([RH, "init", "--force"], capture_output=True, text=True, env=env)
        generated = Path(folder, "config.toml").read_text()
        VALID["the generated config"] = generated

        for name, text in VALID.items():
            found = [e.message for e in validator.iter_errors(tomllib.loads(text))]
            Path(folder, "config.toml").write_text(text)
            cli = subprocess.run([RH, "config", "validate", "--strict"], capture_output=True, text=True, env=env)
            if found:
                problems.append(f"the schema rejects the valid config '{name}': {found[0]}")
            if cli.returncode != 0:
                problems.append(f"`rh config validate --strict` rejects the valid config '{name}': {cli.stdout.strip() or cli.stderr.strip()}")

        for name, text in INVALID.items():
            found = [e.message for e in validator.iter_errors(tomllib.loads(text))]
            Path(folder, "config.toml").write_text(text)
            cli = subprocess.run([RH, "config", "validate", "--strict"], capture_output=True, text=True, env=env)
            if not found:
                problems.append(f"the schema accepts {name}")
            if cli.returncode == 0:
                problems.append(f"`rh config validate --strict` accepts {name}")

    with tempfile.TemporaryDirectory() as folder:
        env = dict(os.environ, RH_CONFIG_DIR=folder, RH_LOG_DIR=folder + "/logs")
        Path(folder, "config.toml").write_text("")
        for table, expect_valid in ((OVERLAY_VALID, True), (OVERLAY_INVALID, False)):
            for name, text in table.items():
                found = [e.message for e in validator.iter_errors(tomllib.loads(text))]
                Path(folder, "config.local.toml").write_text(text)
                cli = subprocess.run([RH, "config", "validate", "--strict"], capture_output=True, text=True, env=env)
                if expect_valid and (found or cli.returncode != 0):
                    problems.append(f"the valid overlay '{name}' is rejected: {found[:1] or cli.stdout.strip() or cli.stderr.strip()}")
                if not expect_valid and (not found or cli.returncode == 0):
                    problems.append(f"the invalid overlay '{name}' is accepted")

    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"ok: the schema and `rh config validate` agree on {len(VALID)} valid and {len(INVALID)} invalid configs, and {len(OVERLAY_VALID)} valid and {len(OVERLAY_INVALID)} invalid overlays")
    return 0


if __name__ == "__main__":
    sys.exit(main())
