import Foundation
import RightHereCore

/// What the setup window puts on the clipboard for the person to paste into another tool. It is text for a program or an
/// AI assistant and stays English: `rh docs` and the commands in it are English too.
public enum SetupSnippets {
    /// For an AI assistant: it reads the built-in guide, runs the checks, and tailors the config to the person.
    public static let setupPrompt = "Set up Right Here for me. Run `rh docs agent-setup` and follow it: run `rh doctor --json` and fix whatever fails, "
        + "then tailor ~/.config/right-here/config.toml to how I work, check it with `rh config validate`, and show me the result with `rh menu`."

    /// The name an MCP client gives the server in its settings: the one the README and the plugin use, and the one the server
    /// announces (`MCPServer.serverName`, which a test in the MCP target holds to this).
    public static let mcpServerName = "right-here"

    /// The two commands that add the Claude Code plugin of this repository: its marketplace, then the plugin from it.
    public static let pluginCommands = "/plugin marketplace add boyugou/right-here\n/plugin install right-here@right-here"

    /// The program an MCP client starts, by a path that does not depend on the client's `PATH`. An app launched from the Dock
    /// or Finder has the environment launchd gives it (`/usr/bin:/bin:/usr/sbin:/sbin`, measured with a launchd job), where
    /// the bare `rh` of the README is not found. The link `rh install --cli` makes is the stable name for it, so it comes first;
    /// then the copy inside the app; then `rh`.
    public static func mcpCommand(home: URL, helperPath: String?) -> String {
        let link = Installer(home: home).cliLink.path
        if FileManager.default.isExecutableFile(atPath: link) { return link }
        if let helperPath, FileManager.default.isExecutableFile(atPath: helperPath) { return helperPath }
        return AppIdentity.cliName
    }

    /// The JSON an MCP client takes to start `rh mcp` over standard input and output. The command is written by an encoder,
    /// so a folder with a quote or a backslash in its name is escaped.
    public static func mcpConfiguration(command: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let quoted = (try? encoder.encode(command)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\(AppIdentity.cliName)\""
        return """
        {
          "mcpServers": {
            "\(mcpServerName)": {
              "command": \(quoted),
              "args": ["mcp"]
            }
          }
        }
        """
    }
}
