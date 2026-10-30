import Foundation
import Testing
@testable import RightHereCore

/// A seeded sequence of random edits is applied to a config and to a plain model of it (the lists and the entries), and the two have to agree after each one; the file
/// has to read without an error every time, and the comments in it have to survive.
@Suite("ConfigDocument: random edits agree with a model")
struct ConfigDocumentFuzzTests {
    private struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    private static let start = """
    # Mine.
    version = 1

    [general]
    terminal = "ghostty" # keep
    agents = ["claude", "codex"]

    [menu]
    # The menu, in the order I like.
    items = [
        "open-terminal", # first
        "open-editor",
        # separator below
        "-",
        "agents",
    ]

    [copy_path]
    styles = ["absolute", "tilde"]

    # Presets.
    [[preset]]
    id = "alpha"
    title = "Alpha"
    prompt = "Alpha {files}"

    # The second.
    [[preset]]
    id = "beta"
    title = "Beta" # b
    prompt = "Beta {files}"
    """ + "\n"

    private static let menuPool = ["open-terminal", "open-editor", "open-with", "agents", "agents-more", "-", "new-file", "copy-path", "presets"]
    private static let agentPool = ["claude", "codex", "gemini", "opencode", "aider"]
    private static let stylePool = ["absolute", "tilde", "git-relative", "name", "parent", "file-url"]

    @Test("random edits keep the file readable, the comments in place and the model in step", arguments: Array(1...24))
    func randomEdits(seed: Int) throws {
        var random = Generator(state: UInt64(seed) &* 7919 &+ 17)
        var document = ConfigDocument(Self.start)
        var menu = ["open-terminal", "open-editor", "-", "agents"]
        var agents = ["claude", "codex"]
        var styles = ["absolute", "tilde"]
        var presets = ["alpha", "beta"]
        var spare = 0
        for step in 0..<80 {
            let operation = random.next(11)
            var label = "op \(operation)"
            switch operation {
            case 0, 1:
                let item = Self.menuPool[random.next(Self.menuPool.count)]
                let position = random.next(menu.count + 1)
                document = try document.insertingElement(item, into: "menu.items", at: position + 1)
                menu.insert(item, at: position)
                label = "insert \(item) at \(position + 1) in menu"
            case 2 where menu.count > 1:
                let position = random.next(menu.count)
                document = try document.removingElement(at: position + 1, from: "menu.items")
                menu.remove(at: position)
                label = "remove \(position + 1) from menu"
            case 3 where menu.count > 1:
                let from = random.next(menu.count), to = random.next(menu.count)
                document = try document.movingElement(from: from + 1, to: to + 1, in: "menu.items")
                menu.insert(menu.remove(at: from), at: to)
                label = "move \(from + 1) to \(to + 1) in menu"
            case 4:
                let item = Self.agentPool[random.next(Self.agentPool.count)]
                guard !agents.contains(item) else { continue }
                let position = random.next(agents.count + 1)
                document = try document.insertingElement(item, into: "general.agents", at: position + 1)
                agents.insert(item, at: position)
                label = "insert agent \(item)"
            case 5 where agents.count > 1:
                let position = random.next(agents.count)
                document = try document.removingElement(at: position + 1, from: "general.agents")
                agents.remove(at: position)
                label = "remove agent"
            case 6:
                let item = Self.stylePool[random.next(Self.stylePool.count)]
                guard !styles.contains(item) else { continue }
                document = try document.insertingElement(item, into: "copy_path.styles")
                styles.append(item)
                label = "append style \(item)"
            case 7 where presets.count > 1:
                let from = random.next(presets.count), to = random.next(presets.count)
                document = try document.movingEntry(from: from + 1, to: to + 1, in: "preset")
                presets.insert(presets.remove(at: from), at: to)
                label = "move preset \(from + 1) to \(to + 1)"
            case 8 where presets.count > 1:
                let position = random.next(presets.count)
                document = try document.removingEntry(at: position + 1, from: "preset")
                presets.remove(at: position)
                label = "remove preset \(position + 1)"
            case 9:
                spare += 1
                let id = "extra-\(spare)"
                let position = random.next(presets.count + 1)
                document = try document.addingEntry(to: "preset", fields: [("id", .string(id)), ("title", .string("Extra \(spare)")), ("prompt", .string("Do \(spare) {files}"))], at: position + 1)
                presets.insert(id, at: position)
                label = "add preset \(id) at \(position + 1)"
            default:
                let terminals = ["ghostty", "terminal", "iterm", "wezterm"]
                let choice = terminals[random.next(terminals.count)]
                document = try document.setting("general.terminal", to: .string(choice))
                label = "set terminal \(choice)"
            }
            let parsed = ConfigParser.parse(document.text)
            let context = "seed \(seed) step \(step): \(label)\n\(document.text)"
            #expect(parsed.diagnostics.filter { $0.severity == .error }.isEmpty, "\(context)")
            #expect(parsed.config.menuItems == menu, "\(context)")
            #expect(parsed.config.enabledAgents == agents, "\(context)")
            #expect(parsed.config.copyPathStyles.map(\.rawValue) == styles, "\(context)")
            let builtIn = Set(AgentPreset.builtIn.map(\.id))
            #expect(parsed.config.presets.map(\.id).filter { !builtIn.contains($0) } == presets, "\(context)")
            // The comments the person wrote are still there; those above or beside an entry are there exactly as long as the entry is, and directly with it.
            for comment in ["# Mine.", "# The menu, in the order I like.", "terminal = \"", "\" # keep"] { #expect(document.text.contains(comment), "lost \(comment): \(context)") }
            #expect(document.text.contains("# Presets.\n[[preset]]\nid = \"alpha\"\n") == presets.contains("alpha"), "\(context)")
            #expect(document.text.contains("# The second.\n[[preset]]\nid = \"beta\"\ntitle = \"Beta\" # b\n") == presets.contains("beta"), "\(context)")
            // The layout stays the person's: a list written on one line stays on one line with a comma and a space between its items, and a list written one to a line keeps its
            // indentation.
            func oneLine(_ items: [String]) -> String { "[" + items.map { "\"\($0)\"" }.joined(separator: ", ") + "]" }
            #expect(document.rawValue(at: "general.agents") == oneLine(agents), "agents: \(context)")
            #expect(document.rawValue(at: "copy_path.styles") == oneLine(styles), "styles: \(context)")
            for line in (document.rawValue(at: "menu.items") ?? "").split(separator: "\n", omittingEmptySubsequences: false).dropFirst().dropLast() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                #expect(line.hasPrefix("    \"") && !line.hasPrefix("     "), "menu line \(line.debugDescription): \(context)")
            }
            #expect(!document.text.contains("\n\n\n"), "blank lines piled up: \(context)")
            #expect(document.text.hasSuffix("\n"), "\(context)")
        }
    }
}
