import Foundation
import Testing
@testable import RightHereCore

private func facts(gitRoots: [String] = ["/Users/tester/code/app"]) -> FakeSystemFacts {
    FakeSystemFacts(
        directories: ["/Users/tester", "/Users/tester/code/app", "/Users/tester/code/app/src", "/Volumes/Data"],
        files: ["/Users/tester/code/app/src/main.swift", "/Users/tester/code/app/My Notes.md", "/Volumes/Data/x.txt"],
        gitRoots: gitRoots
    )
}

@Suite("PathRenderer")
struct PathRendererTests {
    private let nested = URL(fileURLWithPath: "/Users/tester/code/app/src/main.swift")
    private let spaced = URL(fileURLWithPath: "/Users/tester/code/app/My Notes.md")
    private let outside = URL(fileURLWithPath: "/Volumes/Data/x.txt")

    @Test func absolute() {
        #expect(PathRenderer(facts: facts()).render(nested, style: .absolute) == "/Users/tester/code/app/src/main.swift")
    }

    @Test func tildeInsideAndOutsideHome() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render(nested, style: .tilde) == "~/code/app/src/main.swift")
        #expect(renderer.render(URL(fileURLWithPath: "/Users/tester"), style: .tilde) == "~")
        #expect(renderer.render(outside, style: .tilde) == "/Volumes/Data/x.txt")
    }

    @Test func tildeDoesNotMatchSiblingWithSamePrefix() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render(URL(fileURLWithPath: "/Users/tester2/file"), style: .tilde) == "/Users/tester2/file")
    }

    @Test func gitRelative() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render(nested, style: .gitRelative) == "src/main.swift")
        #expect(renderer.render(URL(fileURLWithPath: "/Users/tester/code/app"), style: .gitRelative) == ".")
        #expect(renderer.render(outside, style: .gitRelative) == "/Volumes/Data/x.txt")
    }

    @Test func gitRelativeFallsBackToAbsoluteWithoutRepository() {
        let renderer = PathRenderer(facts: facts(gitRoots: []))
        #expect(renderer.render(nested, style: .gitRelative) == "/Users/tester/code/app/src/main.swift")
    }

    @Test func nameAndParent() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render(spaced, style: .name) == "My Notes.md")
        #expect(renderer.render(spaced, style: .parent) == "/Users/tester/code/app")
    }

    @Test func shellStyles() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render(spaced, style: .shellEscaped) == "/Users/tester/code/app/My\\ Notes.md")
        #expect(renderer.render(spaced, style: .shellQuoted) == "'/Users/tester/code/app/My Notes.md'")
    }

    @Test func fileURL() {
        #expect(PathRenderer(facts: facts()).render(spaced, style: .fileURL) == "file:///Users/tester/code/app/My%20Notes.md")
    }

    @Test func aiMention() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render(nested, style: .aiMention) == "@src/main.swift")
        #expect(renderer.render(spaced, style: .aiMention) == "@\"My Notes.md\"")
        #expect(renderer.render(outside, style: .aiMention) == "@/Volumes/Data/x.txt")
    }

    @Test func markdownLink() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render(nested, style: .markdownLink) == "[main.swift](src/main.swift)")
        #expect(renderer.render(spaced, style: .markdownLink) == "[My Notes.md](<My Notes.md>)")
    }

    @Test func severalItemsJoinPerStyle() {
        let renderer = PathRenderer(facts: facts())
        #expect(renderer.render([nested, spaced], style: .name) == "main.swift\nMy Notes.md")
        #expect(renderer.render([nested, spaced], style: .aiMention) == "@src/main.swift @\"My Notes.md\"")
        #expect(renderer.render([nested, spaced], style: .shellEscaped)
                == "/Users/tester/code/app/src/main.swift /Users/tester/code/app/My\\ Notes.md")
    }

    @Test func standardizesDotComponents() {
        let url = URL(fileURLWithPath: "/Users/tester/code/app/src/../src/./main.swift")
        #expect(PathRenderer(facts: facts()).render(url, style: .absolute) == "/Users/tester/code/app/src/main.swift")
    }

    @Test func repositoryAtHomeIsIgnored() {
        let renderer = PathRenderer(facts: facts(gitRoots: ["/Users/tester"]))
        #expect(renderer.render(nested, style: .gitRelative) == "/Users/tester/code/app/src/main.swift")
    }

    @Test func nestedRepositoryWinsOverOuter() {
        let renderer = PathRenderer(facts: facts(gitRoots: ["/Users/tester/code", "/Users/tester/code/app"]))
        #expect(renderer.render(nested, style: .gitRelative) == "src/main.swift")
    }
}
