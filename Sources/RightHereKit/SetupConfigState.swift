import Foundation
import RightHereCore

/// The two bounded sources a setup read consumed, including comments and symlink destinations. Dates alone miss edits that preserve them.
public struct SetupConfigState: Sendable, Equatable {
    let loaded: LoadedConfig
    private let sources: [ConfigSource]
    private let linkTargets: [String?]

    init(loaded: LoadedConfig, sources: [ConfigSource]) {
        self.loaded = loaded
        self.sources = sources
        linkTargets = [loaded.file, loaded.localFile].map { try? FileManager.default.destinationOfSymbolicLink(atPath: $0.path) }
    }

    /// A comment or a moved line refreshes the text and its checks, without rerunning the doctor and the person's login shell.
    public func changesSettings(from other: Self) -> Bool {
        func problems(_ loaded: LoadedConfig) -> [ConfigDiagnostic] {
            loaded.result.diagnostics.map { var problem = $0; problem.line = nil; return problem }
        }
        return loaded.config != other.loaded.config || loaded.fileExists != other.loaded.fileExists
            || loaded.localFileExists != other.loaded.localFileExists || loaded.result.fileLeftOut != other.loaded.result.fileLeftOut
            || problems(loaded) != problems(other.loaded) || linkTargets != other.linkTargets
    }
}
