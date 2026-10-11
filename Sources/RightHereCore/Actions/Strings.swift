import Foundation

/// Every user-visible title is produced here, so localization has one place to plug in.
enum Strings {
    static func openIn(_ appName: String) -> String { "Open in \(appName)" }
    static func agentHere(_ agent: String) -> String { "\(agent) Here" }
    static func agentVariant(_ agent: String, _ variant: String) -> String { "\(agent): \(variant)" }
    static func agentIn(_ agent: String, terminal: String) -> String { "\(agent) in \(terminal)" }
    static func agentVariantIn(_ agent: String, _ variant: String, terminal: String) -> String { "\(agent): \(variant) in \(terminal)" }
    static func agentDesktop(_ agent: String) -> String { "\(agent) in Desktop App" }
    static func agentLink(_ agent: String) -> String { "\(agent) in Last-Used Terminal" }
    static func newFile(_ templateTitle: String) -> String { "New \(templateTitle)" }

    static let newFileGroup = "New File"
    static let copyPathGroup = "Copy Path"
    static let openWithGroup = "Open With"
    static let moreAgentsGroup = "More Agent Options"
    static let revealInFinder = "Reveal in Finder"

    static func copyPath(_ style: PathStyle) -> String {
        switch style {
        case .absolute: return "Full Path"
        case .tilde: return "Path from Home (~)"
        case .gitRelative: return "Path from Git Root"
        case .name: return "File Name"
        case .parent: return "Parent Folder Path"
        case .shellEscaped: return "Shell-Escaped Path"
        case .shellQuoted: return "Quoted Path"
        case .fileURL: return "File URL"
        case .aiMention: return "@ Mention for AI"
        case .markdownLink: return "Markdown Link"
        }
    }
}
