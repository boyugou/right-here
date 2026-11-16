import Foundation

/// The configuration a setup read consumed. Comparing parsed state notices meaningful edits even when file dates are preserved.
public struct SetupConfigState: Sendable, Equatable {
    private let loaded: LoadedConfig
    private let linkTargets: [String?]

    init(_ loaded: LoadedConfig) {
        self.loaded = loaded
        linkTargets = [loaded.file, loaded.localFile].map { try? FileManager.default.destinationOfSymbolicLink(atPath: $0.path) }
    }
}
