import Foundation
import RightHereCore

/// One line of what `rh doctor` and the setup window report: which check, how it stands and what it says.
///
/// What a check says is kept as catalog messages and not as sentences: the command line and the MCP server write them in
/// English, the setup window in the language of the system, from the same data.
public struct DoctorCheck: Sendable, Equatable, Encodable {
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

    /// The check as the command line and the MCP server print it, in English. `quoting` marks what may have been written
    /// by somebody else (a config problem, a command, an agent's name): the MCP server fences it for the agent that reads it.
    public func englishLines(quoting quote: (String) -> String = { $0 }) -> [String] {
        var lines = ["[\(status.rawValue)] \(id.isAgent ? quote(title) : title)" + (detail.map { ": " + quote($0.english()) } ?? "")]
        lines += notes.map { "       note: " + quote($0.english()) }
        if let fix { lines.append("       fix: " + quote(fix.english())) }
        return lines
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, status, detail, notes, fix
    }

    /// `rh doctor --json`: `detail`, `notes` and `fix` are messages that carry their English text, so a person or an AI
    /// agent reads `text` and a program can act on `code` and `args`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.rawValue, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(detail, forKey: .detail)
        if !notes.isEmpty { try container.encode(notes, forKey: .notes) }
        try container.encodeIfPresent(fix, forKey: .fix)
    }
}

extension Array where Element == DoctorCheck {
    /// The checks with `check` in the place of the one that has its id; the order is kept. When none has that id the list
    /// comes back as it is, since where a new row would go is not known. For looking at one check again without
    /// running the whole doctor.
    public func replacing(_ check: DoctorCheck) -> [DoctorCheck] {
        map { $0.id == check.id ? check : $0 }
    }
}
