import Foundation
import RightHereCore

/// What the setup window offers a person who has no config file yet: the terminals and editors installed on this Mac, the agents
/// Right Here knows (with which of them the login shell found), and what it would pick by itself. The window starts from `detected`,
/// and what the person leaves checked becomes their `SetupChoices`.
public struct SetupOffer: Sendable, Equatable {
    public struct Option: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        /// For an app, always true here (only installed ones are offered); for an agent, whether its command was found.
        public var available: Bool
        /// The icon of the installed app, which its chip shows; an agent has none.
        public var icon: Icon?

        public init(id: String, name: String, available: Bool, icon: Icon? = nil) {
            self.id = id
            self.name = name
            self.available = available
            self.icon = icon
        }
    }

    /// The terminals that are installed, the one a click would use first.
    public var terminals: [Option]
    /// The editors that are installed, the one a click would use first.
    public var editors: [Option]
    /// Every agent Right Here knows, the ones that were found first.
    public var agents: [Option]
    public var detected: DetectedEnvironment
    /// Whether the login shell said which agents' commands it finds. When it did not (a startup file that exits, a shell that is slow to start), no agent was found
    /// because nobody could tell, and the window says so.
    public var loginShellAnswered: Bool

    public init(terminals: [Option] = [], editors: [Option] = [], agents: [Option] = [], detected: DetectedEnvironment = DetectedEnvironment(), loginShellAnswered: Bool = true) {
        self.terminals = terminals
        self.editors = editors
        self.agents = agents
        self.detected = detected
        self.loginShellAnswered = loginShellAnswered
    }

    /// Looks at this Mac: LaunchServices for the apps and the login shell, once, for the agents' commands.
    public static func make(facts: any SystemFacts, runner: any ProcessRunner) async -> SetupOffer {
        let (detected, shellAnswered) = await Detector(facts: facts, runner: runner).look()
        func installed(_ apps: [AppDescriptor]) -> [Option] {
            apps.sorted { ($0.defaultRank ?? Int.max) < ($1.defaultRank ?? Int.max) }
                .compactMap { app in app.installedBundleID(facts: facts).map { Option(id: app.id, name: app.name, available: true, icon: .app($0)) } }
        }
        let found = Set(detected.agents)
        let agents = KnownAgents.all.map { Option(id: $0.id, name: $0.name, available: found.contains($0.id)) }
        return SetupOffer(terminals: installed(KnownApps.terminals), editors: installed(KnownApps.editors),
                          agents: agents.filter(\.available) + agents.filter { !$0.available }, detected: detected, loginShellAnswered: shellAnswered)
    }

    /// The choices that make the config: the terminal and editor picked (or none, when the machine has none), the agents checked in the
    /// order Right Here lists them.
    public func choices(terminal: String?, editor: String?, agents checked: Set<String>) -> SetupChoices {
        SetupChoices(terminal: terminal, editor: editor, agents: KnownAgents.all.map(\.id).filter(checked.contains))
    }
}
