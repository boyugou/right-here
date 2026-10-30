import Foundation
import Testing
@testable import RightHereKit

@Suite("Setup window: how a path is written")
struct PathDisplayTests {
    private let home = "/Users/tester"

    @Test func aPathUnderTheHomeStartsFromATilde() {
        #expect(PathDisplay.abbreviatingHome("/Users/tester/.config/right-here/config.toml", home: home) == "~/.config/right-here/config.toml")
    }

    @Test func theHomeFolderItselfIsATilde() {
        #expect(PathDisplay.abbreviatingHome("/Users/tester", home: home) == "~")
    }

    @Test func everyPathInASentenceIsAbbreviated() {
        let text = "linked at /Users/tester/.local/bin/rh, but /Users/tester/.local/bin is not on PATH"
        #expect(PathDisplay.abbreviatingHome(text, home: home) == "linked at ~/.local/bin/rh, but ~/.local/bin is not on PATH")
    }

    @Test func aQuotedOrBracketedPathIsAbbreviatedToo() {
        #expect(PathDisplay.abbreviatingHome("\"/Users/tester/a\" (`/Users/tester/b`)", home: home) == "\"~/a\" (`~/b`)")
    }

    @Test func anotherFolderWithTheSameBeginningIsLeftAlone() {
        #expect(PathDisplay.abbreviatingHome("/Users/tester2/Projects", home: home) == "/Users/tester2/Projects")
        #expect(PathDisplay.abbreviatingHome("/Users/tester-old/Projects", home: home) == "/Users/tester-old/Projects")
    }

    @Test func aHomeInsideAnotherPathIsAnotherFolder() {
        // The window used to replace the home wherever it found it, which rewrote a backup disk's copy of the home.
        #expect(PathDisplay.abbreviatingHome("/Volumes/Backup/Users/tester/Projects", home: home) == "/Volumes/Backup/Users/tester/Projects")
    }

    @Test func aTrailingSlashOfTheHomeChangesNothing() {
        #expect(PathDisplay.abbreviatingHome("/Users/tester/x", home: "/Users/tester/") == "~/x")
    }

    @Test func aHomeThatIsTheRootAbbreviatesNothing() {
        #expect(PathDisplay.abbreviatingHome("/usr/bin", home: "/") == "/usr/bin")
        #expect(PathDisplay.abbreviatingHome("/usr/bin", home: "") == "/usr/bin")
    }

    @Test func anAccountNameWithLettersBeyondAsciiWorks() {
        #expect(PathDisplay.abbreviatingHome("/Volumes/Büro/Projekte", home: "/Volumes/Büro") == "~/Projekte")
        #expect(PathDisplay.abbreviatingHome("/Volumes/Büroarbeit/Projekte", home: "/Volumes/Büro") == "/Volumes/Büroarbeit/Projekte")
    }

    @Test func aHomeWithRegularExpressionCharactersIsTakenLiterally() {
        #expect(PathDisplay.abbreviatingHome("/Volumes/a.b+c/x", home: "/Volumes/a.b+c") == "~/x")
        #expect(PathDisplay.abbreviatingHome("/Volumes/aXb+c/x", home: "/Volumes/a.b+c") == "/Volumes/aXb+c/x")
    }

    /// The marks a folder adds: a left-to-right mark at its start and on each side of a slash.
    private func withoutMarks(_ text: String) -> String {
        text.filter { $0 != "\u{200E}" }
    }

    @Test func aFolderInAListIsKeptInOnePieceLeftToRight() {
        let shown = PathDisplay.folder("/Users/tester/مستندات/مشروع", home: home)
        #expect(shown.hasPrefix("\u{200E}"))
        // A left-to-right mark on each side of every slash: the names between them keep their order.
        #expect(shown.contains("/\u{200E}مستندات\u{200E}/") || shown.contains("\u{200E}/\u{200E}مستندات"))
        #expect(withoutMarks(shown) == "~/مستندات/مشروع")
    }

    @Test func theMarksAreTheOnlyThingAFolderGains() {
        let path = "/Volumes/Work/app"
        #expect(withoutMarks(PathDisplay.folder(path, home: home)) == path)
        #expect(withoutMarks(PathDisplay.folder("", home: home)) == "")
    }
}
