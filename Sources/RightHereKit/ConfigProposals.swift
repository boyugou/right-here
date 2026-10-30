import Foundation
import RightHereCore

/// A change an AI assistant asked for that decides which program starts or whether an agent asks first (`ConfigTrust`): it waits here until the person has looked at it and
/// applies it, or dismisses it (ADR 0026, D5).
public struct ConfigProposal: Sendable, Equatable, Codable {
    public var id: String
    public var time: Date
    public var actor: ConfigActor
    public var target: ConfigTarget
    public var operations: [ConfigOperation]
    /// What it does, in a line.
    public var summary: String
    /// The settings in it that need the person.
    public var approvals: [ConfigTrust.Approval]
    /// The digest of the two files as they were when the person looked at what it would do (`rh config pending show`), which applying it on the command line is held to; `nil`: not looked at.
    public var shownDigest: String?

    public init(id: String, time: Date, actor: ConfigActor, target: ConfigTarget, operations: [ConfigOperation], summary: String, approvals: [ConfigTrust.Approval], shownDigest: String? = nil) {
        self.id = id
        self.time = time
        self.actor = actor
        self.target = target
        self.operations = operations
        self.summary = summary
        self.approvals = approvals
        self.shownDigest = shownDigest
    }
}

/// The proposals that wait, one small file each in `.pending` next to the config.
struct ConfigProposals: Sendable {
    /// More than this many waiting are refused: an assistant that proposes without end must not bury what the person has to look at.
    static let keep = 20
    /// A proposal this old is forgotten: what it was for is not what the person remembers.
    static let lifetime: TimeInterval = 7 * 24 * 3600

    var directory: URL

    /// An id is eight lowercase hexadecimal digits; it is the name of a file, so nothing else is read as one.
    static func isValid(id: String) -> Bool {
        id.utf8.count == 8 && id.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    private func file(_ id: String) -> URL { directory.appendingPathComponent(id + ".json") }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The proposals that wait, newest first. One that is too old is removed, and a file that is not a proposal is left alone and not listed.
    func all(now: Date) -> [ConfigProposal] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".json") }
        var found: [ConfigProposal] = []
        for name in names {
            let id = String(name.dropLast(5))
            guard Self.isValid(id: id), let data = try? Data(contentsOf: file(id)), let proposal = try? decoder.decode(ConfigProposal.self, from: data), proposal.id == id else { continue }
            if now.timeIntervalSince(proposal.time) > Self.lifetime {
                remove(id)
            } else {
                found.append(proposal)
            }
        }
        return found.sorted { ($0.time, $0.id) > ($1.time, $1.id) }
    }

    /// How many wait, without removing the ones that are too old: a check only reads.
    func waitingCount(now: Date) -> Int {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".json") }
        return names.filter { name in
            let id = String(name.dropLast(5))
            guard Self.isValid(id: id), let data = try? Data(contentsOf: file(id)), let proposal = try? decoder.decode(ConfigProposal.self, from: data), proposal.id == id else { return false }
            return now.timeIntervalSince(proposal.time) <= Self.lifetime
        }.count
    }

    func proposal(_ id: String, now: Date) -> ConfigProposal? {
        guard Self.isValid(id: id) else { return nil }
        return all(now: now).first { $0.id == id }
    }

    func store(_ proposal: ConfigProposal) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try AtomicFile.write(try encoder.encode(proposal), to: file(proposal.id), mode: 0o600)
    }

    func remove(_ id: String) {
        guard Self.isValid(id: id) else { return }
        try? FileManager.default.removeItem(at: file(id))
    }
}
