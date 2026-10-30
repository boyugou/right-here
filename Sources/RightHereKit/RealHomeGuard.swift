import Foundation

/// A process that a test started carries `RH_NO_UI`, and a test gives it a trial home (`RH_HOME`) for whatever it writes. One that has the first and not the
/// second, and is about to change the person's real home (the runner script, the command link, the Quick Actions, the Finder extension's registration), is a test
/// that expected a refusal and got none: a bug, or a mutant of `script/mutation_check.py`, which removes the protection a test is for and runs the test. That once
/// replaced the real runner script, command link and Quick Actions of the person who ran the check with ones that pointed into a folder that was gone, so this
/// refuses before anything is written. A person who runs `rh` has no `RH_NO_UI`, and a test that means to write has a trial home.
public enum RealHomeGuard {
    public struct Refusal: Error, LocalizedError, Equatable {
        public var errorDescription: String? {
            "RH_NO_UI is set, which only a test does, and RH_HOME is not: this would change the real home folder (the runner script, the command link, the Quick Actions) "
                + "or the Finder extension's registration, which are the person's. Unset RH_NO_UI (it is for tests), or give rh a trial home, `RH_HOME=<an empty folder>`, for what it writes."
        }
    }

    /// Whether this process is one a test started that has no trial home.
    static func isUnderTestWithoutTrialHome(_ environment: [String: String]) -> Bool {
        environment["RH_NO_UI"] != nil && RHEnvironment.path("RH_HOME", in: environment) == nil
    }

    /// Throws before something is written under `home` when that is the real home of a process a test started.
    public static func check(home: URL, environment: [String: String] = ProcessInfo.processInfo.environment,
                             realHome: URL = LiveSystemFacts.realHomeDirectory) throws {
        guard isUnderTestWithoutTrialHome(environment),
              home.resolvingSymlinksInPath().path == realHome.resolvingSymlinksInPath().path else { return }
        throw Refusal()
    }

    /// Throws before a file under the real home is written by a process a test started that has no trial home: a test of `rh config set` that forgot its home would
    /// otherwise change the person's own config.
    public static func checkWriting(_ file: URL, environment: [String: String] = ProcessInfo.processInfo.environment,
                                    realHome: URL = LiveSystemFacts.realHomeDirectory) throws {
        guard isUnderTestWithoutTrialHome(environment) else { return }
        let target = file.resolvingSymlinksInPath().path
        let home = realHome.resolvingSymlinksInPath().path
        guard target == home || target.hasPrefix(home + "/") else { return }
        throw Refusal()
    }

    /// Throws before the Finder extension's registration, which is for the whole Mac, is changed by a process a test started that has no trial home.
    public static func checkSystemWide(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard isUnderTestWithoutTrialHome(environment) else { return }
        throw Refusal()
    }
}
