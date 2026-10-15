import Foundation
import RightHereCore

/// `rh doctor --report`: what a person pastes into a bug report, as Markdown. It holds the versions of rh and of the app, the macOS version and
/// the processor, the doctor's own lines, and the count of what the config check found. It never holds the text of the config file, and the
/// home folder and the account name are taken out of everything in it (`Privacy`), so it does not say who the person is or where they keep things.
public enum DoctorReport {
    public struct Identity: Sendable, Equatable {
        public var rhVersion: String
        /// The version of Right Here.app, or `nil` when it is not found.
        public var appVersion: String?
        /// `major.minor.patch`, as macOS reports it.
        public var macOS: String
        /// The processor's architecture, for example `arm64`.
        public var architecture: String

        public init(rhVersion: String, appVersion: String?, macOS: String, architecture: String) {
            self.rhVersion = rhVersion
            self.appVersion = appVersion
            self.macOS = macOS
            self.architecture = architecture
        }
    }

    /// Takes out what says who the person is: the home folder (shown as `~`) and the account name (shown as `<account>`). Whole words only, so an
    /// account called `app` does not change `application`, and a home folder `/Users/me` does not change `/Users/me2`.
    public struct Privacy: Sendable, Equatable {
        /// Every spelling of the home folder that may appear (the account's own, and the one `RH_HOME` points at).
        public var homes: [String]
        /// The account name, or `nil` when it is not known.
        public var account: String?

        public init(homes: [String], account: String?) {
            self.homes = homes
            self.account = account
        }

        public func apply(_ text: String) -> String {
            var result = text
            // The longest first: a home folder that is inside another one is taken out as the whole of it.
            for home in Set(homes).filter({ $0.count > 1 && $0 != "/" }).sorted(by: { $0.count > $1.count }) {
                result = Self.replacing(home, in: result, with: "~") { !($0.isLetter || $0.isNumber || "_-.".contains($0)) }
            }
            if let account, !account.isEmpty {
                result = Self.replacing(account, in: result, with: "<account>") { $0.isLetter == false && $0.isNumber == false }
            }
            return result
        }

        /// Replaces each whole occurrence of `needle`: one that the characters around it do not continue (`isBoundary` says which those are).
        static func replacing(_ needle: String, in text: String, with replacement: String, isBoundary: (Character) -> Bool) -> String {
            var result = ""
            var rest = Substring(text)
            while let range = rest.range(of: needle) {
                let before = rest[..<range.lowerBound]
                let after = rest[range.upperBound...]
                let wholeWord = (before.last.map(isBoundary) ?? true) && (after.first.map(isBoundary) ?? true)
                result += before
                result += wholeWord ? replacement : needle
                rest = after
            }
            return result + rest
        }
    }

    /// The report. `configCheck` is the result line of `rh config validate --strict` (counts, never the text it quotes); `checks` are the doctor's.
    public static func markdown(identity: Identity, configCheck: String, checks: [DoctorCheck], privacy: Privacy) -> String {
        let body = checks.flatMap { $0.englishLines() }.joined(separator: "\n")
        // The doctor's lines go in a block as they are printed; a fence longer than any run of backticks in them keeps the block closed.
        let fence = body.contains("```") ? "````" : "```"
        let lines = [
            "# Right Here bug report",
            "",
            "Made by `rh doctor --report`. The home folder is shown as `~`, the account name is removed, and the report holds no text of the config file.",
            "",
            "- Right Here (rh): \(identity.rhVersion)",
            "- Right Here.app: \(identity.appVersion ?? "not found")",
            "- macOS: \(identity.macOS)",
            "- Architecture: \(identity.architecture)",
            "- Config check (`rh config validate --strict`): \(configCheck)",
            "",
            "## Checks",
            "",
            fence + "text",
            body,
            fence,
            ""
        ]
        return privacy.apply(lines.joined(separator: "\n"))
    }
}
