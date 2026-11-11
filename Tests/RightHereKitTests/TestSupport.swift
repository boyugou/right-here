import Foundation
import RightHereCore
@testable import RightHereKit

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rh-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

enum Shell {
    /// Runs an executable and returns its standard output. `environment` replaces the process's own when it is given.
    static func run(_ executable: String, args: [String], environment: [String: String]? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let environment { process.environment = environment }
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

/// git for a test's own repositories: none of the person's configuration is read (a `core.hooksPath` or `init.templateDir` of their `~/.gitconfig` would run
/// in a test's commits), and the commits need no identity of theirs.
enum TestGit {
    static func run(_ arguments: [String], in directory: URL) throws -> String {
        let environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.temporaryDirectory.path, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]
        return try Shell.run("/usr/bin/git", args: ["-C", directory.path, "-c", "commit.gpgsign=false", "-c", "user.name=Test", "-c", "user.email=test"] + arguments,
                             environment: environment)
    }

    /// A repository with one commit of a README (and a `.gitignore` of `ignoring`, when given).
    static func repository(ignoring patterns: [String] = []) throws -> URL {
        let directory = try makeTemporaryDirectory()
        _ = try run(["init", "-q"], in: directory)
        try "initial".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        _ = try run(["add", "README.md"], in: directory)
        if !patterns.isEmpty {
            try (patterns.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
            _ = try run(["add", ".gitignore"], in: directory)
        }
        _ = try run(["commit", "-q", "-m", "initial"], in: directory)
        return directory
    }
}
