import Foundation

/// The environment variables that point Right Here at other folders: `RH_HOME` stands in for the home folder, `RH_CONFIG` and `RH_CONFIG_DIR`
/// name the config, `RH_LOG_DIR` the log. Every place that reads one reads it here.
///
/// Each names a path, so one that is set to nothing is a mistake and never means "not set": `RH_HOME=$TRIAL rh setup` with `$TRIAL` unset
/// would otherwise be a setup of the real home, which is the one thing a trial is there to avoid. `rh` refuses it before it does anything
/// (`problem`); a process that is not started from a shell (the app, the Finder extension) reads it as a path that no file system has,
/// so what it reads is not there and what it writes fails, and nothing happens in a folder that was not named.
public enum RHEnvironment {
    public static let names = ["RH_HOME", "RH_CONFIG", "RH_CONFIG_DIR", "RH_LOG_DIR"]

    /// What `name` is set to as a path, with `~` expanded; `nil` when it is not set.
    public static func path(_ name: String, in environment: [String: String]) -> URL? {
        guard let value = environment[name] else { return nil }
        guard !value.isEmpty else { return URL(fileURLWithPath: "/dev/null/\(name)-is-set-to-nothing") }
        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
    }

    /// The sentence for standard error when a variable is set to nothing, or `nil` when none is.
    public static func problem(in environment: [String: String]) -> String? {
        let empty = names.filter { environment[$0]?.isEmpty == true }
        guard !empty.isEmpty else { return nil }
        let list = empty.joined(separator: " and ")
        return "\(list) \(empty.count == 1 ? "is" : "are") set to nothing. Each of \(names.joined(separator: ", ")) names a folder or a file, and an empty value is "
            + "refused and not read as \"not set\", which would use your real folders: a shell variable that is not set expands to nothing "
            + "(`RH_HOME=$TRIAL rh setup`). Give it a path, for example `RH_HOME=/tmp/trial rh setup`, or remove it from the environment."
    }
}
