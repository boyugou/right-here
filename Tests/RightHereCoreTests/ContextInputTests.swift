import Foundation
import Testing
@testable import RightHereCore

@Suite("ContextInput")
struct ContextInputTests {
    private let work = URL(fileURLWithPath: "/Users/tester/work", isDirectory: true)

    @Test func theOriginIsInferredFromWhatWasPointedAt() throws {
        func origin(paths: [String], container: String?) throws -> HereContext.Origin {
            try ContextInput(paths: paths, container: container, resolution: .relative(to: work)).makeContext().origin
        }
        #expect(try origin(paths: [], container: nil) == .cli)
        #expect(try origin(paths: [], container: "/tmp") == .container)
        #expect(try origin(paths: ["a"], container: nil) == .items)
        #expect(try origin(paths: ["a"], container: "/tmp") == .items)
    }

    @Test func anExplicitOriginWinsAndAnUnknownOneIsRefused() throws {
        let toolbar = ContextInput(origin: "toolbar", paths: ["a"], resolution: .relative(to: work))
        #expect(try toolbar.makeContext().origin == .toolbar)
        let bad = ContextInput(origin: "menu", paths: [], resolution: .relative(to: work))
        #expect(throws: ContextInput.Problem.unknownOrigin("menu")) { try bad.makeContext() }
    }

    @Test func relativePathsTakeTheDirectoryAndTheTilde() throws {
        let here = try ContextInput(paths: ["src/../a.txt", "~/b.txt", "/abs/c.txt"], resolution: .relative(to: work)).makeContext()
        #expect(here.items.map(\.path) == ["/Users/tester/work/a.txt", NSHomeDirectory() + "/b.txt", "/abs/c.txt"])
    }

    @Test func anEmptyPathIsRefusedOnTheCommandLine() {
        #expect(throws: ContextInput.Problem.emptyPath) { try ContextInput(paths: [""], resolution: .relative(to: work)).makeContext() }
        #expect(throws: ContextInput.Problem.emptyPath) { try ContextInput(paths: [], container: "", resolution: .relative(to: work)).makeContext() }
    }

    @Test func absoluteOnlyRefusesAnythingElse() throws {
        for path in ["relative/file", "~/file", ""] {
            #expect(throws: ContextInput.Problem.notAbsolute) { try ContextInput(paths: [path], resolution: .absoluteOnly).makeContext() }
        }
        #expect(throws: ContextInput.Problem.notAbsolute) { try ContextInput(paths: [], container: "x", resolution: .absoluteOnly).makeContext() }
        #expect(try ContextInput(paths: ["/a/b"], resolution: .absoluteOnly).makeContext().items.map(\.path) == ["/a/b"])
    }

    @Test func aNULIsRefusedEverywhere() {
        for resolution in [ContextInput.Resolution.absoluteOnly, .relative(to: work)] {
            #expect(throws: ContextInput.Problem.containsNUL) { try ContextInput(paths: ["/a\0b"], resolution: resolution).makeContext() }
            #expect(throws: ContextInput.Problem.containsNUL) { try ContextInput(paths: [], container: "/a\0b", resolution: resolution).makeContext() }
        }
    }
}
