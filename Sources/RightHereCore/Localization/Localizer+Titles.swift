import Foundation

/// Typed access to the strings used by menus and alerts.
extension Localizer {
    func openIn(_ appName: String) -> String { string(.menuOpenIn, appName) }
    func agentHere(_ agent: String) -> String { string(.menuAgentHere, agent) }
    func agentVariant(_ agent: String, _ variant: String) -> String { string(.menuAgentVariant, agent, variant) }
    func agentIn(_ agent: String, terminal: String) -> String { string(.menuAgentIn, agent, terminal) }
    func agentVariantIn(_ agent: String, _ variant: String, terminal: String) -> String { string(.menuAgentVariantIn, agent, variant, terminal) }
    func agentDesktop(_ agent: String) -> String { string(.menuAgentDesktop, agent) }
    func agentLink(_ agent: String) -> String { string(.menuAgentLink, agent) }
    func newFile(_ templateTitle: String) -> String { string(.menuNewFile, templateTitle) }

    var newFileGroup: String { string(.groupNewFile) }
    var copyPathGroup: String { string(.groupCopyPath) }
    var openWithGroup: String { string(.groupOpenWith) }
    var moreAgentsGroup: String { string(.groupMoreAgents) }
    var presetsGroup: String { string(.groupPresets) }
    var revealInFinder: String { string(.actionReveal) }

    func copyPath(_ style: PathStyle) -> String {
        switch style {
        case .absolute: return string(.copyPathAbsolute)
        case .tilde: return string(.copyPathTilde)
        case .gitRelative: return string(.copyPathGitRelative)
        case .name: return string(.copyPathName)
        case .parent: return string(.copyPathParent)
        case .shellEscaped: return string(.copyPathShellEscaped)
        case .shellQuoted: return string(.copyPathShellQuoted)
        case .fileURL: return string(.copyPathFileURL)
        case .aiMention: return string(.copyPathAIMention)
        case .markdownLink: return string(.copyPathMarkdownLink)
        }
    }

    func copyPathTitle(_ style: PathStyle) -> String { string(.copyPathTitleFormat, copyPath(style)) }
}
