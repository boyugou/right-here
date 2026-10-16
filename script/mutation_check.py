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
     "try? await Task.sleep(for: .seconds(1))\n                Self.killLeftovers(of: process)", "try? await Task.sleep(for: .seconds(1))\n                _ = process"),
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
     "app.role == .terminal ? nil : app.installedBundleID(facts: facts)", "app.installedBundleID(facts: facts)"),
    ("a new file is opened with no app named when none is installed", "Sources/RightHereCore/Planner/Planner.swift",
     "            if let bundleID = newFileApp(for: template) {\n                steps.append(.open(OpenStep(bundleID: bundleID, targets: [path])))",
     "            let bundleID = newFileApp(for: template)\n            if true {\n                steps.append(.open(OpenStep(bundleID: bundleID, targets: [path])))"),
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
    ("extra quotes before a closing triple quote hide what follows", "Sources/RightHereCore/Quoting/TOMLScan.swift",
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
     "switch BoundedRead.read(file) {", "switch BoundedRead.read(file, limit: Int.max) {"),
    ("a config that cannot be read is taken for a missing one", "Sources/RightHereKit/ConfigStore.swift",
     'return (.unreadable(ConfigDiagnostic(severity: .error, path: "", message: "cannot read \\(file.path): \\(reason)")), true)', "return (.absent, false)"),
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
    ("a config that is there is replaced when setup is run without --force", "Sources/RightHereKit/ConfigStore.swift",
     "switch try AtomicFile.createExclusively(content, at: paths.configFile, beforeLink: beforeCreate) {",
     "switch try { () throws -> AtomicFile.Creation in try AtomicFile.write(content, to: paths.configFile); return .created }() {"),
    ("the config is created with a rename that replaces a file that appeared meanwhile", "Sources/RightHereKit/AtomicFile.swift",
     "if link(temporary.path, destination.path) == 0 { return .created }", "if rename(temporary.path, destination.path) == 0 { return .created }"),
    ("a trial under RH_HOME registers the Finder extension for the whole Mac", "Sources/RightHereKit/SetupRunner.swift",
     "guard systemWide else {\n            return SetupStep(.finderExtension, .skipped", "guard true else {\n            return SetupStep(.finderExtension, .skipped"),
    ("a trial under RH_HOME refreshes the system's Services cache", "Sources/RightHereKit/SetupRunner.swift",
     "            if systemWide {\n                _ = try? await runner.run(ProcessStep(executable: \"/System/Library/CoreServices/pbs\"",
     "            if true {\n                _ = try? await runner.run(ProcessStep(executable: \"/System/Library/CoreServices/pbs\""),
    ("a dry run of setup writes the config", "Sources/RightHereKit/SetupRunner.swift",
     "        if request.dryRun {\n            report.steps.append(SetupStep(.config,", "        if false {\n            report.steps.append(SetupStep(.config,"),
    ("the runner script passes any subcommand on, so a compromised extension could run rh setup --force", "Sources/RightHereKit/Installer.swift",
     "run|probe) ;;", "*) ;;"),
    ("an id that is not a known terminal or editor reaches the text of the config", "Sources/RightHereCore/Config/SetupChoices.swift",
     "if wanted.contains(where: { $0.id == id }) { return id }", "if true { return id }"),
    ("an agent that is not a known one reaches the text of the config", "Sources/RightHereCore/Config/SetupChoices.swift",
     "guard KnownAgents.agent(id: word) != nil else {", "guard true || KnownAgents.agent(id: word) != nil else {"),
    ("the Quick Actions are made from the config as it was before setup created it", "Sources/RightHereKit/SetupRunner.swift",
     "let config = planned ?? ConfigStore.load(paths: paths).config\n        let specs", "let config = Config.default\n        let specs"),
    ("the runner takes every item", "Sources/RightHereKit/RunnerArguments.swift",
     "context.items.prefix(maxItems)", "context.items"),
    ("a NUL in a path is accepted", "Sources/RightHereCore/Context/ContextInput.swift",
     'guard !path.unicodeScalars.contains("\\0") else', "guard true else"),
    ("a .. after a symbolic link is resolved by reading the text", "Sources/RightHereKit/PathHazard.swift",
     "if isSymbolicLink(\"/\" + names.joined(separator: \"/\")) { return true }", "if false { return true }"),
    ("a preset prompt with a newline reaches the terminal", "Sources/RightHereCore/Planner/Planner.swift",
     "if let problem = PresetTemplate.typingProblem(prompt) {",
     "if false, let problem = PresetTemplate.typingProblem(prompt) {"),
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
     "case .missing: return .remoteAhead", "case .missing: local = nil"),
    ("push writes through a link in the sync folder that leaves the folder", "Sources/RightHereKit/ConfigSync.swift",
     'guard target.path.hasPrefix(inside.hasSuffix("/") ? inside : inside + "/") else {', "guard true else {"),
    ("push replaces a link in the sync folder with a regular file", "Sources/RightHereKit/ConfigSync.swift",
     "let destination = try remoteWriteTarget(in: folder)", "let destination = folder.appendingPathComponent(Self.remoteFileName)"),
    ("an intent's failure text includes the config problems rh reported", "Sources/RightHereKit/IntentInvocation.swift",
     "&& $0.firstMatch(of: configProblem) == nil }", "}"),
    ("the preset prompt limit counts Characters, not bytes", "Sources/RightHereCore/Presets/AgentPreset.swift",
     "if prompt.utf8.count > AgentPreset.maxPromptBytes {", "if prompt.count > AgentPreset.maxPromptBytes {"),
    ("a variant's argument is typed unquoted", "Sources/RightHereCore/Planner/AgentLaunchResolution.swift",
     'variant: variant?.id ?? "", argument: argument)) }\n            words.append(ShellQuoting.quote(argument, for: .posix))',
     'variant: variant?.id ?? "", argument: argument)) }\n            words.append(argument)'),
    ("a variant's argument with a backslash is typed", "Sources/RightHereCore/Planner/AgentLaunchResolution.swift",
     'if argument.unicodeScalars.contains("\\\\") { return .failure(.variantArgument(', "if false { return .failure(.variantArgument("),
    ("an editor named as a terminal is opened as one", "Sources/RightHereCore/Planner/DefaultApps.swift",
     "guard let app = config.terminalApp(id: id) else { throw PlanError.unknownTerminal(id) }",
     "guard let app = config.app(id: id) else { throw PlanError.unknownTerminal(id) }"),
    ("a file past the size limit is read to find its size", "Sources/RightHereKit/BoundedRead.swift",
     "if info.st_size > limit { return .tooLarge(bytes: Int(info.st_size)) }", "if false { return .tooLarge(bytes: Int(info.st_size)) }"),
    ("launch commands are looked for in a file past the size limit", "Sources/RightHereCore/Config/LaunchCommands.swift",
     "guard data.count <= ConfigParser.maxBytes, var text = String(data: data, encoding: .utf8) else", "guard var text = String(data: data, encoding: .utf8) else"),
    ("a local config that cannot be read counts as a missing one", "Sources/RightHereKit/ConfigSync.swift",
     "case .tooLarge, .unreadable: snapshotLocal = .unknown", "case .tooLarge, .unreadable: snapshotLocal = .missing"),
    ("a name or title from the config may hold a control character", "Sources/RightHereCore/Config/ConfigBuilder.swift",
     "guard ShellQuoting.containsControlCharacter(text) else { return true }", "guard false else { return true }"),
    ("validate does not read the shared file on its own, so an error the overlay hides is passed", "Sources/RightHereCore/Config/ConfigLayers.swift",
     "        if case .text = local {\n            for error in ConfigParser.parse(baseText).diagnostics where error.severity == .error {",
     "        if false {\n            for error in ConfigParser.parse(baseText).diagnostics where error.severity == .error {"),
    ("a value in a plan is quoted without escaping its control characters", "Sources/RightHereCore/Quoting/ScalarEditing.swift",
     '''"\\"" + scalarReplacing(["\\\\": "\\\\\\\\", "\\"": "\\\\\\""]).withControlCharactersEscaped + "\\""''',
     '''"\\"" + scalarReplacing(["\\\\": "\\\\\\\\", "\\"": "\\\\\\""]) + "\\""'''),
    ("a terminal that types the folder is handed one with a control character", "Sources/RightHereCore/Planner/Planner.swift",
     "        if adapter.typesTheFolder {\n            do { try ShellQuoting.validateForTyping(directory.path) }",
     "        if false {\n            do { try ShellQuoting.validateForTyping(directory.path) }"),
    ("an adapter that says nothing is taken for one that types none of the folder", "Sources/RightHereCore/Terminals/TerminalAdapter.swift",
     "    public var typesTheFolder: Bool { true }\n}", "    public var typesTheFolder: Bool { false }\n}"),
    ("rh apps prints a name from the config raw", "Sources/rh/Commands/Actions.swift",
     "Output.print(line(row.id, row.name.withControlCharactersEscaped, row.role,", "Output.print(line(row.id, row.name, row.role,"),
    ("rh actions prints a title from the config raw", "Sources/rh/Commands/Actions.swift",
     "Output.print(id + info.title.withControlCharactersEscaped +", "Output.print(id + info.title +"),
    ("rh agents prints a name from the config raw", "Sources/rh/Commands/Actions.swift",
     "Output.column(row.name.withControlCharactersEscaped, 16)", "Output.column(row.name, 16)"),
    ("rh menu prints a title from the config raw", "Sources/rh/Commands/Actions.swift",
     'case .action: return pad + node.title.withControlCharactersEscaped + "    ("', 'case .action: return pad + node.title + "    ("'),
    ("the MCP action list prints titles unfenced", "Sources/RightHereMCP/Tools.swift",
     '"\\($0.id)  " + Fence.name($0.title)', '"\\($0.id)  " + $0.title'),
    ("the MCP menu preview prints titles unfenced", "Sources/RightHereMCP/Tools.swift",
     "json.fencing([\"title\"]).pretty()", "json.pretty()"),
    ("the MCP catalog prints names unfenced", "Sources/RightHereMCP/Tools.swift",
     "structured.fencing([\"name\", \"command\", \"bundleID\"]).pretty()", "structured.pretty()"),
    ("a worktree that existed before this run is discarded", "Sources/RightHereKit/GitWorktree.swift",
     "        guard created.wasCreated else { return false }", "        guard true else { return false }"),
    ("a worktree with a change in it is discarded", "Sources/RightHereKit/GitWorktree.swift",
     "check.status == 0, check.standardOutput.isEmpty else { return false }", "check.status == 0 else { return false }"),
    ("two runs in one second get the same worktree name", "Sources/RightHereKit/GitWorktree.swift",
     'return "rh/\\(Int(now.timeIntervalSince1970))-" + String(format: "%08x", random)', 'return "rh/\\(Int(now.timeIntervalSince1970))"'),
    ("an agent starts at the root of its worktree, not in the folder named", "Sources/rh/Commands/Run.swift",
     "return URL(fileURLWithPath: worktree.path + path.dropFirst(top.count))", "return worktree"),
    ("a preset is started with --bypass-permissions or --safe", "Sources/rh/Commands/Run.swift",
     "if isPreset, bypassPermissions || safe {", "if false, bypassPermissions || safe {"),
    ("--bypass-permissions, --safe, --arg or --worktree is accepted for an action that starts no agent", "Sources/rh/Commands/Run.swift",
     "if !launchesAnAgent, !named.isEmpty {", "if false, !launchesAnAgent, !named.isEmpty {"),
    ("git: the hook files of the repository still run", "Sources/RightHereKit/GitCommand.swift",
     '            ("core.hooksPath", "/dev/null"),\n            ("core.fsmonitor", "false")\n', '            ("core.fsmonitor", "false")\n'),
    ("git: the file system monitor of the repository still runs", "Sources/RightHereKit/GitCommand.swift",
     '            ("core.hooksPath", "/dev/null"),\n            ("core.fsmonitor", "false")\n', '            ("core.hooksPath", "/dev/null")\n'),
    ("git: a hook that the configuration names still runs", "Sources/RightHereKit/GitCommand.swift",
     'for hook in defined.hooks.sorted() { settings.append(("hook.\\(hook).enabled", "false")) }', '_ = defined.hooks'),
    ("git: a long-running filter of the repository still runs", "Sources/RightHereKit/GitCommand.swift",
     'for key in ["smudge", "clean", "process"] {', 'for key in ["smudge", "clean"] {'),
    ("git: the smudge filter of the repository still runs", "Sources/RightHereKit/GitCommand.swift",
     'for key in ["smudge", "clean", "process"] {', 'for key in ["clean", "process"] {'),
    ("git: the clean filter of the repository still runs", "Sources/RightHereKit/GitCommand.swift",
     'for key in ["smudge", "clean", "process"] {', 'for key in ["smudge", "process"] {'),
    ("git: a required filter that is blanked makes git fail", "Sources/RightHereKit/GitCommand.swift",
     'settings.append(("filter.\\(driver).required", "false"))', '_ = driver'),
    ("git: a partial clone fetches from its promisor remote", "Sources/RightHereKit/GitCommand.swift",
     'var environment = ["GIT_NO_LAZY_FETCH": "1", "GIT_CONFIG_COUNT": String(settings.count)]', 'var environment = ["GIT_CONFIG_COUNT": String(settings.count)]'),
    ("git: a pager may be started", "Sources/RightHereKit/GitCommand.swift",
     'arguments: ["--no-pager", "-C", directory] + arguments', 'arguments: ["-C", directory] + arguments'),
    ("git: the drivers are listed without their scope, so a file the configuration includes and config.worktree are missed", "Sources/RightHereKit/GitCommand.swift",
     '"config", "-z", "--show-scope", "--name-only", "--get-regexp"', '"config", "--local", "-z", "--name-only", "--get-regexp"'),
    ("git: the hooks the configuration names are not looked for", "Sources/RightHereKit/GitCommand.swift",
     '"^(filter|hook)\\\\."', '"^filter\\\\."'),
    ("git: a driver in the repository's local or worktree configuration is taken for the person's own", "Sources/RightHereKit/GitCommand.swift",
     'static let ownScopes: Set<String> = ["system", "global", "command"]', 'static let ownScopes: Set<String> = ["system", "global", "command", "local", "worktree"]'),
    ("git: the person's own filters are switched off too", "Sources/RightHereKit/GitCommand.swift",
     'static let ownScopes: Set<String> = ["system", "global", "command"]', 'static let ownScopes: Set<String> = []'),
    ("git: the list of worktrees is read as lines, so a folder name with a line break forges one", "Sources/RightHereKit/GitWorktree.swift",
     '["worktree", "list", "--porcelain", "-z"]', '["worktree", "list", "--porcelain"]'),
    ("git: the status that discards an unused worktree has no guard", "Sources/RightHereKit/GitWorktree.swift",
     'GitCommand.step(["status", "--porcelain", "--untracked-files=all"], in: created.worktreeURL.path, blanking: defined)',
     'ProcessStep(executable: GitCommand.executable, arguments: ["-C", created.worktreeURL.path, "status", "--porcelain", "--untracked-files=all"])'),
    ("git: removing a worktree has no guard", "Sources/RightHereKit/GitWorktree.swift",
     'let removed = try await runner.run(GitCommand.step(arguments, in: gitRoot.path, blanking: defined))',
     'let removed = try await runner.run(ProcessStep(executable: GitCommand.executable, arguments: ["-C", gitRoot.path] + arguments))'),
    ("git: removing a worktree does not look for what its own configuration defines", "Sources/RightHereKit/GitWorktree.swift",
     'if FileManager.default.fileExists(atPath: entry.path) { defined = defined.merging(', 'if false { defined = defined.merging('),
    ("git: deleting a branch does not switch off the hooks the configuration names", "Sources/RightHereKit/GitWorktree.swift",
     '["branch", "-d", "--", branch], in: gitRoot.path, blanking: defined)', '["branch", "-d", "--", branch], in: gitRoot.path, blanking: GitCommand.Defined())'),
    ("git: attaching to an existing branch has no filter guard", "Sources/RightHereKit/GitWorktree.swift",
     'let fallbackStep = GitCommand.step(["worktree", "add", "--", worktreeDir.path, branchName], in: gitRoot.path, blanking: defined)',
     'let fallbackStep = GitCommand.step(["worktree", "add", "--", worktreeDir.path, branchName], in: gitRoot.path, blanking: GitCommand.Defined())'),
    ("git: the list of worktrees has no time limit", "Sources/RightHereKit/GitWorktree.swift",
     'let result = try await runner.run(step, timeout: GitCommand.reading)', 'let result = try await runner.run(step)'),
    ("git: the list of what the repository defines has no time limit", "Sources/RightHereKit/GitCommand.swift",
     '                                           timeout: reading)', '                                           timeout: nil)'),
    ("git: deleting a branch has no time limit", "Sources/RightHereKit/GitWorktree.swift",
     'blanking: defined), timeout: GitCommand.reading)', 'blanking: defined), timeout: nil)'),
    ("git: a command stopped for its time is taken for one that answered", "Sources/RightHereKit/GitCommand.swift",
     'if let limit = result.terminatedAfter { throw', 'if false, let limit = result.terminatedAfter { throw'),
    ("worktrees: a worktree the person made can be removed", "Sources/RightHereKit/GitWorktree.swift",
     "let managed = named.filter { resolved($0.path).hasPrefix(base) }", "let managed = named"),
    ("a preset takes the second spelling of the default terminal", "Sources/RightHereCore/Actions/ActionRef.swift",
     "guard case .valid(let terminal) = Self.terminalSuffix(suffix), terminal != AgentLauncher.defaultWord else { return nil }",
     "guard case .valid(let terminal) = Self.terminalSuffix(suffix) else { return nil }"),
    ("a control character in an agent's args is typed", "Sources/RightHereCore/Config/ConfigBuilder+Agents.swift",
     "if extraArgs.contains(where: ShellQuoting.containsControlCharacter) {", "if false {"),
    ("the menu cache lives for a minute and a half", "Sources/RightHereKit/MenuCachePolicy.swift",
     "public static let lifetime: TimeInterval = 30", "public static let lifetime: TimeInterval = 90"),
    ("the setup window offers to remove a worktree Right Here did not make, and asks git about it", "Sources/RightHereKit/SetupWorktrees.swift",
     "guard row.canBeRemoved else {", "guard true else {"),
    ("an agent's args are typed unquoted", "Sources/RightHereCore/Planner/AgentLaunchResolution.swift",
     'argument: argument)) }\n            words.append(ShellQuoting.quote(argument, for: .posix))\n        }\n        return .success(words)',
     'argument: argument)) }\n            words.append(argument)\n        }\n        return .success(words)'),
    ("an agent's args with a backslash are typed", "Sources/RightHereCore/Planner/AgentLaunchResolution.swift",
     'if argument.unicodeScalars.contains("\\\\") { return .failure(.agentArgument(', "if false { return .failure(.agentArgument("),
    ("a dry run counts the Quick Actions from a config file that is not there yet", "Sources/RightHereKit/SetupRunner.swift",
     "let config = planned ?? ConfigStore.load(paths: paths).config\n        let specs", "let config = ConfigStore.load(paths: paths).config\n        let specs"),
    ("a trial says nothing of what is left for the person", "Sources/RightHereKit/SetupRunner.swift",
     "report.needsUser = SetupAdvice.needsUser(checks: rows, config: loaded.config, facts: facts)",
     "report.needsUser = systemWide ? SetupAdvice.needsUser(checks: rows, config: loaded.config, facts: facts) : []"),
    ("setup never tells the person to put ~/.local/bin on the PATH", "Sources/RightHereKit/SetupAdvice.swift",
     "if checks.first(where: { $0.id == .cliLink })?.detail?.key == .doctorCliNotOnPath {",
     "if false, checks.first(where: { $0.id == .cliLink })?.detail?.key == .doctorCliNotOnPath {"),
    ("setup never tells the person about the permission macOS asks for before the first agent starts", "Sources/RightHereKit/SetupAdvice.swift",
     "if let terminal = agentTerminalNeedingPermission(config: config, facts: facts) {",
     "if false, let terminal = agentTerminalNeedingPermission(config: config, facts: facts) {"),
    ("a real run that came before the edits does not say to run setup again after them", "Sources/RightHereKit/SetupAdvice.swift",
     'next.append(SetupNext("rh setup", why: "After the edits: it builds the Quick Actions from the config as you edited it (the Quick Actions of this run came from the file as it was), and checks everything again."))',
     "_ = 0"),
    ("a dry run that lists edits does not say to make them before the real run", "Sources/RightHereKit/SetupAdvice.swift",
     'guard !configEdits.isEmpty else { return [SetupNext(rerun, why: "The same without --dry-run: it makes the changes above.")] }',
     'if true { return [SetupNext(rerun, why: "The same without --dry-run: it makes the changes above.")] }'),
    ("setup runs from a translocated copy of the app, whose folder disappears when the app quits", "Sources/RightHereKit/SetupRunner.swift",
     "if InstallError.isTranslocated(rhPath) { throw InstallError.translocated }", "if false { throw InstallError.translocated }"),
    ("the Claude Code link handler is checked where nothing starts Claude Code through the link", "Sources/RightHereKit/Doctor.swift",
     "if claudeLinkIsOffered() { checks.append(claudeLinkCheck()) }", "checks.append(claudeLinkCheck())"),
    ("a pinned or recent folder in the state file may be a relative path", "Sources/RightHereCore/Config/StateStore.swift",
     'path.hasPrefix("/") ? (path as NSString).standardizingPath : nil', "(path as NSString).standardizingPath"),
    ("a state file may hold any number of recent folders", "Sources/RightHereCore/Config/StateStore.swift",
     'Array(folders(in: table, key: "recents").prefix(maxRecents))', 'folders(in: table, key: "recents")'),
    ("the MCP tool makes worktrees without the launch budget", "Sources/RightHereMCP/Tools.swift",
     "switch await server.launchLimiter.allow(cost: LaunchCost.worktree) {", "switch await server.launchLimiter.allow(cost: 0) {"),
    ("the extension remembers every folder it was ever asked about", "Sources/RightHereKit/CachingSystemFacts.swift",
     "if cache.count >= Self.maxDirectories {\n                cache = cache.filter", "if false {\n                cache = cache.filter"),
    ("a switched-on Finder extension that crashed is reported as healthy", "Sources/RightHereKit/Doctor.swift",
     "if let crashReports,\n", "if false, let crashReports,\n"),
    ("the whole doctor never looks at the extension's crash reports", "Sources/RightHereKit/Doctor.swift",
     "crashReports: ExtensionCrashes.reportsFolder(home: facts.homeDirectory)))", "crashReports: nil))"),
    ("crash reports from before the installed copy count against it", "Sources/RightHereKit/ExtensionCrashes.swift",
     "let cutoff = max(installed ?? .distantPast, now.addingTimeInterval(-window))", "let cutoff = now.addingTimeInterval(-window)"),
    ("the PATH row ignores what the person's login shell says", "Sources/RightHereKit/Doctor.swift",
     " || Self.pathListsFolder(shell.path ?? [], installer.locations.localBin)", ""),
    ("the login shell is asked for its PATH although the link is missing or this process already has the folder", "Sources/RightHereKit/Doctor.swift",
     "let wantPath = linked && !processPath(contains: installer.locations.localBin)", "let wantPath = true"),
    ("a login shell that said nothing is called a wrong PATH", "Sources/RightHereKit/Doctor.swift",
     "} else if shell.path == nil {", "} else if false {"),
    ("a PATH entry must be the folder letter for letter", "Sources/RightHereKit/Doctor.swift",
     "return wanted.contains(url.standardizedFileURL.path) || wanted.contains(url.resolvingSymlinksInPath().path)", "return entry == folder.path"),
    ("a symbolic link on the way makes the folder another one", "Sources/RightHereKit/Doctor.swift",
     "let wanted = Set([folder.standardizedFileURL.path, folder.resolvingSymlinksInPath().path])", "let wanted = Set([folder.standardizedFileURL.path])"),
    ("the gate takes the xcodebuild shim of the Command Line Tools for a full Xcode", "script/verify_all.sh",
     "xcodebuild -version >/dev/null 2>&1 && have_xcode=1 || have_xcode=0", "command -v xcodebuild >/dev/null && have_xcode=1 || have_xcode=0"),
    ("the gate notices a missing uv only after the build and the tests", "script/verify_all.sh",
     'command -v uv >/dev/null || { echo "error: uv is not installed, and the checks after the tests run on it. Install it with: brew install uv" >&2; exit 1; }', ""),
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
    # A run that is killed can be cut inside a multi-byte character (the checkmarks of the test report are three bytes), so what cannot
    # be decoded is replaced and not an error: strict decoding crashed this script on the very hang it is there to report.
    process = subprocess.Popen(["swift", "test"], cwd=clone, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, errors="replace", start_new_session=True)
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
            occurrences = original.count(old)
            if occurrences != 1:
                problems.append(f"[{index}] the pattern for \"{name}\" is in {file} {occurrences} times, not once; make it match exactly once")
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
