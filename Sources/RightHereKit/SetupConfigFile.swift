import Foundation
import RightHereCore

/// A known configuration layer, resolved from the app's paths rather than from diagnostic prose.
public enum SetupConfigFile: String, Identifiable, Sendable, CaseIterable {
    case main, local

    public var id: String { rawValue }

    public func url(relativeTo mainFile: URL) -> URL {
        switch self {
        case .main: mainFile
        case .local:
            mainFile.deletingLastPathComponent().appendingPathComponent(ConfigLayers.overlayName(forConfigFile: mainFile.lastPathComponent))
        }
    }

    static func containing(_ diagnostic: ConfigDiagnostic, mainFile: URL) -> SetupConfigFile? {
        guard let file = diagnostic.file else { return .main }
        return file == Self.local.url(relativeTo: mainFile).lastPathComponent ? .local : nil
    }
}

extension LoadedConfig {
    /// A dangling link still belongs to the setup; opening it must not silently open the other layer or create a file.
    public var setupFiles: [SetupConfigFile] {
        var files: [SetupConfigFile] = []
        if fileExists || ConfigProblem.danglingTarget(of: file) != nil { files.append(.main) }
        if localFileExists || ConfigProblem.danglingTarget(of: localFile) != nil { files.append(.local) }
        return files
    }

    /// The doctor reports a dangling link before parse errors in either layer.
    public var setupErrorFile: SetupConfigFile? {
        if let dangling = SetupConfigFile.allCases.first(where: { ConfigProblem.danglingTarget(of: $0.url(relativeTo: file)) != nil }) {
            return dangling
        }
        return result.diagnostics.first { $0.severity == .error }.flatMap { SetupConfigFile.containing($0, mainFile: file) }
    }
}
