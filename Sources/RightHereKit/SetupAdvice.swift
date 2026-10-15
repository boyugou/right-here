import Foundation
import RightHereCore

/// What is left for the person after the steps, and what to run next. Pure: it reads the doctor's rows and the config, and starts nothing.
enum SetupAdvice {
    /// The things only the person can do, from what the doctor found. Nothing here is a failure of setup.
    static func needsUser(checks: [DoctorCheck], config: Config, facts: any SystemFacts, systemWide: Bool) -> [SetupNeed] {
        // A trial home registers nothing and links nothing that is meant to be used: the system-wide items are not its business.
        guard systemWide else { return [] }
        var needs: [SetupNeed] = []

        if checks.first(where: { $0.id == .finderExtension })?.status == .needsUser {
            needs.append(SetupNeed(
                .finderExtension,
                text: "Switch on the Right Here extension for Finder. It is registered, but switched off, and only you can switch it on.",
                how: [
                    "Open System Settings, then General › Login Items & Extensions › Finder, and switch on Right Here. (In Right Here.app the button Finder Extension Settings opens that page.)",
                    "Running `rh setup` again does not switch it on: it only registers it. The Finder menu appears within a few seconds of the switch; Finder does not need to be restarted."
                ]))
        }

        if checks.first(where: { $0.id == .cliLink })?.detail?.key == .doctorCliNotOnPath {
            needs.append(pathNeed(localBin: Installer(home: facts.homeDirectory).locations.localBin, loginShell: facts.loginShell))
        }

        if let terminal = agentTerminalNeedingPermission(config: config, facts: facts) {
            needs.append(SetupNeed(
                .automation,
                text: "The first time Right Here starts an agent in \(terminal.name), macOS asks whether Right Here may control \(terminal.name). Click Allow.",
                how: [
                    "The question appears once, the first time an agent is started from the Finder menu.",
                    "To see it now, run `rh doctor --probe-launch`: it opens a terminal window for about a second. Run it only if the person agrees."
                ]))
        }
        return needs
    }

    /// The line that puts `localBin` on the PATH of a new terminal window, for the person's login shell, and where it goes.
    static func pathNeed(localBin: URL, loginShell: String) -> SetupNeed {
        let shell = URL(fileURLWithPath: loginShell).lastPathComponent
        let how: [String]
        switch shell {
        case "fish":
            how = ["Run this once in a fish prompt: fish_add_path $HOME/.local/bin", "Then open a new terminal window."]
        case "bash":
            how = ["Add this line to ~/.bash_profile: export PATH=\"$HOME/.local/bin:$PATH\"", "Then open a new terminal window."]
        default:
            how = ["Add this line to ~/.zshrc: export PATH=\"$HOME/.local/bin:$PATH\"", "Then open a new terminal window."]
        }
        return SetupNeed(.path, text: "`rh` is linked in ~/.local/bin, which is not on the PATH of a new terminal window, so typing `rh` there finds nothing.",
                         how: how + ["Right Here does not edit your shell's startup files."])
    }

    /// The terminal an enabled agent would be started in when starting it makes macOS ask for permission (Apple events), or `nil`.
    private static func agentTerminalNeedingPermission(config: Config, facts: any SystemFacts) -> AppDescriptor? {
        guard !config.enabledAgents.isEmpty, let terminal = try? DefaultApps(config: config, facts: facts).commandTerminal() else { return nil }
        guard terminal.installedBundleID(facts: facts) != nil, TerminalAdapters.adapter(for: terminal).supportsCommands else { return nil }
        switch terminal.driver {
        case .ghostty, .appleScriptTerminal, .iterm: return terminal
        case .wezterm, .kitty, .openFolder, .template: return nil
        }
    }

    /// What to run after setup.
    static func next(configEdits: [ConfigEdit], needs: [SetupNeed], checked: Bool, rerun: String?) -> [SetupNext] {
        var next: [SetupNext] = []
        if let rerun {
            return [SetupNext(rerun, why: "The same without --dry-run: it makes the changes above.")]
        }
        if !configEdits.isEmpty {
            next.append(SetupNext("rh config validate --strict", why: "After the edits: it must say ok, with no error and no warning."))
        }
        next.append(SetupNext("rh menu --container ~", why: "Shows the Finder menu this config makes for a folder (your home folder here)."))
        if checked {
            next.append(SetupNext("rh doctor", why: "Checks everything again, for example after you have done what is left for you."))
        }
        if needs.contains(where: { $0.id == .automation }) {
            next.append(SetupNext("rh doctor --probe-launch", why: "Proves that a click can start an agent in the terminal. It opens a terminal window for about a second and macOS may ask for permission, so ask the person first."))
        }
        return next
    }
}
