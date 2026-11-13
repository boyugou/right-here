import Foundation

/// What `rh` refuses on the command line before ArgumentParser reads it, because ArgumentParser reads it differently from the person.
/// A misspelt command prints the whole root help with status 0. An argument that starts with a dash is read as options: `-h` in
/// `copy-path.absolute -dash.txt` prints the help of `run` with status 0 and runs nothing.
public enum InvocationCheck {
    /// The options of a command that takes paths: the flags, and the options whose value is the next word (which may start with a dash).
    public struct Options: Sendable, Equatable {
        public var flags: Set<String>
        public var values: Set<String>

        public init(flags: Set<String>, values: Set<String>) {
            self.flags = flags
            self.values = values
        }
    }

    /// The options of `rh run`, its path arguments included. A test holds this list to `rh run --help`.
    public static let runOptions = Options(
        flags: ["--dry-run", "--json", "--alert", "--worktree", "--bypass-permissions", "--safe", "--help", "-h", "--version"],
        values: ["--origin", "--container", "--branch", "--arg", "--language", "--time-limit"]
    )

    /// The options of `rh menu`. A test holds this list to `rh menu --help`.
    public static let menuOptions = Options(
        flags: ["--json", "--explain", "--help", "-h", "--version"],
        values: ["--origin", "--container", "--language"]
    )

    /// The options of `rh config set` and `rh config add` that change what is written or where: their values may follow `--`, and one of these there is a value too. A test holds them
    /// to the commands' `--help`.
    public static let configValueOptions: [String: Options] = [
        "set": Options(flags: ["--local", "--dry-run", "--json"], values: []),
        "add": Options(flags: ["--local", "--dry-run", "--json"], values: ["--at"]),
    ]

    /// `rh config set <key> -- <values> --dry-run`: the help says to put `--` before a value that starts with a dash, and its usage line puts the options after the values, so an option
    /// written last was a value, and the dry run wrote the file (`--local` changed config.toml). Such an option is refused, unless it stands before `--` as well (then the one after is meant
    /// as a value), with the command that gives it before `--`.
    static func configProblem(_ arguments: [String]) -> String? {
        guard arguments.count > 2, arguments[0] == "config", let options = configValueOptions[arguments[1]], let terminator = arguments.firstIndex(of: "--") else { return nil }
        func name(_ word: String) -> String { word.split(separator: "=", maxSplits: 1).first.map(String.init) ?? word }
        let before = Set(arguments[2..<terminator].map(name))
        var moved: [String] = []
        var values: [String] = []
        var index = terminator + 1
        var first: String?
        while index < arguments.count {
            let word = arguments[index]
            index += 1
            let option = name(word)
            guard options.flags.contains(option) || options.values.contains(option), !before.contains(option) else { values.append(word); continue }
            first = first ?? word
            moved.append(word)
            if options.values.contains(option), !word.contains("="), index < arguments.count { moved.append(arguments[index]); index += 1 }
        }
        guard let first else { return nil }
        let fixed = (["rh"] + arguments[0..<terminator] + moved + ["--"] + values).map { $0.withControlCharactersEscaped }.joined(separator: " ")
        return "\(first.withControlCharactersEscaped) after -- would be written as a value of the setting, not read as the option: give the options before -- (`\(fixed)`)."
            + " A value that is one of these options is written in the file itself (`rh config path` names it)."
    }

    /// What to add to "<word> does not exist" for a word that was read as a folder (`rh worktree ad` is `rh worktree list ad`, since `list`
    /// is what `rh worktree` does) when it is close to the name of a subcommand: a folder that is not there and a misspelt `add` look the same.
    public static func subcommandHint(for word: String, of command: String, in subcommands: [String]) -> String? {
        guard !word.contains("/"), let close = Suggestion.closest(to: word, in: subcommands) else { return nil }
        return "Did you mean \"rh \(command) \(close)\"?"
    }

    /// The first problem with the command line as one sentence for standard error, or `nil` when ArgumentParser may read it.
    /// `commands` are the root's subcommands.
    public static func problem(_ arguments: [String], commands: [String]) -> String? {
        guard let command = arguments.first, !command.hasPrefix("-") else { return nil }
        if command != "help", !commands.contains(command) {
            let close = Suggestion.closest(to: command, in: commands)
            return "unknown command \"\(command.withControlCharactersEscaped)\"."
                + (close.map { " Did you mean \"\($0)\"?" } ?? "") + " Run `rh --help` to list the commands."
        }
        let options: Options
        switch command {
        case "run": options = runOptions
        case "menu": options = menuOptions
        case "config": return configProblem(arguments)
        default: return nil
        }
        var index = 1
        while index < arguments.count {
            let word = arguments[index]
            index += 1
            if word == "--" { return nil }
            guard word.hasPrefix("-"), word != "-" else { continue }
            if word.hasPrefix("--") {
                // `--arg --verbose`: the word after an option that takes a value is that value, dash or not.
                let name = word.split(separator: "=", maxSplits: 1).first.map(String.init) ?? word
                if options.values.contains(name), !word.contains("=") { index += 1 }
                continue
            }
            if options.flags.contains(word) { continue }
            return "arguments that start with - need -- before them, and \"\(word.withControlCharactersEscaped)\" would be read as an option"
                + " (`rh \(command) … -- \(word.withControlCharactersEscaped)`)."
        }
        return nil
    }
}
