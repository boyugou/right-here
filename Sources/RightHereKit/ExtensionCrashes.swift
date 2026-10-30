import Foundation

/// The crash reports macOS wrote for the code of the Finder extension that is installed.
///
/// A crashing extension looks healthy to `pluginkit` (registered, switched on) and to the launch probe, which does not do what Finder asks of an
/// extension by itself, such as watching a folder. The person sees a context menu without Right Here's entries and every check ok (ADR 0019), so
/// the doctor looks at what macOS wrote down. The window of the Mac App Store edition is sandboxed, cannot read that folder and leaves the row as it is.
///
/// Whose crash a report is, is told by its first line: macOS writes a JSON header (`.ips`) that names the UUID of the code that crashed (`slice_uuid`), and the installed
/// extension's executable has the same UUID in its `LC_UUID` (`MachOUUID`). A report of another build (the copy that was replaced, written after it was built and before
/// the new one was put in place) does not count against this one. Copying an app keeps the dates of its files (`cp -Rp`, `ditto`: measured), so the date the code was written
/// cannot say when a copy arrived; it is what is used for a report that has no UUID (a `.crash` file, a header that cannot be read) and when the executable has none.
public struct ExtensionCrashes: Sendable, Equatable {
    public var count: Int
    public var latest: Date
    public var latestFile: String
    /// The reports were matched to the installed code by its UUID, and not by the date it was written.
    public var matchedByBuild = false

    /// The name macOS gives a report: the executable's name, the date, and `.ips` (or `.crash` on an older system).
    static let namePrefix = "FinderExtension-"
    static let reportExtensions: Set<String> = ["ips", "crash"]
    /// A report older than this says nothing about the extension as it is now.
    static let window: TimeInterval = 7 * 24 * 3600

    public static func reportsFolder(home: URL) -> URL {
        home.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    /// When the installed extension's code was written: the reports from before that are about another copy. `nil` when it cannot be told.
    public static func installDate(ofExtensionAt path: String) -> Date? {
        let executable = URL(fileURLWithPath: path).appendingPathComponent("Contents/MacOS/" + String(namePrefix.dropLast()))
        for candidate in [executable, URL(fileURLWithPath: path)] {
            if let date = (try? FileManager.default.attributesOfItem(atPath: candidate.path))?[.modificationDate] as? Date { return date }
        }
        return nil
    }

    /// The UUIDs of the code of the extension at `path` (the `.appex`), or `nil` when its executable cannot be read.
    public static func buildIDs(ofExtensionAt path: String) -> Set<String>? {
        MachOUUID.uuids(ofFileAt: URL(fileURLWithPath: path).appendingPathComponent("Contents/MacOS/" + String(namePrefix.dropLast())).path)
    }

    /// The `slice_uuid` of the crash report at `url`, from its first line, or `nil` when it has none (a text report, a header that is not JSON).
    static func sliceUUID(ofReportAt url: URL) -> String? {
        guard let handle = MachOUUID.openRegularFile(at: url.path) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 8192) else { return nil }
        let line = head.split(separator: UInt8(ascii: "\n"), maxSplits: 1, omittingEmptySubsequences: false).first ?? head[...]
        guard let header = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any], let uuid = header["slice_uuid"] as? String else { return nil }
        return uuid.lowercased()
    }

    /// `nil` when there is no report of this code in the window, or when the folder cannot be read. `buildIDs` are the UUIDs of the installed code
    /// (`buildIDs(ofExtensionAt:)`): a report that names another UUID is of another build and is left out, whenever it was written; one that names none is counted when it was written
    /// after `installed`.
    public static func scan(in folder: URL, installedAfter installed: Date?, buildIDs: Set<String>? = nil, now: Date = Date()) -> ExtensionCrashes? {
        // Names only: the folder holds a report for every program that crashed on this Mac, and only this one's are looked at.
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        let start = now.addingTimeInterval(-window)
        let known = buildIDs?.isEmpty == false ? buildIDs : nil
        var reports: [(date: Date, name: String)] = []
        var matched = false
        for name in names where name.hasPrefix(namePrefix) && reportExtensions.contains((name as NSString).pathExtension) {
            let url = folder.appendingPathComponent(name)
            guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, date >= start else { continue }
            if let known, let uuid = sliceUUID(ofReportAt: url) {
                guard known.contains(uuid) else { continue }
                matched = true
            } else {
                guard date >= (installed ?? .distantPast) else { continue }
            }
            reports.append((date, name))
        }
        guard let newest = reports.max(by: { $0.date < $1.date }) else { return nil }
        return ExtensionCrashes(count: reports.count, latest: newest.date, latestFile: newest.name, matchedByBuild: matched)
    }

    /// What the doctor says: English in every language, as the report is a file name and a count for a person who will attach it to a bug report.
    func detail(now: Date) -> String {
        let relative = RelativeDateTimeFormatter()
        relative.locale = Locale(identifier: "en")
        relative.unitsStyle = .full
        let times = count == 1 ? "once" : "\(count) times"
        // The name is whatever a program of the person's wrote into that folder: its control and invisible characters are shown as escapes.
        let latest = "the latest \(relative.localizedString(for: latest, relativeTo: now)): \(latestFile.withControlCharactersEscaped)"
        return matchedByBuild ? "switched on, but this build of it crashed \(times) in the last week (\(latest))" : "switched on, but it crashed \(times) since this copy was installed (\(latest))"
    }

    static let fix = "A crashed extension leaves Finder's context menu without Right Here's entries. Read the report in ~/Library/Logs/DiagnosticReports and attach it to a bug report; `rh docs troubleshooting` says what to try first."
}
