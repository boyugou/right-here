import Foundation

/// The crash reports macOS wrote for the Finder extension since this copy of it was installed.
///
/// A crashing extension looks healthy to `pluginkit` (registered, switched on) and to the launch probe, which does not do what Finder asks of an
/// extension by itself, such as watching a folder. The person sees a context menu without Right Here's entries and every check ok (ADR 0019), so
/// the doctor looks at what macOS wrote down. The window of the Mac App Store edition is sandboxed, cannot read that folder and leaves the row as it is.
public struct ExtensionCrashes: Sendable, Equatable {
    public var count: Int
    public var latest: Date
    public var latestFile: String

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

    /// `nil` when there is no report in the window, or when the folder cannot be read.
    public static func scan(in folder: URL, installedAfter installed: Date?, now: Date = Date()) -> ExtensionCrashes? {
        // Names only: the folder holds a report for every program that crashed on this Mac, and only this one's are looked at.
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        let cutoff = max(installed ?? .distantPast, now.addingTimeInterval(-window))
        var reports: [(date: Date, name: String)] = []
        for name in names where name.hasPrefix(namePrefix) && reportExtensions.contains((name as NSString).pathExtension) {
            let url = folder.appendingPathComponent(name)
            guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, date >= cutoff else { continue }
            reports.append((date, name))
        }
        guard let newest = reports.max(by: { $0.date < $1.date }) else { return nil }
        return ExtensionCrashes(count: reports.count, latest: newest.date, latestFile: newest.name)
    }

    /// What the doctor says: English in every language, as the report is a file name and a count for a person who will attach it to a bug report.
    func detail(now: Date) -> String {
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        let times = count == 1 ? "once" : "\(count) times"
        // The name is whatever a program of the person's wrote into that folder: its control and invisible characters are shown as escapes.
        return "switched on, but it crashed \(times) since this copy was installed (the latest \(relative.localizedString(for: latest, relativeTo: now)): \(latestFile.withControlCharactersEscaped))"
    }

    static let fix = "A crashed extension leaves Finder's context menu without Right Here's entries. Read the report in ~/Library/Logs/DiagnosticReports and attach it to a bug report; `rh docs troubleshooting` says what to try first."
}
