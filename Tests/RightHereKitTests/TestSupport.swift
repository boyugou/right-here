import Foundation
import RightHereCore
@testable import RightHereKit

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rh-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

enum Shell {
    /// Runs an executable and returns its standard output.
    static func run(_ executable: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// What `git worktree list --porcelain -z` prints for a readable listing (lines, and an empty line between worktrees): every line ends with a NUL.
func porcelainZ(_ readable: String) -> String {
    readable.replacingOccurrences(of: "\n", with: "\0") + "\0\0"
}
