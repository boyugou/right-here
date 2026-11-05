import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

/// From an independent review of the Finder click path (2026-11-04): what `rh run --alert` shows, and what the extension's own config read costs. Nothing here
/// shows a window: `FailureAlert.content` is built and read, never `show`n.
@Suite("The Finder click path: the alert of a failed New File, and the config read", .serialized)
struct FinderPathAlertTests {
    /// `LiveExecutor.createFile` names its step `"create \(file.path)"`, raw, where every other step is named by `Step.summary`, which quotes the
    /// path (`jsonQuoted`). `ExecutionError.shownSentences` then keeps line breaks in every value of `refusalStepFailed` (meant for what a
    /// program wrote), so a line break in a folder's name reaches the alert body as a line of its own, under Right Here's title.
    @Test func aFolderNameCannotAddLinesToTheAlertOfAFailedNewFile() async throws {
        let root = try makeTemporaryDirectory()
        let folder = root.appendingPathComponent("notes\nRight Here needs your password. Choose Open Settings to continue")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A folder that cannot be written to: a read-only disk image, a share, or a folder unpacked from an archive with these permissions.
        #expect(chmod(folder.path, 0o555) == 0)
        defer {
            _ = chmod(folder.path, 0o755)
            try? FileManager.default.removeItem(at: root)
        }
        let plan = LaunchPlan(action: "new-file.txt", summary: "Create untitled.txt",
                              steps: [.createFile(CreateFileStep(path: folder.appendingPathComponent("untitled.txt").path))])
        do {
            try await LiveExecutor(runner: FakeProcessRunner(), pasteboard: RecordingPasteboard()).execute(plan)
            Issue.record("creating a file in a folder that cannot be written to succeeded")
        } catch {
            let content = FailureAlert.content(for: error, action: "new-file.txt", localizer: .english)
            #expect(!content.message.contains("\nRight Here needs your password"), "the alert reads:\n\(content.message)")
        }
    }

    /// The name of a step is Right Here's own and may hold a path: shown on one line, while what the program wrote keeps its lines.
    @Test func theNameOfAStepIsShownOnOneLineAndWhatTheProgramWroteKeepsItsLines() {
        let failure = ExecutionError.stepFailed(index: 0, step: "create /x/a\nb", message: "line one\nline two")
        let shown = Localizer.english.render(sentences: failure.shownSentences)
        #expect(shown.contains("/x/a\\nb") && shown.contains("line one\nline two"), Comment(rawValue: shown))
    }

    /// The call the extension makes on its main thread in `menu(for:)` when the config's stamp changed, with a 48 KB config whose only
    /// fault is a long table header (refused as a syntax error, so the defaults apply).
    @Test func theConfigReadThatTheFinderMenuWaitsForStaysFastForALongTableHeader() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let paths = RHPaths(environment: ["RH_CONFIG_DIR": folder.path, "RH_LOG_DIR": folder.appendingPathComponent("logs").path], home: folder)
        try ("[" + Array(repeating: "a", count: 24_000).joined(separator: ".") + "]\nx = 1\n").write(to: paths.configFile, atomically: true, encoding: .utf8)
        let start = ContinuousClock.now
        let loaded = ConfigStore.load(paths: paths)
        let elapsed = ContinuousClock.now - start
        #expect(loaded.result.diagnostics.contains { $0.severity == .error })
        #expect(elapsed < .seconds(3), "ConfigStore.load took \(elapsed)")
    }
}
