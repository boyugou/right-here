import Foundation
import Testing
@testable import RightHereKit

@Suite("PathHazard")
struct PathHazardTests {
    @Test func aDotDotAfterALinkIsRefusedAndAnOrdinaryOneIsNot() throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("other/deep/er")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("fx/sub"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("fx/far"), withDestinationURL: real)
        let base = root.path
        #expect(PathHazard.linkBeforeDotDot("\(base)/fx/far/..") == true)
        #expect(PathHazard.linkBeforeDotDot("\(base)/fx/far/../x") == true)
        #expect(PathHazard.linkBeforeDotDot("\(base)/fx/sub/..") == false)
        #expect(PathHazard.linkBeforeDotDot("\(base)/fx/far") == false)
        #expect(PathHazard.linkBeforeDotDot("\(base)/fx/far/.") == false)
        #expect(PathHazard.linkBeforeDotDot("\(base)/fx/sub/../far") == false)
    }
}
