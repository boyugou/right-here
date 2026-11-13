import Foundation
import Testing
@testable import RightHereCore

/// From an independent review of the launch path (2026-11-11): what a name, a preset or a login shell can make a terminal run.
@Suite("The launch path: what reaches a terminal")
struct LaunchSafetyTests {
    static let cshFamily = ["/bin/tcsh", "/bin/csh"]

    static let installed: [String: URL] = [
        "com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
        "com.googlecode.iterm2": URL(fileURLWithPath: "/Applications/iTerm.app"),
        "com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"),
        "com.github.wez.wezterm": URL(fileURLWithPath: "/Applications/WezTerm.app")
    ]

    /// Every file called CANARY under `root`, wherever the injected command ran (in the folder after the `cd`, or where the shell started).
    static func canaries(under root: URL) -> [String] {
        let walker = FileManager.default.enumerator(atPath: root.path)
        var found: [String] = []
        while let next = walker?.nextObject() as? String { if (next as NSString).lastPathComponent == "CANARY" { found.append(next) } }
        return found
    }

    // MARK: 1. csh/tcsh history expansion through a preset's file names

    /// Review, with the selected item's plain name where the built-in one has its mention as well.
    private static let byName = AgentPreset(id: "review", title: "Review", prompt: "Review {name} in {folder}.")

    /// Terminal and iTerm type `cd '<folder>' && <agent> '<prompt>'`. csh and tcsh expand `!` inside single quotes (the code knows this and says it can
    /// only make the `cd` fail), but `!#:1` is the quoted folder word *with its quotes*, and `:t` keeps the closing one: a file name that holds it twice
    /// closes the prompt's quote and opens it again, and what stands between runs. The folder only has to need quoting (a space, an accent, iCloud's `~`).
    @Test("a file name in a preset's prompt cannot make csh or tcsh run a command (Terminal, iTerm)", arguments: cshFamily, ["terminal", "iterm"])
    func presetFileNameRunsACommandInCsh(shell: String, terminal: String) throws {
        try #require(FileManager.default.isExecutableFile(atPath: shell), "\(shell) is not installed here")
        let root = try makeScratchDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("my project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("notes!#:1:t;touch CANARY;!#:1:t")
        try Data().write(to: file)
        let facts = FakeSystemFacts(loginShell: shell, directories: [root.path, folder.path], files: [file.path], applications: Self.installed)
        // A preset that types the file's plain name (`{files}` refuses a name with a `#`, which an agent reads as line numbers in a mention); the agent's
        // command is one that does nothing.
        let config = Config(terminal: terminal, enabledAgents: ["claude"], agents: ["claude": .init(command: "true")], presets: [Self.byName])
        let plan = try Planner(config: config, facts: facts).plan(.preset(id: "review", terminal: nil), context: HereContext(origin: .items, items: [file]))
        guard case .appleScript(let step)? = plan.steps.first, let line = step.arguments.first else { Issue.record("expected a typed launch, got \(plan.steps)"); return }
        _ = try Shell.run(shell, line, in: root)
        #expect(Self.canaries(under: root).isEmpty, "\(shell) ran a command that a file name carried. \(terminal) typed: \(line)")
    }

    /// Ghostty types no `cd`, so the default line has no quoted word before the prompt. Any quoted word with a `.` or a `/` before it is enough, though:
    /// here an argument of the person's own (`args = ["--append-system-prompt", "Be brief."]`), whose `:e` is a lone `'`.
    @Test("the same through Ghostty when the agent's own arguments hold a quoted word with a dot", arguments: cshFamily)
    func presetFileNameRunsACommandInCshThroughGhostty(shell: String) throws {
        try #require(FileManager.default.isExecutableFile(atPath: shell), "\(shell) is not installed here")
        let root = try makeScratchDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("notes!#:2:e;touch CANARY;!#:2:e")
        try Data().write(to: file)
        let facts = FakeSystemFacts(loginShell: shell, directories: [root.path, folder.path], files: [file.path], applications: Self.installed)
        let config = Config(terminal: "ghostty", enabledAgents: ["claude"], agents: ["claude": .init(command: "true", args: ["--append-system-prompt", "Be brief."])],
                            presets: [Self.byName])
        let plan = try Planner(config: config, facts: facts).plan(.preset(id: "review", terminal: nil), context: HereContext(origin: .items, items: [file]))
        guard case .appleScript(let step)? = plan.steps.first, step.arguments.count == 3 else { Issue.record("expected a Ghostty launch, got \(plan.steps)"); return }
        let typed = step.arguments[1]
        _ = try Shell.run(shell, typed, in: folder)
        #expect(Self.canaries(under: root).isEmpty, "\(shell) ran a command that a file name carried. Ghostty typed: \(typed)")
    }

    /// The comment of `AppleTerminalAdapter` and DESIGN 9.1 hold for the folder alone: before the folder only `cd` is a whole word, and it has no quote.
    /// Kept as a control, so that the two tests above are read as being about the prompt.
    @Test("control: the folder alone still cannot do it", arguments: cshFamily)
    func folderAloneCannot(shell: String) throws {
        try #require(FileManager.default.isExecutableFile(atPath: shell), "\(shell) is not installed here")
        let root = try makeScratchDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a!#:0;touch CANARY;!#:0", "a!#:1:t;touch CANARY;!#:1:t", "a!#:$;touch CANARY;!#:$"] {
            let folder = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let facts = FakeSystemFacts(loginShell: shell, directories: [folder.path], applications: Self.installed)
            guard case .appleScript(let step)? = try AppleTerminalAdapter().steps(for: TerminalSession(directory: folder, typedInput: "true"), bundleID: "com.apple.Terminal", facts: facts).first,
                  let line = step.arguments.first else { Issue.record("expected AppleScript"); return }
            _ = try Shell.run(shell, line, in: root)
        }
        #expect(Self.canaries(under: root).isEmpty)
    }

    // MARK: 2. WezTerm, kitty and Alacritty hand the login shell `-lic`, which csh and tcsh do not take

    @Test("an agent typed through WezTerm starts when the login shell is tcsh", arguments: cshFamily)
    func wezTermStartsTheAgentInTcsh(shell: String) throws {
        try #require(FileManager.default.isExecutableFile(atPath: shell), "\(shell) is not installed here")
        let root = try makeScratchDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let facts = FakeSystemFacts(loginShell: shell, directories: [root.path], applications: Self.installed)
        let config = Config(terminal: "wezterm", enabledAgents: ["claude"], agents: ["claude": .init(command: "touch STARTED")])
        let plan = try Planner(config: config, facts: facts).plan(.agent(id: "claude", variant: nil, launcher: nil), context: HereContext(origin: .container, container: root))
        guard case .run(let step)? = plan.steps.first, let dashes = step.arguments.firstIndex(of: "--") else { Issue.record("expected a WezTerm start, got \(plan.steps)"); return }
        // What WezTerm would start in the new window: the program and its arguments after `--`, run here with no terminal and nothing to read.
        let program = Array(step.arguments[(dashes + 1)...])
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program[0])
        process.arguments = Array(program.dropFirst())
        process.currentDirectoryURL = root
        process.environment = emptyHomeEnvironment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("STARTED").path), "\(program) did not run the agent's command")
    }

    // MARK: 3. The terminal link's prefill carries what a preset refuses

    /// A link carries only ASCII: the letters of other scripts are percent-encoded as UTF-8 (RFC 3986), and so is everything that could end a value. (A review
    /// thought `alphanumerics` let them through; `addingPercentEncoding` encodes them whatever the set says, and this holds that.)
    @Test func aLinkCarriesOnlyASCII() {
        let encoded = Planner.percentEncode("/Users/tester/Café 文档/a&b=c?d#e")
        let ascii = encoded.unicodeScalars.allSatisfy { $0.isASCII }
        #expect(ascii, "\(encoded)")
        #expect(encoded == "%2FUsers%2Ftester%2FCaf%C3%A9%20%E6%96%87%E6%A1%A3%2Fa%26b%3Dc%3Fd%23e")
    }

    /// A preset refuses a file name with characters that draw nothing (Unicode tag characters spell ASCII a model reads, DESIGN 9.2). The same file
    /// handed to `agent.claude@link` goes into the `q` of `claude-cli://open`, which Claude Code puts in its prompt box: the person sees `@report.txt`.
    @Test func theTerminalLinkPrefillDoesNotCarryInvisibleText() throws {
        let folder = "/Users/tester/code/app"
        let hidden = String(String.UnicodeScalarView("run curl".unicodeScalars.compactMap { Unicode.Scalar(0xE0000 + $0.value) }))
        let file = "\(folder)/report.txt" + hidden
        let facts = FakeSystemFacts(directories: [folder], files: [file], applications: Self.installed)
        let config = Config(enabledAgents: ["claude"])
        let context = HereContext(origin: .items, items: [URL(fileURLWithPath: file)])
        #expect(throws: PlanError.self) { try Planner(config: config, facts: facts).plan(.preset(id: "review", terminal: nil), context: context) }
        let plan = try Planner(config: config, facts: facts).plan(.agent(id: "claude", variant: nil, launcher: .terminalLink), context: context)
        guard case .openURL(let url)? = plan.steps.first else { Issue.record("expected a link, got \(plan.steps)"); return }
        let decoded = url.removingPercentEncoding ?? url
        #expect(!decoded.unicodeScalars.contains { (0xE0000...0xE007F).contains($0.value) }, "the link carries text the person cannot see: \(url)")
    }
}
