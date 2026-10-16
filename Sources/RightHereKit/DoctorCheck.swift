import Foundation
import RightHereCore

/// One line of what `rh doctor` and the setup window report: which check, how it stands and what it says.
///
/// What a check says is kept as catalog messages and not as sentences: the command line and the MCP server write them in
/// English, the setup window in the language of the system, from the same data.
public struct DoctorCheck: Sendable, Equatable, Encodable, Identifiable {
    public enum Status: String, Sendable, Encodable {
        case ok
        case warn
        case fail
        /// Only the person can fix it, for example by switching a Finder extension on in System Settings.
        case needsUser = "needs-user"
    }

    public var id: CheckID
    /// The title in English; for an agent, the agent's own name. `title(in:)` gives it in another language.
    public var title: String
    public var status: Status
    /// What was found.
    public var detail: LocalizedMessage?
    /// More that goes with it, a line each: the per-machine overlay the config is merged with, a config file that is a symlink.
    public var notes: [LocalizedMessage]
    /// What to do about it.
    public var fix: LocalizedMessage?

    public init(_ id: CheckID, title: String? = nil, status: Status, detail: LocalizedMessage? = nil, notes: [LocalizedMessage] = [], fix: LocalizedMessage? = nil) {
        self.id = id
        self.title = title ?? id.titleKey.map { Localizer.english.string($0) } ?? id.rawValue
        self.status = status
        self.detail = detail
        self.notes = notes
        self.fix = fix
    }

    /// The title in a language, which is the agent's own name for an agent's check.
    public func title(in localizer: Localizer) -> String {
        id.titleKey.map { localizer.string($0) } ?? title
    }

    /// For a row that can quote the config (`CheckID.quotesTheConfig`): which values of which messages are Right Here's own and not the config's text: where it looks for
    /// the config, the overlay, which of the two files is a link, the sync state's file, the origin and the age of the last action started from Finder (its id is
    /// the config's), and the constants that a fix quotes. `rh doctor --report` shows these and leaves every other value out; a report an agent reads fences every other value.
    static let ownValues: [LocalizationKey: Set<Int>] = [
        .doctorConfigMissing: [0], .doctorConfigOverlay: [0], .doctorConfigSymlink: [0], .doctorSyncStateUnreadable: [0],
        .doctorActivityRecent: [1, 2],
        // Constants of Right Here's own that a fix quotes (`launcher = "link"`, `agents = ["claude"]`).
        .doctorFixAgentsAdd: [0], .doctorFixAgentLauncher: [0, 1]
    ]

    /// The check as the command line and the MCP server print it, in English.
    ///
    /// What a row that can quote the config (`CheckID.quotesTheConfig`: an app's or an agent's name, a command, the error that quotes a value) says is fenced as
    /// data, value by value, so that Right Here's own words stay outside the fences (`Fence`, ADR 0020): the config can come through the sync folder, and an AI
    /// agent that reads this must be able to tell it from the tool's own words. `quote` replaces that for the MCP server, which fences the whole text of every row.
    public func englishLines(quoting quote: ((String) -> String)? = nil) -> [String] {
        func said(_ message: LocalizedMessage) -> String {
            if let quote { return quote(message.english()) }
            return id.quotesTheConfig ? message.englishMarkingValues(except: Self.ownValues[message.key] ?? []) : message.english()
        }
        let name = id.isAgent ? (quote ?? Fence.wrap)(title) : title
        var lines = ["[\(status.rawValue)] \(name)" + (detail.map { ": " + said($0) } ?? "")]
        lines += notes.map { "       note: " + said($0) }
        if let fix { lines.append("       fix: " + said(fix)) }
        return lines
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, status, detail, notes, fix
    }

    /// `rh doctor --json`: `detail`, `notes` and `fix` are messages that carry their English text, so a person or an AI
    /// agent reads `text` and a program can act on `code` and `args`. With `CodingUserInfoKey.fencesQuotedText` set (the command line's printer sets it), the
    /// `text` of a row that can quote the config has what it quotes fenced as data; `args` and `title` hold the values as they are.
    public func encode(to encoder: any Encoder) throws {
        let fencing = encoder.userInfo[.fencesQuotedText] as? Bool == true && id.quotesTheConfig
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.rawValue, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(detail.map { MessageText($0, fencing: fencing) }, forKey: .detail)
        if !notes.isEmpty { try container.encode(notes.map { MessageText($0, fencing: fencing) }, forKey: .notes) }
        try container.encodeIfPresent(fix.map { MessageText($0, fencing: fencing) }, forKey: .fix)
    }
}

extension CodingUserInfoKey {
    /// Set on an encoder whose output an AI agent reads, as the command line's JSON is: what a check quotes from the config is fenced in its `text`. The MCP server's
    /// structured data does not set it, which keeps that data plain; the text of the MCP result fences it instead.
    public static let fencesQuotedText: CodingUserInfoKey = {
        guard let key = CodingUserInfoKey(rawValue: "com.boyugou.righthere.fencesQuotedText") else { fatalError("an empty key") }
        return key
    }()
}

/// A message as `LocalizedMessage` encodes it (`code`, `args`, `text`), with the values in `text` fenced when the row quotes the config.
private struct MessageText: Encodable {
    let message: LocalizedMessage
    let fencing: Bool

    init(_ message: LocalizedMessage, fencing: Bool) {
        self.message = message
        self.fencing = fencing
    }

    private enum CodingKeys: String, CodingKey {
        case code, args, text
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message.key.rawValue, forKey: .code)
        try container.encode(message.arguments, forKey: .args)
        try container.encode(fencing ? message.englishMarkingValues(except: DoctorCheck.ownValues[message.key] ?? []) : message.english(), forKey: .text)
    }
}

extension Array where Element == DoctorCheck {
    /// The checks with `check` in the place of the one that has its id; the order is kept. When none has that id the list
    /// comes back as it is, since where a new row would go is not known. For looking at one check again without
    /// running the whole doctor.
    public func replacing(_ check: DoctorCheck) -> [DoctorCheck] {
        map { $0.id == check.id ? check : $0 }
    }

    /// The checks with `check` in the place of the one that has its id, or at the end when there is none: for a row that
    /// only some runs of the doctor have, such as the launch probe.
    public func replacingOrAppending(_ check: DoctorCheck) -> [DoctorCheck] {
        contains { $0.id == check.id } ? replacing(check) : self + [check]
    }
}
