import Foundation
import RightHereCore

/// `rh doctor --report`: what a person pastes into a public bug report, as Markdown. It holds the versions of rh and of the app, the macOS version and
/// the processor, the doctor's rows in Right Here's own words, and the count of what the config check found. It never holds what the config says:
/// the rows that can quote it (an app's or an agent's name, an agent's command, the text of an error, the folder the config syncs with) show their
/// values as `…` and the text they would have quoted not at all (`lines(for:)`). The home folder and the account name are taken out of everything
/// in it (`Privacy`), so it does not say who the person is or where they keep things.
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

    static let notShown = "(not shown: it can quote the config)"

    private static func shown(_ message: LocalizedMessage) -> String {
        message.key == .doctorVerbatim ? notShown : message.english(showingOnly: DoctorCheck.ownValues[message.key] ?? [])
    }

    /// The lines of one check in the report. A row that cannot hold text from the config is printed as the doctor prints it. One that can (`CheckID.quotesTheConfig`)
    /// is titled by the built-in agent's own name, or the id for one the config defines, and says its sentence with the values left out; a text the doctor
    /// quotes as it is (`doctorVerbatim`) is not shown, and neither are the notes that quote.
    static func lines(for check: DoctorCheck) -> [String] {
        guard check.id.quotesTheConfig else { return check.englishLines() }
        var title = check.title
        if case .agent(let id) = check.id { title = KnownAgents.agent(id: id)?.name ?? check.id.rawValue }
        var lines = ["[\(check.status.rawValue)] \(title)" + (check.detail.map { ": " + shown($0) } ?? "")]
        lines += check.notes.filter { $0.key != .doctorVerbatim }.map { "       note: " + shown($0) }
        let quoting = check.notes.filter { $0.key == .doctorVerbatim }.count
        if quoting > 0 { lines.append("       note: \(quoting) more, \(notShown)") }
        if let fix = check.fix { lines.append("       fix: " + shown(fix)) }
        return lines
    }

    /// The most backticks in a row in `text`, counted by scalars.
    static func longestRun(of character: Unicode.Scalar, in text: String) -> Int {
        var longest = 0
        var current = 0
        for scalar in text.unicodeScalars {
            current = scalar == character ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }

    /// The report. `configCheck` is the result line of `rh config validate --strict` (counts, never the text it quotes); `checks` are the doctor's.
    public static func markdown(identity: Identity, configCheck: String, checks: [DoctorCheck], privacy: Privacy) -> String {
        let body = checks.flatMap(lines(for:)).joined(separator: "\n")
        // The doctor's lines go in a block as they are printed; a fence longer than any run of backticks in them keeps the block closed, whatever a
        // crash report's name (or anything else a row quotes) holds.
        let fence = String(repeating: "`", count: max(3, longestRun(of: "`", in: body) + 1))
        let lines = [
            "# Right Here bug report",
            "",
            "Made by `rh doctor --report`, for a public issue. It holds the versions, the doctor's rows in Right Here's own words and the counts of the config check. "
                + "What your config says (names, commands, folders and the text of its errors) is left out and shown as `…`. "
                + "Where Right Here and its parts are installed is shown, with the home folder as `~`, and the account name is removed.",
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
