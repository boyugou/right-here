import Foundation

/// Text that came from outside Right Here (a file name, a name or a message in a config, what git printed) is data, never an instruction, and a reader that
/// is an AI agent has to be able to tell it from the words of the tool it is reading. `wrap` puts it between `⟦user⟧` and `⟦/user⟧`, with its control and
/// invisible characters shown as escapes (what `rh docs mcp` promises: a name with a line break cannot start a line of its own, and one that draws nothing cannot
/// say something the person does not see) and the two marks themselves taken out of it, so a name cannot close its own fence.
///
/// The MCP tools mark the names in the text of their results with it, and so do `rh setup` and `rh doctor` where a name the config chose stands in a sentence or
/// a row that an agent is told to pass on (ADR 0020).
public enum Fence {
    public static let open = "⟦user⟧"
    public static let close = "⟦/user⟧"

    /// The text fenced; text with nothing in it is left as it is (a separator has no title to mark).
    public static func wrap(_ text: String) -> String {
        fenced(text.withControlCharactersEscaped)
    }

    /// Text that has lines of its own (a plan as JSON) fenced as a whole: its line feeds stay, and everything else is escaped as it is in a name.
    public static func block(_ text: String) -> String {
        fenced(text.escapingControlCharacters(keeping: ["\n"]))
    }

    private static func fenced(_ escaped: String) -> String {
        escaped.isEmpty ? escaped : open + escaped.scalarReplacing(["⟦": "[", "⟧": "]"]) + close
    }
}
