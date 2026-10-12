#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Check that the tests notice when a protection is taken away.

Each mutant below removes or weakens one protection the security notes (docs/DESIGN.md, section 9) rely on:
quoting that escapes a quote, the refusal of a path that does not exist, the MCP budget, the probe request's
atomic claim and expiry, and so on. The script applies the change to a throwaway clone of HEAD, runs the whole
test suite, and expects a test to fail. A mutant the tests do not notice is a hole in the tests; a mutant whose
pattern no longer matches the code, or that does not compile, needs its entry updated (the code moved).

Slow the first time (the clone builds from scratch), then about 15 seconds a mutant. Run it after touching
quoting, planning, the MCP server, the process runner or the Finder probe.

    ./script/mutation_check.py              all mutants
    ./script/mutation_check.py --list       what they are
    ./script/mutation_check.py 3 7          only these
"""
import os
import pathlib
import re
import signal
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent

# (what is taken away, file, text to replace, replacement)
MUTANTS = [
    ("posix quote does not escape a quote", "Sources/RightHereCore/Quoting/ShellQuoting.swift",
     '''return "'" + value.scalarReplacing(["'": "'\\\\''"]) + "'"''', '''return "'" + value + "'"'''),
    ("typing accepts control characters", "Sources/RightHereCore/Quoting/ShellQuoting.swift",
     "if value.unicodeScalars.contains(where: { isControl($0) }) {\n            throw .unsafeForTyping(value)", "if false {\n            throw .unsafeForTyping(value)"),
    ("missing paths are never reported", "Sources/RightHereCore/Context/HereContext.swift",
     "items.first(where: { facts.itemState($0) == .missing })", "items.first(where: { facts.itemState($0) == .unreadable })"),
    ("planner does not refuse a missing path", "Sources/RightHereCore/Planner/Planner.swift",
     "else if let missing = context.firstMissingPath(facts: facts) { throw PlanError.pathNotFound(missing.path) }", "else if false { }"),
    ("Terminal.app accepts a backslash", "Sources/RightHereCore/Terminals/AppleTerminalAdapter.swift",
     'if directory.unicodeScalars.contains("\\\\") {', "if false {"),
    ("Terminal.app quotes for the login shell again", "Sources/RightHereCore/Terminals/AppleTerminalAdapter.swift",
     "ShellQuoting.quote(directory, for: .posix)", "ShellQuoting.quote(directory, for: facts.shellFlavor)"),
    ("reveal is free", "Sources/RightHereMCP/MCPServer.swift",
     "case .reveal(let paths): return total + max(1, Set(paths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }).count)", "case .reveal: return total"),
    ("the limiter allows anything", "Sources/RightHereMCP/MCPServer.swift",
     "<= budget else { return .tooMany }", "<= budget * 1000 else { return .tooMany }"),
    ("an old probe request is honoured", "Sources/RightHereKit/ProbeMarker.swift",
     "abs(now.timeIntervalSince(modified)) < lifetime", "abs(now.timeIntervalSince(modified)) < 1e12"),
    ("the probe request is not consumed when it is claimed", "Sources/RightHereKit/ProbeMarker.swift",
     "guard rename(marker, mine) == 0 else { return false }", "guard link(marker, mine) == 0 else { return false }"),
    ("tags forget the menu kind", "Sources/RightHereKit/ActionTags.swift",
     "return (kindNumber << Self.numberBits) | position", "return position"),
    ("any JSON-RPC id is valid", "Sources/RightHereMCP/MCPServer.swift",
     "id.stringValue != nil || id.intValue != nil", "true"),
    ("maxItems is not enforced", "Sources/RightHereMCP/ArgumentValidator.swift",
     "if let most = schema[\"maxItems\"]?.intValue, items.count > most {", "if false, let most = schema[\"maxItems\"]?.intValue, items.count > most {"),
    ("an old log stays readable", "Sources/RightHereKit/RunLog.swift",
     "fchmod(descriptor, 0o600)", "_ = descriptor"),
    ("control characters escaped the Swift way again", "Sources/RightHereCore/Quoting/ScalarEditing.swift",
     'result += "\\\\u" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex', 'result += "\\\\u{" + hex + "}"'),
    ("dot-dot is not recognised", "Sources/RightHereCore/Paths/PathNormalization.swift",
     'current.elementsEqual("..".unicodeScalars)', 'current.elementsEqual("...".unicodeScalars)'),
    ("a timed-out process that ignores SIGTERM is never killed hard", "Sources/RightHereKit/ProcessRunner.swift",
     "Self.killLeftovers(of: process)", "_ = process"),
    ("the Files & Folders button is gone", "Sources/RightHereKit/FailureAlert.swift",
     "settingsURL = filesAndFoldersSettingsURL", "settingsURL = nil"),
    ("SIGPIPE can kill the MCP server", "Sources/RightHereMCP/MCPServer.swift",
     "_ = fcntl(descriptor, F_SETNOSIGPIPE, 1)", "_ = descriptor"),
    ("the runner is not told about a stopped process", "Sources/RightHereKit/ProcessRunner.swift",
     "terminatedAfter: cutOff.happened ? timeout : nil", "terminatedAfter: nil"),
    ("a role-mismatched default terminal is picked", "Sources/RightHereCore/Planner/Planner.swift",
     "order.compactMap { config.app(id: $0) }.filter { $0.role == role }", "order.compactMap { config.app(id: $0) }"),
    ("a ping waits for a request slot like a tool call", "Sources/RightHereMCP/MCPServer.swift",
     'case .object: return message["method"]?.stringValue == "tools/call"', "case .object: return true"),
    ("the server holds any number of tool calls", "Sources/RightHereMCP/MCPServer.swift",
     "guard held < outstanding, heldBytes + bytes <= queuedBytes else { return false }", "guard heldBytes + bytes <= queuedBytes else { return false }"),
    ("the server holds any amount of request data", "Sources/RightHereMCP/MCPServer.swift",
     "guard held < outstanding, heldBytes + bytes <= queuedBytes else { return false }", "guard held < outstanding else { return false }"),
    ("copy-path.shell-quoted follows the login shell again", "Sources/RightHereCore/Paths/PathStyle.swift",
     "return Self.shellQuotedForAnyShell(url.path)", "return ShellQuoting.quote(url.path, for: facts.shellFlavor)"),
    ("a terminal may open a new file", "Sources/RightHereCore/Planner/Planner.swift",
     "$0.role != .terminal && $0.installedBundleID(facts: facts) != nil", "$0.installedBundleID(facts: facts) != nil"),
    ("open_with may name a terminal in the config", "Sources/RightHereCore/Config/ConfigParser.swift",
     "if found.role == .terminal {", "if false {"),
    ("a link that points nowhere opens the folder around it", "Sources/RightHereCore/Context/HereContext.swift",
     "// Neither gives a folder, and the folder around it is not what was asked for.\n        case nil: return nil",
     "// Neither gives a folder, and the folder around it is not what was asked for.\n        case nil: return Self.directory(from: first.deletingLastPathComponent(), facts: facts)"),
    ("process input is written on the Swift concurrency pool", "Sources/RightHereKit/ProcessRunner.swift",
     "DispatchQueue.global(qos: .userInitiated).async {", "Task.detached {"),
    ("an absolute path is judged by its first Character", "Sources/RightHereMCP/Tools.swift",
     'path.unicodeScalars.first == "/"', 'path.hasPrefix("/")'),
    ("the rotated log keeps its old mode", "Sources/RightHereKit/RunLog.swift",
     "chmod(older.path, 0o600)", "_ = older"),
    ("a name the file system cannot hold counts as unreadable", "Sources/RightHereKit/LiveSystemFacts.swift",
     "case EACCES, EPERM, EIO, ESTALE, ETIMEDOUT: return .unreadable",
     "case EACCES, EPERM, EIO, ESTALE, ETIMEDOUT, ENAMETOOLONG, ELOOP, EBADF: return .unreadable"),
    ("an extension registration that vanished is not made again", "Sources/RightHereKit/Installer.swift",
     "guard await status().state != .enabled else { return false }", "guard true else { return false }"),
    ("a deeply nested JSON request reaches the decoder", "Sources/RightHereMCP/MCPServer.swift",
     "if NestingDepth.jsonExceeds(line.utf8, limit: maxNesting) {", "if false {"),
    ("a deeply nested config reaches the TOML parser", "Sources/RightHereCore/Config/ConfigParser.swift",
     "if NestingDepth.tomlExceeds(text, limit: maxNesting) {", "if false {"),
    ("RH_NO_UI lets open and osascript start", "Sources/RightHereKit/ProcessRunner.swift",
     'if environment["RH_NO_UI"] != nil, Self.screenPrograms.contains(step.executable) {', "if false {"),
    ("a name with a backslash and a control character gets a shell form", "Sources/RightHereCore/Paths/PathStyle.swift",
     'if path.unicodeScalars.contains("\\\\") && ShellQuoting.containsControlCharacter(path) {', "if false {"),
    ("a dry run shows an alert", "Sources/RightHereKit/FailureAlert.swift",
     "requested && !dryRun && environment", "requested && environment"),
    ("a plan summary prints names raw", "Sources/RightHereCore/Plan/LaunchPlan.swift",
     "self.summary = summary.withControlCharactersEscaped", "self.summary = summary"),
    ("the MCP doctor runs without the time limit", "Sources/RightHereMCP/Tools.swift",
     "runner: TimeLimitedRunner(base: server.runner, limit: server.executionLimit), rhPath: server.rhPath).run()", "runner: server.runner, rhPath: server.rhPath).run()"),
    ("uninstall removes any link", "Sources/RightHereKit/Installer.swift",
     'if resolved.contains("/Right Here.app/Contents/Helpers/") { return true }', "return true"),
    ("the runner takes every item", "Sources/RightHereKit/RunnerArguments.swift",
     "context.items.prefix(maxItems)", "context.items"),
    ("a NUL in an MCP path is accepted", "Sources/RightHereMCP/Tools.swift",
     'guard !path.unicodeScalars.contains("\\0") else', "guard true else"),
]


def main() -> int:
    arguments = sys.argv[1:]
    if arguments == ["--list"]:
        for index, (name, file, _old, _new) in enumerate(MUTANTS):
            print(f"{index:2}  {name}  ({file})")
        return 0
    chosen = {int(a) for a in arguments} if arguments else set(range(len(MUTANTS)))

    problems: list[str] = []
    with tempfile.TemporaryDirectory(prefix="rh-mutation-") as folder:
        clone = pathlib.Path(folder) / "clone"
        subprocess.run(["git", "clone", "--quiet", "--local", str(ROOT), str(clone)], check=True)
        for index, (name, file, old, new) in enumerate(MUTANTS):
            if index not in chosen:
                continue
            path = clone / file
            original = path.read_text(encoding="utf-8")
            if old not in original:
                problems.append(f"[{index}] the pattern for \"{name}\" is not in {file} any more; update the entry")
                print(f"[{index}] SKIPPED: {name}", flush=True)
                continue
            path.write_text(original.replace(old, new, 1), encoding="utf-8")
            started = time.time()
            hung = False
            # Its own session, so that on a hang the test host and every rh it started are stopped together.
            process = subprocess.Popen(["swift", "test"], cwd=clone, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, start_new_session=True)
            try:
                output, _ = process.communicate(timeout=900)
            except subprocess.TimeoutExpired:
                hung = True
                os.killpg(process.pid, signal.SIGKILL)
                output, _ = process.communicate()
            finally:
                path.write_text(original, encoding="utf-8")
            if hung:
                status = "HUNG"
                problems.append(f"[{index}] the tests hung instead of failing for: {name} ({file})")
            elif "\u2718 Test" in output:
                status = "killed"
            elif re.search(r"^error: |\.swift:\d+:\d+: error:", output, re.M):
                # A passing test run prints "error:" too (in the names of cases about error messages), so only a
                # compiler diagnostic or SwiftPM's own "error: " line counts.
                status = "DOES NOT COMPILE"
                problems.append(f"[{index}] \"{name}\" does not compile; fix the entry")
            else:
                status = "SURVIVED"
                problems.append(f"[{index}] no test noticed that: {name} ({file})")
            print(f"[{index}] {status} in {time.time() - started:.0f}s: {name}", flush=True)

    if problems:
        print("\n" + "\n".join(problems), file=sys.stderr)
        return 1
    print(f"ok: every one of {len(chosen)} removed protections made a test fail")
    return 0


if __name__ == "__main__":
    sys.exit(main())
