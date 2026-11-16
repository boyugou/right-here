import Foundation
import Testing
@testable import RightHereKit

@Suite("Finding a saved folder")
struct FolderSearchTests {
    private let home = "/Users/tester"
    private let locale = Locale(identifier: "en_US_POSIX")

    @Test(arguments: ["resume", "RÉSUMÉ", "projects 2026", "2026 resume", "~/Projects/Résumé 2026", "\t résumé  2026\n"])
    func namesPathsAndSeparateWordsFindTheSameFolder(_ query: String) {
        let paths = [home + "/Projects/Résumé 2026", home + "/Notes/Résumé 2025", "/Volumes/Archive"]
        let matches = FolderSearch(query, locale: locale).filter(paths, home: home)
        if query == "resume" || query == "RÉSUMÉ" { #expect(matches == Array(paths.prefix(2))) }
        else { #expect(matches == [paths[0]]) }
    }

    @Test func anEmptyQueryKeepsTheOriginalOrderAndAQueryDoesNotSortTheMatches() {
        let paths = ["/work/zeta", "/work/alpha", "/work/middle"]
        #expect(FolderSearch(" \n\t", locale: locale).isEmpty)
        #expect(FolderSearch(" \n\t", locale: locale).filter(paths, home: home) == paths)
        #expect(FolderSearch("work a", locale: locale).filter(paths, home: home) == [paths[0], paths[1]])
    }

    @Test func everyWordMustMatchAndPunctuationIsLiteral() {
        let paths = ["/work/notes [final]", "/work/notes draft", "/work/reports"]
        #expect(FolderSearch("notes final", locale: locale).filter(paths, home: home) == [paths[0]])
        #expect(FolderSearch("notes reports", locale: locale).filter(paths, home: home).isEmpty)
        #expect(FolderSearch("[final]", locale: locale).filter(paths, home: home) == [paths[0]])
        #expect(FolderSearch(".*", locale: locale).filter(paths, home: home).isEmpty)
    }

    @Test func homeAbbreviationsDoNotMatchAnotherPersonsHome() {
        let paths = [home, home + "/notes", home + "2/notes", "/Volumes/Backup" + home + "/notes"]
        #expect(FolderSearch("~", locale: locale).filter(paths, home: home) == Array(paths.prefix(2)))
        #expect(FolderSearch("~/notes", locale: locale).filter(paths, home: home) == [paths[1]])
    }

    @Test func escapedNamesAndNonLatinNamesCanBeFoundAsDisplayed() {
        let paths = ["/work/report\n2026", "/work/\u{202E}notes", "/work/研究/报告", "/work/Ｐｒｏｊｅｃｔ"]
        #expect(FolderSearch("report\\n2026", locale: locale).filter(paths, home: home) == [paths[0]])
        #expect(FolderSearch("\\u202e", locale: locale).filter(paths, home: home) == [paths[1]])
        #expect(FolderSearch("研究 报告", locale: locale).filter(paths, home: home) == [paths[2]])
        #expect(FolderSearch("project", locale: locale).filter(paths, home: home) == [paths[3]])
    }

    @Test func caseMatchingUsesTheLanguageTheCallerSpecified() {
        let paths = ["/work/ISPARTA", "/work/izmir"]
        #expect(FolderSearch("ısparta", locale: Locale(identifier: "tr")).filter(paths, home: home) == [paths[0]])
    }
}
