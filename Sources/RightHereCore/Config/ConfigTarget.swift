import Foundation

/// Which file of the config an edit is for: the shared `config.toml`, or this Mac's overlay `config.local.toml`.
public enum ConfigTarget: String, Sendable, Codable, Equatable, CaseIterable {
    case shared, local
}
