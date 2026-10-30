import Foundation
import RightHereCore

/// What is left for the person after the steps, and what to run next. Pure: it reads the doctor's rows and the config, and starts nothing.
enum SetupAdvice {
    /// The things only the person can do, from what the doctor found. Nothing here is a failure of setup.
    ///
    /// A trial (`RH_HOME`) says the same as a real run, except about the Finder extension: it registers and checks nothing for the
    /// whole Mac, so its rows have no extension row and no switch to ask for. The PATH line and the permission prompt depend only on
    /// the config and on the person's shell and terminal, so a trial is a rehearsal of them (and an AI agent that tries setup in a
    /// trial meets the same list the person will).
    ///
    /// - Parameter config: The config as it is read, or `nil` when it cannot be used (`configNeed`): what depends on it (the permission
    ///   macOS asks for) would be worked out from the defaults, which is not what the person has.
    static func needsUser(checks: [DoctorCheck], config: Config?, facts: any SystemFacts) -> [SetupNeed] {
        var needs: [SetupNeed] = []

        if checks.first(where: { $0.id == .finderExtension })?.status == .needsUser {
            needs.append(SetupNeed(
                .finderExtension,
                text: "Switch on the Right Here extension for Finder. It is registered, but switched off, and only you can switch it on.",
                how: [
                    "Open System Settings, then General › Login Items & Extensions › Finder, and switch on Right Here. (In Right Here.app the button Finder Extension Settings opens that page.)",
                    "Setup registers the extension and asks macOS to use it, and the switch is still theirs: running `rh setup` again does not flip it. The Finder menu appears within a few seconds of the switch; Finder does not need to be restarted."
                ]))
        }

        if checks.first(where: { $0.id == .cliLink })?.detail?.key == .doctorCliNotOnPath {
            needs.append(pathNeed(localBin: Installer(home: facts.homeDirectory).locations.localBin, loginShell: facts.loginShell))
        }

        if let config, let terminal = agentTerminalNeedingPermission(config: config, facts: facts) {
            // The name macOS asks about is the app's own (the dialog names the app, not what the config calls it); the config's name stands in only when the system
            // has none. Either is text from outside, so the sentence the playbook has an agent pass on fences it (ADR 0020).
            let name = Fence.wrap(terminal.installedBundleID(facts: facts).flatMap(facts.displayName(bundleID:)) ?? terminal.name)
            needs.append(SetupNeed(
                .automation,
                text: "The first time Right Here starts an agent in \(name), macOS asks whether Right Here may control \(name). Click Allow.",
                how: [
                    "The question appears once, the first time an agent is started from the Finder menu.",
                    "To see it now, run `rh doctor --probe-launch`: it opens a terminal window for about a second. (An AI agent asks the person before it runs it.)"
                ]))
        }
        return needs
    }

    /// A config file that cannot be used. Setup left it as it is, which is all it does to a config, so what is left is the person's: fix it, or
    /// say that an AI agent may.
    static func configNeed(_ problem: ConfigProblem, command: String) -> SetupNeed {
        SetupNeed(
            .config,
            text: "\(problem.sentence), so setup left it as it is, made no Quick Actions from it and listed no edits for it. Until it is fixed Right Here does not use it.",
            how: [
                "Setup never rewrites a config. Fix the file yourself, or tell an AI agent that it may: the smallest edit that makes `rh config validate --strict` say ok, keeping every comment.",
                "Then run `\(command) --dry-run`: it lists the edits your choices need in the fixed file, if any."
            ])
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
        case .wezterm, .kitty, .alacritty, .warp, .openFolder, .template: return nil
        }
    }

    /// What to run after setup.
    ///
    /// The Quick Actions are built from the config as it is when setup runs, and the edits of an existing config are made by hand,
    /// so the order matters: with the edits made first, one real run builds them all. A real run that came first needs one more
    /// `rh setup` after the edits, and says so.
    ///
    /// - Parameter command: The command line that asks for the same as this run, for the commands that come after a fix.
    static func next(configEdits: [ConfigEdit], needs: [SetupNeed], checked: Bool, rerun: String?, command: String) -> [SetupNext] {
        // A config that cannot be used comes before everything else: no edit is listed for it, and the Quick Actions were not made from it.
        if needs.contains(where: { $0.id == .config }) {
            return [
                SetupNext("rh config validate --strict", why: "Names what is wrong in the config file, with its line. After the fix, made by the person or by an AI agent they allow, it must say ok, with no error and no warning."),
                SetupNext("\(command) --dry-run", why: "Then look again: it lists the edits your choices need in the fixed file, if any, and what the real run would do. (This run made no Quick Actions from the config.)")
            ]
        }
        var next: [SetupNext] = []
        if let rerun {
            guard !configEdits.isEmpty else { return [SetupNext(rerun, why: "The same without --dry-run: it makes the changes above.")] }
            return [
                SetupNext("rh config validate --strict", why: "After you have made the edits above to the config file: it must say ok, with no error and no warning."),
                SetupNext(rerun, why: "Then the same without --dry-run: it makes the other changes above, and builds the Quick Actions from the config as you edited it.")
            ]
        }
        if !configEdits.isEmpty {
            next.append(SetupNext("rh config validate --strict", why: "After the edits: it must say ok, with no error and no warning."))
            next.append(SetupNext("rh setup", why: "After the edits: it builds the Quick Actions from the config as you edited it (the Quick Actions of this run came from the file as it was), and checks everything again."))
        }
        next.append(SetupNext("rh menu --container ~", why: "Shows the Finder menu this config makes for a folder (your home folder here)."))
        if checked {
            next.append(SetupNext("rh doctor", why: "Checks everything again, for example after you have done what is left for you."))
        }
        if needs.contains(where: { $0.id == .automation }) {
            next.append(SetupNext("rh doctor --probe-launch", why: "Proves that a click can start an agent in the terminal. It opens a terminal window for about a second and macOS may ask for permission, so an AI agent asks the person first."))
        }
        return next
    }
}
