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
        values: ["--origin", "--container", "--branch", "--arg", "--language"]
    )

    /// The options of `rh menu`. A test holds this list to `rh menu --help`.
    public static let menuOptions = Options(
        flags: ["--json", "--explain", "--help", "-h", "--version"],
        values: ["--origin", "--container", "--language"]
    )

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
