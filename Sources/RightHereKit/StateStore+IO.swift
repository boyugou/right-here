import Foundation
import RightHereCore

extension StateStore {
    /// Loads state from `state.toml`, returning an empty store if the file does not exist or cannot be parsed.
    public static func load(paths: RHPaths) -> StateStore {
        guard let data = try? Data(contentsOf: paths.stateFile),
              data.count < 128 * 1024,
              let text = String(data: data, encoding: .utf8) else {
            return StateStore()
        }
        return parse(text)
    }

    /// Saves state to `state.toml` atomically.
    public func save(paths: RHPaths) throws {
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        let text = render()
        try AtomicFile.write(Data(text.utf8), to: paths.stateFile)
    }
}
