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

The test that fails is named in the output. A test whose result depends on how busy the machine is (LOAD_SENSITIVE)
fails on a loaded one whatever the code says, so a mutant that only it notices is run once more and, if that
fails the same way, reported as inconclusive instead of killed.

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
    ("the children of a killed process are left running", "Sources/RightHereKit/ProcessRunner.swift",
     "{ killpg(pid, SIGKILL) }", "{ _ = pid }"),
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
     "as? Int, size > ConfigParser.maxBytes {", "as? Int, size > Int.max {"),
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
    ("a terminal the config lists as another kind of app is not asked about", "Sources/RightHereCore/Config/LaunchCommands.swift",
     "for app in config.apps where app.role != .terminal && !terminalBundles.isDisjoint(with: app.bundleIDs) {",
     "for app in config.apps where false && !terminalBundles.isDisjoint(with: app.bundleIDs) {"),
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
     "$0.englishLines(quoting: Fence.wrap)", "$0.englishLines()"),
    ("the doctor's detail is printed unmarked where the caller asked for what it quotes to be marked", "Sources/RightHereKit/DoctorCheck.swift",
     '": " + quote($0.english())', '": " + $0.english()'),
    ("the doctor's note is printed unmarked where the caller asked for what it quotes to be marked", "Sources/RightHereKit/DoctorCheck.swift",
     '"       note: " + quote($0.english())', '"       note: " + $0.english()'),
    ("the doctor's fix is printed unmarked where the caller asked for what it quotes to be marked", "Sources/RightHereKit/DoctorCheck.swift",
     '"       fix: " + quote(fix.english())', '"       fix: " + fix.english()'),
    ("an agent's name, which the config chooses, is printed unmarked in the doctor", "Sources/RightHereKit/DoctorCheck.swift",
     "id.isAgent ? quote(title) : title", "title"),
    ("a path is cut into components by Character where the kernel cuts by scalar", "Sources/RightHereKit/PathHazard.swift",
     'for component in path.unicodeScalars.split(separator: "/", omittingEmptySubsequences: true) {',
     'for component in path.split(separator: "/", omittingEmptySubsequences: true).map({ $0.unicodeScalars }) {'),
    ("a relative path is told from an absolute one by its first Character in the hazard check", "Sources/RightHereCore/Context/ContextInput.swift",
     'hasLinkBeforeDotDot(expanded.unicodeScalars.first == "/" ? expanded :', 'hasLinkBeforeDotDot(expanded.hasPrefix("/") ? expanded :'),
    ("a disabled built-in app is still found by id", "Sources/RightHereCore/Config/Config.swift",
     "?? (disabledApps.contains(id) ? nil : KnownApps.app(id: id))", "?? KnownApps.app(id: id)"),
    ("a disabled built-in app is still offered", "Sources/RightHereCore/Config/Config.swift",
     "!replaced.contains($0.id) && !disabledApps.contains($0.id)", "!replaced.contains($0.id)"),
    ("the overlay's disabled built-in apps are not recorded", "Sources/RightHereCore/Config/ConfigLayers.swift",
     "result.config.disabledApps = Set(merged.disabled.filter { KnownApps.app(id: $0) != nil })", "result.config.disabledApps = []"),
    ("a preset that names a disabled agent is kept", "Sources/RightHereCore/Config/ConfigMerge.swift",
     'filterEntries(&root, at: ["preset"]) { Self.agent(of: $0).map(disabled.contains) ?? false }', 'filterEntries(&root, at: ["preset"]) { _ in false }'),
    ("a disabled terminal stays in a preset entry of the menu", "Sources/RightHereCore/Config/ConfigMerge.swift",
     "case .preset(_, let terminal?): return [terminal]", "case .preset(_, let terminal?): return []"),
    ("the menu entry of a dropped preset stays", "Sources/RightHereCore/Config/ConfigMerge.swift",
     "if case .preset(let id, _) = ref, goneIDs.contains(id) { return false }", "if false, case .preset(let id, _) = ref, goneIDs.contains(id) { return false }"),
    ("a dropped preset takes the entries of the built-in preset it replaced", "Sources/RightHereCore/Config/ConfigMerge.swift",
     "Set(droppedPresets.map(\\.id)).subtracting(AgentPreset.builtIn.map(\\.id))", "Set(droppedPresets.map(\\.id))"),
    ("an overlay preset replaces every shared preset", "Sources/RightHereCore/Config/ConfigMerge.swift",
     'static let idKeyedArrays: Set<String> = ["app", "template", "variant", "preset"]', 'static let idKeyedArrays: Set<String> = ["app", "template", "variant"]'),
    ("a duplicate in the overlay silently replaces the earlier one when the shared file has entries", "Sources/RightHereCore/Config/ConfigMerge.swift",
     ", replaced.insert(position).inserted {", " {"),
    ("a deleted local config reads as a local change", "Sources/RightHereCore/Config/SyncState.swift",
     "if snapshot.local == nil { return .remoteAhead }", "if false { return .remoteAhead }"),
    ("push writes through a link in the sync folder that leaves the folder", "Sources/RightHereKit/ConfigSync.swift",
     'guard target.path.hasPrefix(inside.hasSuffix("/") ? inside : inside + "/") else {', "guard true else {"),
    ("push replaces a link in the sync folder with a regular file", "Sources/RightHereKit/ConfigSync.swift",
     "let destination = try remoteWriteTarget(in: folder)", "let destination = folder.appendingPathComponent(Self.remoteFileName)"),
    ("an intent's failure text includes the config problems rh reported", "Sources/RightHereKit/IntentInvocation.swift",
     "&& $0.firstMatch(of: configProblem) == nil }", "}"),
    ("the preset prompt limit counts Characters, not bytes", "Sources/RightHereCore/Presets/AgentPreset.swift",
     "if prompt.utf8.count > AgentPreset.maxPromptBytes {", "if prompt.count > AgentPreset.maxPromptBytes {"),
    ("an editor named as a terminal is opened as one", "Sources/RightHereCore/Planner/DefaultApps.swift",
     "guard let app = config.terminalApp(id: id) else { throw PlanError.unknownTerminal(id) }",
     "guard let app = config.app(id: id) else { throw PlanError.unknownTerminal(id) }"),
]


# Tests whose result depends on how busy the machine is (they leave a margin of a second or two for a process to be
# stopped), so on a loaded one they fail whatever the code does.
LOAD_SENSITIVE: set[str] = set()


def failed_tests(output: str) -> set[str]:
    """The tests a run reports as failed. Swift Testing prints `✘ Test name() failed`, `✘ Test "display name" ... failed`
    and, for one case of a parameterized test, `✘ Test case ... to "display name" failed`."""
    names: set[str] = set()
    for match in re.finditer(r'✘ Test (?:case .*? to "([^"]+)"|(\w+)\(\)|"([^"]+)")', output):
        names.add(next(group for group in match.groups() if group))
    return names


def run_tests(clone: pathlib.Path) -> tuple[str, bool]:
    """`swift test` in the clone: what it printed, and whether it had to be killed for hanging."""
    # Its own session, so that on a hang the test host and every rh it started are stopped together.
    process = subprocess.Popen(["swift", "test"], cwd=clone, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=900)
        return output, False
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        return output, True


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
            try:
                # A run in which only a load-sensitive test failed says nothing, so it is tried once more.
                for _ in range(2):
                    output, hung = run_tests(clone)
                    if hung or failed_tests(output) - LOAD_SENSITIVE or "\u2718 Test" not in output:
                        break
            finally:
                path.write_text(original, encoding="utf-8")
            killers = sorted(failed_tests(output) - LOAD_SENSITIVE)
            if hung:
                status = "HUNG"
                problems.append(f"[{index}] the tests hung instead of failing for: {name} ({file})")
            elif killers:
                status = f"killed by {killers[0]}" + (f" and {len(killers) - 1} more" if len(killers) > 1 else "")
            elif "unexpected signal code" in output:
                # A test host that dies by a signal (SIGPIPE, SIGBUS) is as good as a failed test.
                status = "killed (the test host died)"
            elif "\u2718 Test" in output:
                status = "INCONCLUSIVE"
                problems.append(f"[{index}] only a load-sensitive test failed for: {name} ({file}); run it again when the machine is quieter")
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
