import Foundation

/// Typed access to the strings used by menus and alerts.
extension Localizer {
    func openIn(_ appName: String) -> String { render(.menuOpenIn(appName)) }
    func agentHere(_ agent: String) -> String { render(.menuAgentHere(agent)) }
    func agentVariant(_ agent: String, _ variant: String) -> String { render(.menuAgentVariant(agent, variant)) }
    func agentIn(_ agent: String, terminal: String) -> String { render(.menuAgentIn(agent, terminal)) }
    func agentVariantIn(_ agent: String, _ variant: String, terminal: String) -> String { render(.menuAgentVariantIn(agent, variant, terminal)) }
    func agentDesktop(_ agent: String) -> String { render(.menuAgentDesktop(agent)) }
    func agentLink(_ agent: String) -> String { render(.menuAgentLink(agent)) }
    func newFile(_ templateTitle: String) -> String { render(.menuNewFile(templateTitle)) }

    var newFileGroup: String { string(.groupNewFile) }
    var copyPathGroup: String { string(.groupCopyPath) }
    var openWithGroup: String { string(.groupOpenWith) }
    var moreAgentsGroup: String { string(.groupMoreAgents) }
    var presetsGroup: String { string(.groupPresets) }
    var revealInFinder: String { string(.actionReveal) }
    var copyRepositoryLink: String { string(.actionCopyRepositoryLink) }
    var openRepositoryPage: String { string(.actionOpenRepositoryPage) }

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
        case .aiMention: return string(.copyPathAiMention)
        case .markdownLink: return string(.copyPathMarkdownLink)
        }
    }

    func copyPathTitle(_ style: PathStyle) -> String { render(.copyPathTitleFormat(copyPath(style))) }
}
