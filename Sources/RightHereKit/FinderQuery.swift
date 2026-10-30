import Foundation
import RightHereCore

/// What Finder is showing right now.
public struct FinderState: Sendable, Equatable, Codable {
    /// The selected items of the frontmost Finder window (or the desktop).
    public var selection: [String]
    /// The folder shown by the frontmost Finder window, or the Desktop when there is none.
    public var frontWindowFolder: String?

    public init(selection: [String], frontWindowFolder: String?) {
        self.selection = selection
        self.frontWindowFolder = frontWindowFolder
    }
}

/// Asks Finder what is selected. This sends Apple events, so macOS asks the person once to let
/// the calling app control Finder; the answer is a clear error until they do.
public struct FinderQuery: Sendable {
    private let runner: any ProcessRunner

    public init(runner: any ProcessRunner = LiveProcessRunner()) {
        self.runner = runner
    }

    /// Constant JavaScript for Automation. It returns JSON, so no file name can break the parsing.
    static let script = """
    ObjC.import('Foundation');
    function pathOf(item) {
      return ObjC.unwrap($.NSURL.URLWithString(item.url()).path);
    }
    function run() {
      const finder = Application('Finder');
      let selection = [];
      try { selection = finder.selection().map(pathOf); } catch (error) {}
      let folder = null;
      try {
        const windows = finder.finderWindows();
        folder = windows.length > 0 ? pathOf(windows[0].target()) : pathOf(finder.desktop());
      } catch (error) {}
      return JSON.stringify({ selection: selection, frontWindowFolder: folder });
    }
    """

    public func current() async throws -> FinderState {
        let result = try await runner.run(
            ProcessStep(executable: "/usr/bin/osascript", arguments: ["-l", "JavaScript", "-"], standardInput: Self.script),
            timeout: .seconds(15)
        )
        guard result.status == 0 else {
            if result.standardError.contains("(-1743)") { throw ExecutionError.automationDenied(application: "Finder") }
            throw ExecutionError.stepFailed(index: 0, step: "ask Finder for its selection",
                                            message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try Self.parse(result.standardOutput)
    }

    static func parse(_ output: String) throws -> FinderState {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return try JSONDecoder().decode(FinderState.self, from: Data(text.utf8))
    }
}
