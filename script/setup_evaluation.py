#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""The sandbox for the cold-agent evaluation of `rh setup` (docs/development/SETUP_EVALUATION.md).

A cold agent is an AI agent that has only the installed-style `rh` and the prompt the app copies. This script prepares what it
runs in, and afterwards says what it did:

    ./script/setup_evaluation.py prepare <folder> [--rh <path to rh>] [--config <a config file the person already has>]
    ./script/setup_evaluation.py report <folder>

`prepare` makes, inside <folder> and nowhere else:

  bin/rh          the command the agent runs. It writes every call to log/commands.log, refuses what an evaluation must never run
                  (`finder`, `uninstall`, `probe`, `mcp`, `--probe-*`, `install --finder`, `run` without `--dry-run`), and runs a copy of
                  rh (real/rh) with RH_HOME set to home/ (a trial: every per-user path and the config are under it, and nothing
                  registered for the whole Mac is touched) and RH_NO_UI=1 (rh starts no `open` and no `osascript`).
  shell-home/     the home of the login shell that rh starts to find agent commands: empty startup files, except that `.zshrc` puts
                  fake-agents/ (stubs called claude and codex) on the PATH, so an agent command is found (or not) on purpose.
  work/           where the agent starts, with a folder to preview the menu for (work/projects/demo).
  snapshot-before.json   a hash of the files of the real home that setup could touch, and the Finder extension registrations,
                  so `report` can show that nothing outside the sandbox changed.

`report` prints the commands that were run, which failed or were refused, what changed on this Mac outside the folder (it must be
nothing), and, when a config was given to `prepare`, a diff of it.
"""
import difflib
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

WRAPPER = """#!/bin/bash
# The `rh` of a cold-agent evaluation (script/setup_evaluation.py): logs, refuses what must never run, and runs a trial.
DIR={directory}
LOG="$DIR/log/commands.log"
quoted=$(printf '%q ' "$@")
refuse() {{
  printf '%s\\trefused\\trh %s\\n' "$(date +%s)" "$quoted" >> "$LOG"
  echo "rh (evaluation sandbox): refused: $1" >&2
  exit 64
}}
case "${{1:-}}" in
  finder|uninstall|probe|mcp) refuse "rh ${{1}} is never run in an evaluation" ;;
esac
dry=0
for argument in "$@"; do
  case "$argument" in
    --probe-*|--probe) refuse "a probe opens a window and may ask macOS for permission" ;;
    --bypass-permissions|-y) refuse "no agent is started in an evaluation" ;;
    --dry-run) dry=1 ;;
    --finder) refuse "the Finder extension is registered for the whole Mac, which an evaluation never touches" ;;
  esac
done
if [ "${{1:-}}" = run ] && [ "$dry" = 0 ]; then refuse "rh run without --dry-run could open a window"; fi
export RH_HOME="$DIR/home" RH_NO_UI=1 HOME="$DIR/shell-home" ZDOTDIR="$DIR/shell-home" ENV= BASH_ENV=
unset RH_CONFIG RH_CONFIG_DIR XDG_CONFIG_HOME RH_LOG_DIR
"$DIR/real/rh" "$@"
status=$?
printf '%s\\t%s\\trh %s\\n' "$(date +%s)" "$status" "$quoted" >> "$LOG"
exit $status
"""


def real_home() -> Path:
    import pwd
    return Path(pwd.getpwuid(os.getuid()).pw_dir)


def digest(path: Path) -> str:
    if path.is_symlink():
        return "link -> " + os.readlink(path)
    if not path.exists():
        return "absent"
    if path.is_dir():
        return "folder: " + ",".join(sorted(entry.name for entry in path.iterdir()))
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot() -> dict[str, str]:
    """What setup could touch on this Mac, outside a trial: the real config folder, the shell startup files, the command link, the
    runner script, the Services, and which Finder extensions are registered (read with pluginkit, which only lists)."""
    home = real_home()
    state: dict[str, str] = {}
    config = home / ".config" / "right-here"
    state["config folder"] = digest(config)
    for entry in sorted(config.glob("*")) if config.is_dir() else []:
        state[f"config/{entry.name}"] = digest(entry)
    for name in [".zshrc", ".zprofile", ".zshenv", ".bashrc", ".bash_profile", ".profile", ".config/fish/config.fish"]:
        state[f"~/{name}"] = digest(home / name)
    state["~/.local/bin/rh"] = digest(home / ".local" / "bin" / "rh")
    scripts = home / "Library" / "Application Scripts" / "com.boyugou.righthere.FinderExtension"
    state["runner script folder"] = digest(scripts)
    for entry in sorted(scripts.glob("*")) if scripts.is_dir() else []:
        state[f"runner script/{entry.name}"] = digest(entry)
    services = home / "Library" / "Services"
    state["Right Here Services"] = ",".join(sorted(entry.name for entry in services.glob("Right Here - *"))) if services.is_dir() else "absent"
    listing = subprocess.run(["/usr/bin/pluginkit", "-m", "-A", "-D", "-v", "-p", "com.apple.FinderSync"], capture_output=True, text=True)
    state["Finder extensions (pluginkit)"] = hashlib.sha256(listing.stdout.encode()).hexdigest()
    return state


def prepare(folder: Path, rh: Path, config: Path | None) -> None:
    if folder.exists() and any(folder.iterdir()):
        sys.exit(f"{folder} is not empty; use a new folder")
    if not os.access(rh, os.X_OK):
        sys.exit(f"no rh at {rh}; run `swift build` first (or give --rh)")
    folder = folder.resolve()
    for name in ["bin", "real", "home", "shell-home", "fake-agents", "log", "work/projects/demo"]:
        (folder / name).mkdir(parents=True)
    shutil.copy2(rh, folder / "real" / "rh")
    wrapper = folder / "bin" / "rh"
    wrapper.write_text(WRAPPER.format(directory=json.dumps(str(folder))), encoding="utf-8")
    wrapper.chmod(0o755)
    for name in [".zprofile", ".bashrc", ".bash_profile", ".profile"]:
        (folder / "shell-home" / name).write_text("", encoding="utf-8")
    (folder / "shell-home" / ".zshrc").write_text(f'export PATH="{folder / "fake-agents"}:$PATH"\n', encoding="utf-8")
    for agent in ["claude", "codex"]:
        stub = folder / "fake-agents" / agent
        stub.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        stub.chmod(0o755)
    (folder / "log" / "commands.log").write_text("", encoding="utf-8")
    if config is not None:
        target = folder / "home" / ".config" / "right-here" / "config.toml"
        target.parent.mkdir(parents=True)
        shutil.copy2(config, target)
        shutil.copy2(config, folder / "config-before.toml")
    (folder / "snapshot-before.json").write_text(json.dumps(snapshot(), indent=2, sort_keys=True), encoding="utf-8")
    print(f"prepared {folder}")
    print(f"  the agent runs:  {folder / 'bin' / 'rh'}   (put {folder / 'bin'} first on PATH)")
    print(f"  from:            {folder / 'work'}")


def report(folder: Path) -> int:
    folder = folder.resolve()
    problems = 0
    lines = (folder / "log" / "commands.log").read_text(encoding="utf-8").splitlines()
    print(f"{len(lines)} rh commands:")
    for line in lines:
        parts = line.split("\t", 2)
        status, command = (parts[1], parts[2]) if len(parts) == 3 else ("?", line)
        mark = {"0": "ok     ", "refused": "REFUSED"}.get(status, f"exit {status:<2}")
        problems += status == "refused"
        print(f"  {mark} {command}")
    failed = sum(1 for line in lines if line.split("\t")[1:2] not in (["0"], ["refused"]))
    print(f"  {failed} exited with an error, {sum(1 for line in lines if line.split(chr(9))[1:2] == ['refused'])} were refused")

    before = json.loads((folder / "snapshot-before.json").read_text(encoding="utf-8"))
    after = snapshot()
    changed = [f"  {key}: {before.get(key)} -> {after.get(key)}" for key in sorted(set(before) | set(after)) if before.get(key) != after.get(key)]
    print("\noutside the sandbox, this Mac changed:" if changed else "\noutside the sandbox, this Mac did not change (config folder, shell startup files, command link, runner script, Services, Finder extensions).")
    if changed:
        problems += 1
        print("\n".join(changed))

    original = folder / "config-before.toml"
    if original.exists():
        now = folder / "home" / ".config" / "right-here" / "config.toml"
        diff = list(difflib.unified_diff(original.read_text(encoding="utf-8").splitlines(), now.read_text(encoding="utf-8").splitlines(),
                                         "config before", "config after", lineterm="", n=0))
        print("\nthe person's config, before and after:" + (" identical" if not diff else ""))
        print("\n".join("  " + line for line in diff))
    for name in ["home/.config/right-here/config.toml"]:
        config = folder / name
        print(f"\n{name}: " + ("present" if config.exists() else "absent"))
    return 1 if problems else 0


def main() -> int:
    arguments = sys.argv[1:]
    if len(arguments) >= 2 and arguments[0] == "prepare":
        rh = ROOT / ".build" / "debug" / "rh"
        config = None
        rest = arguments[2:]
        while rest:
            option, value = rest[0], rest[1] if len(rest) > 1 else sys.exit(f"{rest[0]} needs a value")
            if option == "--rh":
                rh = Path(value)
            elif option == "--config":
                config = Path(value)
            else:
                sys.exit(f"unknown option {option}")
            rest = rest[2:]
        prepare(Path(arguments[1]), rh, config)
        return 0
    if len(arguments) == 2 and arguments[0] == "report":
        return report(Path(arguments[1]))
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
