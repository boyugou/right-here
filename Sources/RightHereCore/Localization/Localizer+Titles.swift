import Foundation

/// Typed access to the strings used by menus and alerts.
extension Localizer {
    func openIn(_ appName: String) -> String { render(.menuOpenIn(appName), isolatingValues: isolatesNames) }
    func agentHere(_ agent: String) -> String { render(.menuAgentHere(agent), isolatingValues: isolatesNames) }
    func agentVariant(_ agent: String, _ variant: String) -> String { render(.menuAgentVariant(agent, variant), isolatingValues: isolatesNames) }
    func agentIn(_ agent: String, terminal: String) -> String { render(.menuAgentIn(agent, terminal), isolatingValues: isolatesNames) }
    func agentVariantIn(_ agent: String, _ variant: String, terminal: String) -> String { render(.menuAgentVariantIn(agent, variant, terminal), isolatingValues: isolatesNames) }
    func agentDesktop(_ agent: String) -> String { render(.menuAgentDesktop(agent), isolatingValues: isolatesNames) }
    func agentLink(_ agent: String) -> String { render(.menuAgentLink(agent), isolatingValues: isolatesNames) }
    func newFile(_ templateTitle: String) -> String { render(.menuNewFile(templateTitle), isolatingValues: isolatesNames) }

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
