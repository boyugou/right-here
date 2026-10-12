import Foundation

/// A dotted application version such as `1.3.1`. Anything after the leading digits and dots
/// (a build suffix like `-dev+abc123`) is ignored, and missing components count as zero.
public struct AppVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ text: String) {
        let numeric = text.prefix { $0.isASCII && ($0.isNumber || $0 == ".") }
        let parts = numeric.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return nil }
        components = parts.compactMap { $0 }
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
