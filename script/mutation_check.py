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
     "if let missing = context.firstMissingPath(facts: facts) { throw PlanError.pathNotFound(missing.path) }", "if false { }"),
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
    ("a role-mismatched default terminal is picked", "Sources/RightHereCore/Planner/DefaultApps.swift",
     "apps.filter { $0.role == role }.compactMap { app in", "apps.compactMap { app in"),
    ("a ping waits for a request slot like a tool call", "Sources/RightHereMCP/MCPServer.swift",
     'case .object: return message["method"]?.stringValue == "tools/call"', "case .object: return true"),
    ("the server holds any number of tool calls", "Sources/RightHereMCP/MCPServer.swift",
     "guard held < outstanding, heldBytes + bytes <= queuedBytes else { return false }", "guard heldBytes + bytes <= queuedBytes else { return false }"),
    ("the server holds any amount of request data", "Sources/RightHereMCP/MCPServer.swift",
     "guard held < outstanding, heldBytes + bytes <= queuedBytes else { return false }", "guard held < outstanding else { return false }"),
    ("copy-path.shell-quoted follows the login shell again", "Sources/RightHereCore/Paths/PathStyle.swift",
     "return Self.shellQuotedForAnyShell(path)", "return ShellQuoting.quote(path, for: facts.shellFlavor)"),
    ("a terminal may open a new file", "Sources/RightHereCore/Planner/Planner.swift",
     "$0.role != .terminal && $0.installedBundleID(facts: facts) != nil", "$0.installedBundleID(facts: facts) != nil"),
    ("open_with may name a terminal in the config", "Sources/RightHereCore/Config/ConfigBuilder+NewFile.swift",
     "if found.role == .terminal {", "if false {"),
    ("a link that points nowhere opens the folder around it", "Sources/RightHereCore/Context/HereContext.swift",
     "// Neither gives a folder, and the folder around it is not what was asked for.\n        case nil: return nil",
     "// Neither gives a folder, and the folder around it is not what was asked for.\n        case nil: return Self.directory(from: first.deletingLastPathComponent(), facts: facts)"),
    ("process input is written on the Swift concurrency pool", "Sources/RightHereKit/ProcessRunner.swift",
     "DispatchQueue.global(qos: .userInitiated).async {", "Task.detached {"),
    ("an absolute path is judged by its first Character", "Sources/RightHereCore/Context/ContextInput.swift",
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
     'if environment["RH_NO_UI"] != nil, let program = Self.screenProgram(of: step) {',
     'if environment["RH_NO_UI"] != nil, let program = Self.screenProgram(of: step), program.isEmpty {'),
    ("RH_NO_UI is fooled by /usr/bin/env or a different spelling of the path", "Sources/RightHereKit/ProcessRunner.swift",
     "if screenPrograms.contains(executable) { return executable }", "if screenPrograms.contains(step.executable) { return step.executable } else if true { return nil }"),
    ("extra quotes before a closing triple quote hide what follows", "Sources/RightHereCore/Quoting/NestingDepth.swift",
     "while extra < 2, index < bytes.count", "while extra < 0, index < bytes.count"),
    ("a long dotted TOML key reaches the decoder", "Sources/RightHereCore/Quoting/NestingDepth.swift",
     "if chain > limit { return true }", "if chain > limit * 1_000_000 { return true }"),
    ("the probe's interrupt handler leaves the request behind", "Sources/RightHereKit/ProbeMarker.swift",
     "        _ = claim(in: paths)\n        reenableExtension()", "        reenableExtension()\n        _ = claim(in: paths)"),
    ("copied paths use the decomposed URL spelling again", "Sources/RightHereCore/Paths/PathStyle.swift",
     "let path = facts.onDiskPath(url)\n        let name", "let path = url.path\n        let name"),
    ("the Services are removed before the new ones are written", "Sources/RightHereKit/Installer.swift",
     "        try fileManager.createDirectory(at: locations.services, withIntermediateDirectories: true)\n        // A name that does not",
     "        try removeServices()\n        try fileManager.createDirectory(at: locations.services, withIntermediateDirectories: true)\n        // A name that does not"),
    ("an interrupt is not wired to the cleanup", "Sources/RightHereKit/ProbeMarker.swift",
     "            source.resume()\n            return source", "            return source"),
    ("a config cut off inside an open bracket reaches the TOML library as it is", "Sources/RightHereCore/Config/ConfigParser.swift",
     'return try TOMLTable(source: text + "\\n")', "return try TOMLTable(source: text)"),
    ("a huge config file is read and parsed", "Sources/RightHereKit/ConfigStore.swift",
     "as? Int, size > maxConfigBytes {", "as? Int, size > Int.max {"),
    ("a bidirectional control is printed as it is", "Sources/RightHereCore/Quoting/ScalarEditing.swift",
     "if Self.bidiControls.contains(scalar) {", "if false {"),
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
    ("a NUL in a path is accepted", "Sources/RightHereCore/Context/ContextInput.swift",
     'guard !path.unicodeScalars.contains("\\0") else', "guard true else"),
    ("a .. after a symbolic link is resolved by reading the text", "Sources/RightHereKit/PathHazard.swift",
     "if isSymbolicLink(\"/\" + names.joined(separator: \"/\")) { return true }", "if false { return true }"),
    ("a preset prompt with a newline reaches the terminal", "Sources/RightHereCore/Planner/Planner.swift",
     "if let reason = PresetTemplate.typingRefusal(prompt) { throw PlanError.unsafePrompt(preset: id, reason: reason) }",
     "if false, let reason = PresetTemplate.typingRefusal(prompt) { throw PlanError.unsafePrompt(preset: id, reason: reason) }"),
    ("a preset prompt is not checked for control characters", "Sources/RightHereCore/Presets/AgentPreset.swift",
     "if ShellQuoting.containsControlCharacter(prompt) {", "if false {"),
    ("a preset prompt is typed unquoted", "Sources/RightHereCore/Planner/Planner.swift",
     "words.append(ShellQuoting.quote(prompt, for: .posix))", "words.append(prompt)"),
    ("a preset prompt may start with a dash", "Sources/RightHereCore/Presets/AgentPreset.swift",
     'if prompt.unicodeScalars.first == "-" {', "if false {"),
    ("a preset prompt may hold a backslash", "Sources/RightHereCore/Presets/AgentPreset.swift",
     'if prompt.unicodeScalars.contains("\\\\") {', "if false {"),
    ("a preset takes any number of files", "Sources/RightHereCore/Presets/AgentPreset.swift",
     "if count > maxFiles {", "if false {"),
    ("a selected folder is named as a file in a preset", "Sources/RightHereCore/Planner/Planner.swift",
     "func presetFiles(in context: HereContext) -> [URL] {\n        context.items.filter { facts.isDirectory($0) == false }",
     "func presetFiles(in context: HereContext) -> [URL] {\n        context.items"),
    ("the config accepts a preset prompt that cannot be typed", "Sources/RightHereCore/Config/ConfigBuilder+Presets.swift",
     "if let refusal = PresetTemplate.typingRefusal(prompt) {", "if false, let refusal = PresetTemplate.typingRefusal(prompt) {"),
    ("pull overwrites a locally changed config without --force", "Sources/RightHereCore/Config/SyncState.swift",
     "case .localAhead, .diverged: return force ? .proceed : .refuse(.localChanged)", "case .localAhead, .diverged: return .proceed"),
    ("push overwrites a changed folder copy without --force", "Sources/RightHereCore/Config/SyncState.swift",
     "case .remoteAhead, .diverged: return force ? .proceed : .refuse(.remoteChanged)", "case .remoteAhead, .diverged: return .proceed"),
    ("a sync write is not atomic", "Sources/RightHereKit/AtomicFile.swift",
     r'''let temporary = folder.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, mode)''',
     """let temporary = destination
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_TRUNC, mode)"""),
    ("a forced push overwrites a copy iCloud has not downloaded", "Sources/RightHereCore/Config/SyncState.swift",
     "anything this machine knows.\n        case .remoteEvicted: return .refuse(.remoteEvicted)",
     "anything this machine knows.\n        case .remoteEvicted: return force ? .proceed : .refuse(.remoteEvicted)"),
    ("a sync copy that does not validate is pulled", "Sources/RightHereKit/ConfigSync.swift",
     "if !problems.isEmpty { throw ConfigSyncError.invalid(problems, file: current.remoteFile.path) }",
     "if false { throw ConfigSyncError.invalid(problems, file: current.remoteFile.path) }"),
    ("a config with a secret-looking key is synced", "Sources/RightHereCore/Config/SyncValidation.swift",
     "if !keys.isEmpty { problems.append(.secretKeys(keys)) }", "if false { problems.append(.secretKeys(keys)) }"),
    ("a pull replaces a symlinked config with a regular file", "Sources/RightHereKit/ConfigSync.swift",
     "let destination = paths.configFile.resolvingSymlinksInPath()", "let destination = paths.configFile"),
    ("the Finder extension's facts do not forward the on-disk spelling", "Sources/RightHereKit/CachingSystemFacts.swift",
     "public func onDiskPath(_ url: URL) -> String { base.onDiskPath(url) }", "public func onDiskPath(_ url: URL) -> String { url.path }"),
    ("pull accepts launch commands without --allow-commands", "Sources/RightHereKit/ConfigSync.swift",
     "if !current.pendingCommands.isEmpty, !allowCommands { throw", "if false, !current.pendingCommands.isEmpty, !allowCommands { throw"),
    ("--force approves launch commands", "Sources/RightHereKit/ConfigSync.swift",
     "if !current.pendingCommands.isEmpty, !allowCommands { throw", "if !current.pendingCommands.isEmpty, !allowCommands, !force { throw"),
    ("a changed launch command counts as one this Mac already has", "Sources/RightHereCore/Config/LaunchCommands.swift",
     "before[entry.place] == entry.value ? nil : Change(", "before[entry.place] != nil ? nil : Change("),
    ("a launch command is printed with its control characters", "Sources/RightHereCore/Config/LaunchCommands.swift",
     '.withControlCharactersEscaped + "\\""', ' + "\\""'),
    ("a control character in config text reaches the terminal", "Sources/RightHereCore/Config/ConfigDiagnostic.swift",
     "self.message = message.withControlCharactersEscaped", "self.message = message"),
    ("a control character in a config key reaches the terminal", "Sources/RightHereCore/Config/ConfigDiagnostic.swift",
     "self.path = path.withControlCharactersEscaped", "self.path = path"),
    ("a secret-looking key is listed with its control characters", "Sources/RightHereCore/Config/SyncValidation.swift",
     'found.append(here.joined(separator: ".").withControlCharactersEscaped)', 'found.append(here.joined(separator: "."))'),
    ("a problem in an overlay key is filed under another spelling than the diagnostic's", "Sources/RightHereCore/Config/ConfigMerge.swift",
     "keyOrigins[Self.dotted(path)] = layer", 'keyOrigins[path.joined(separator: ".")] = layer'),
    ("the MCP config check prints what it quotes from the config unfenced", "Sources/RightHereMCP/Tools.swift",
     "Fence.wrap($0.summary(file: loaded.file))", "$0.summary(file: loaded.file)"),
    ("the MCP doctor prints what it quotes unfenced", "Sources/RightHereMCP/Tools.swift",
     '": " + Fence.wrap($0)', '": " + $0'),
    ("a path is cut into components by Character where the kernel cuts by scalar", "Sources/RightHereKit/PathHazard.swift",
     'for component in path.unicodeScalars.split(separator: "/", omittingEmptySubsequences: true) {',
     'for component in path.split(separator: "/", omittingEmptySubsequences: true).map({ $0.unicodeScalars }) {'),
    ("a relative path is told from an absolute one by its first Character in the hazard check", "Sources/RightHereCore/Context/ContextInput.swift",
     'hasLinkBeforeDotDot(expanded.unicodeScalars.first == "/" ? expanded :', 'hasLinkBeforeDotDot(expanded.hasPrefix("/") ? expanded :'),
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
            elif "\u2718 Test" in output or "unexpected signal code" in output:
                # A test host that dies by a signal (SIGPIPE, SIGBUS) is as good as a failed test.
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
