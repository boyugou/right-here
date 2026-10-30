import Foundation

/// `[menu]`, `[services]` and `[copy_path]`, and the check that the action ids they list name something.
extension ConfigBuilder {
    func readMenu(_ root: ConfigReader, into config: inout Config) {
        guard let menu = root.subtable("menu") else { return }
        menu.checkKnownKeys()
        config.menuItems = menu.stringArray("items")
        if config.menuItems?.contains(where: { $0 != "-" }) == false {
            sink.warning(["menu", "items"], "the list has no entries, so the Finder menu will be empty; remove the key to use the default menu")
        }
        for entry in config.menuItems ?? [] where entry != "-" && !MenuBuilder.groups.contains(entry) && ActionRef(parsing: entry) == nil {
            sink.warning(["menu", "items"], "\"\(entry)\" is neither a menu group nor an action id",
                         suggestion: Suggestion.didYouMean(entry, in: Array(MenuBuilder.groups)))
        }
        // An entry twice is two lines of the menu that do the same: `rh config add menu.items open-editor` on a default menu does that, since the default has it.
        var seen = Set<String>()
        for entry in config.menuItems ?? [] where entry != "-" && !seen.insert(entry).inserted {
            sink.warning(["menu", "items"], "\"\(entry)\" is listed twice, so the menu shows it twice; take one out with `rh config remove menu.items \(entry)`")
        }
    }

    func readServices(_ root: ConfigReader, into config: inout Config) {
        guard let services = root.subtable("services") else { return }
        services.checkKnownKeys()
        if let items = services.stringArray("items") {
            var seen = Set<String>()
            config.serviceItems = items.filter { item in
                guard ActionRef(parsing: item) != nil else {
                    sink.warning(["services", "items"], "\"\(item)\" is not an action id; see `rh docs actions`")
                    return false
                }
                // An action twice would be two Quick Actions of one name, and two rows of one id in the window.
                guard seen.insert(item).inserted else {
                    sink.warning(["services", "items"], "\"\(item)\" is listed twice; the second is ignored")
                    return false
                }
                return true
            }
        }
    }

    func readCopyPath(_ root: ConfigReader, into config: inout Config) {
        guard let copyPath = root.subtable("copy_path") else { return }
        copyPath.checkKnownKeys()
        if let title = copyPath.string("title"), isPlainName(title, at: ["copy_path", "title"], noun: "title") { config.copyPathTitle = title }
        if let names = copyPath.stringArray("styles") {
            var seen = Set<String>()
            config.copyPathStyles = names.compactMap { name in
                guard seen.insert(name).inserted else {
                    sink.warning(["copy_path", "styles"], "\"\(name)\" is listed twice; the second is ignored")
                    return nil
                }
                if let style = PathStyle(rawValue: name) { return style }
                sink.error(["copy_path", "styles"], "unknown style \"\(name)\"; known styles: " + PathStyle.allCases.map(\.rawValue).joined(separator: ", "),
                           suggestion: Suggestion.didYouMean(name, in: PathStyle.allCases.map(\.rawValue)))
                return nil
            }
        }
    }

    /// An id can be well formed and still name nothing (an agent, terminal, app or template that is not defined);
    /// such an entry would just be left out of the menu without a word.
    func checkActionTargets(_ config: Config) {
        let agentIDs = (config.customAgents + KnownAgents.all).map(\.id)
        func check(_ entry: String, in path: [String]) {
            guard let ref = ActionRef(parsing: entry) else { return }
            var problem: (what: String, word: String, choices: [String])?
            switch ref {
            case .agent(let id, let variant, let launcher):
                if let agent = config.agent(id: id) {
                    if let variant, !agent.variants.contains(where: { $0.id == variant }) { problem = ("agent \"\(id)\" has no variant \"\(variant)\"", variant, agent.variants.map(\.id)) }
                    else if case .terminal(let terminal?) = launcher, config.app(id: terminal)?.role != .terminal { problem = ("no terminal \"\(terminal)\"", terminal, config.allApps.filter { $0.role == .terminal }.map(\.id)) }
                } else { problem = ("no agent \"\(id)\"", id, agentIDs) }
            case .openTerminal(let id?):
                if config.app(id: id)?.role != .terminal { problem = ("no terminal \"\(id)\"", id, config.allApps.filter { $0.role == .terminal }.map(\.id)) }
            case .openApp(let id):
                if config.app(id: id) == nil { problem = ("no app \"\(id)\"", id, config.allApps.map(\.id)) }
            case .preset(let id, let terminal):
                if config.preset(id: id) == nil { problem = ("no preset \"\(id)\"", id, config.presets.map(\.id)) }
                else if let terminal, config.app(id: terminal)?.role != .terminal { problem = ("no terminal \"\(terminal)\"", terminal, config.allApps.filter { $0.role == .terminal }.map(\.id)) }
            case .newFile(let id):
                if !config.newFile.templates.contains(where: { $0.id == id }) { problem = ("no new-file template \"\(id)\"", id, config.newFile.templates.map(\.id)) }
            default: break
            }
            guard let problem else { return }
            let word = problem.word
            sink.warning(path, "\"\(entry)\" names something that is not defined (\(problem.what)), so it is left out",
                         suggestion: Suggestion.didYouMean(word, in: problem.choices).map { Hint(text: $0.text, replacement: entry.replacingOccurrences(of: word, with: $0.replacement ?? word)) })
        }
        for entry in config.menuItems ?? [] where entry != "-" && !MenuBuilder.groups.contains(entry) { check(entry, in: ["menu", "items"]) }
        for entry in config.serviceItems ?? [] { check(entry, in: ["services", "items"]) }
    }
}
