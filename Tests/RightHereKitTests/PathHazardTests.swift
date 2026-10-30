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

    @Test func aMarkAfterASlashDoesNotHideADotDotAfterALink() throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("other/deep/er")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("fx"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("fx/far"), withDestinationURL: real)
        let base = root.path
        // To the kernel these are the components fx, far, .., <U+0301>x: the same link-then-dot-dot hazard as the plain spelling.
        #expect(PathHazard.linkBeforeDotDot("\(base)/fx/far/../\u{301}x") == true, "the hazard was hidden by a combining mark after the slash")
        #expect(PathHazard.linkBeforeDotDot("\(base)/fx/far/..\u{301}") == false, "a name that merely starts with two dots is not a dot-dot")
        #expect(PathHazard.linkBeforeDotDot("\(base)/fx/far/.\u{301}./x") == false)
        // The component before the dot-dot is cut at the kernel's slash too.
        #expect(PathHazard.linkBeforeDotDot("\(base)/fx/\u{301}far/../x") == false, "a different name is not the link")
        #expect(PathHazard.linkBeforeDotDot("\(base)/fx//far///..//\u{301}x") == true)
    }
}
